import Foundation

/// The page `KhalaWebKitLivePlayer` loads into its small WKWebView: Apple's own WebRTC (WebKit), which negotiates the
/// H.265 that Hikvision-style cameras stream through go2rtc, where the app's bundled Google libwebrtc offers only
/// H.264/VP8 and falls back to HLS. It mirrors the frontend's `ha-web-rtc-player` (home-assistant/frontend
/// `src/components/ha-web-rtc-player.ts` at 20260930.4, the frontend HA 2026.10.2 serves): an `RTCPeerConnection`
/// on the server's ICE configuration, an optional data channel, recvonly audio + video transceivers, negotiation on
/// `negotiationneeded`, the remote stream into a muted inline `<video>`.
///
/// The page never talks to Home Assistant itself: it has no URL, no token and no remote script. Signaling goes
/// through native (`KhalaWebRTCSignaling`), which rides the app's existing websocket:
///
/// - page → native, `window.webkit.messageHandlers.khala.postMessage(...)`, one of `KhalaWebRTCPageMessage`:
///   `ready`, `offer {sdp}`, `candidate {candidate}`, `ice {state}`, `frame {width, height, how}`,
///   `codec {mimeType}`, `error {message}` (fatal) and `note {message}` (logged only);
/// - native → page, `window.khala.start(config)`, `.answer(sdp)`, `.candidate(init)`, `.setMuted(bool)`,
///   `.stop()` (see `KhalaWebRTCPageCommand`).
///
/// Errors are reported by message only — never the SDP, a candidate or the ICE configuration (which can carry TURN
/// credentials), and nothing is written to the console.
enum KhalaWebRTCPage {
    /// The name of the script message handler the page posts to.
    static let messageHandler = "khala"

    /// `object-fit` for the video: `cover` fills the 16:9 card the way its poster still does, `contain` letterboxes
    /// full screen the way the native player did.
    enum Fit: String {
        case cover
        case contain
    }

    /// The whole page. `{{FIT}}` is replaced by `html(fit:)`.
    static func html(fit: Fit) -> String {
        template.replacingOccurrences(of: "{{FIT}}", with: fit.rawValue)
    }

    private static let template = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: transparent;
  -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: {{FIT}}; background: transparent;
  pointer-events: none; }
</style>
</head>
<body>
<video id="v" playsinline muted autoplay disablepictureinpicture></video>
<script>
"use strict";
(function () {
  var video = document.getElementById("v");
  var pc = null;
  var stream = null;
  var generation = 0;
  var sawFrame = false;
  var codecTimer = null;
  var frameTimer = null;
  var lastTime = -1;

  function post(message) {
    try {
      window.webkit.messageHandlers.khala.postMessage(message);
    } catch (e) {
      // No native side to tell; nothing else to do.
    }
  }

  function describe(error) {
    var name = (error && error.name) ? String(error.name) + ": " : "";
    var text = (error && error.message) ? String(error.message) : String(error);
    return (name + text).slice(0, 200);
  }

  // Fatal: native gives way to the next player.
  function fail(where, error) {
    post({ type: "error", message: where + ": " + describe(error) });
  }

  // Not fatal: native only logs it.
  function note(where, error) {
    post({ type: "note", message: where + ": " + describe(error) });
  }

  window.addEventListener("error", function (event) {
    fail("script", event && event.message ? event.message : "error");
  });
  window.addEventListener("unhandledrejection", function (event) {
    note("promise", event && event.reason ? event.reason : "rejection");
  });

  function cleanUp() {
    generation += 1;
    sawFrame = false;
    lastTime = -1;
    if (codecTimer) { clearTimeout(codecTimer); codecTimer = null; }
    if (frameTimer) { clearInterval(frameTimer); frameTimer = null; }
    if (pc) {
      pc.onnegotiationneeded = null;
      pc.onicecandidate = null;
      pc.oniceconnectionstatechange = null;
      pc.ontrack = null;
      try { pc.close(); } catch (e) {}
      pc = null;
    }
    if (stream) {
      stream.getTracks().forEach(function (track) { try { track.stop(); } catch (e) {} });
      stream = null;
    }
    try { video.pause(); } catch (e) {}
    try { video.srcObject = null; } catch (e) {}
  }

  // The first decoded frame, however WebKit shows it: the media events, the video's clock moving, a video frame
  // callback, or the inbound stats counting decoded frames. Whichever comes first reports it, once.
  function reportFrame(how) {
    if (sawFrame || !pc) { return; }
    sawFrame = true;
    if (frameTimer) { clearInterval(frameTimer); frameTimer = null; }
    post({ type: "frame", width: video.videoWidth || 0, height: video.videoHeight || 0, how: how });
    readCodec(generation, 0);
  }

  function onMediaEvent() {
    if (video.videoWidth) { reportFrame("event"); }
  }

  function watchForFrames(gen) {
    if (frameTimer) { clearInterval(frameTimer); }
    if (typeof video.requestVideoFrameCallback === "function") {
      try {
        video.requestVideoFrameCallback(function () { if (gen === generation) { reportFrame("callback"); } });
      } catch (e) {}
    }
    frameTimer = setInterval(function () {
      if (gen !== generation || sawFrame || !pc) { return; }
      var time = video.currentTime;
      // The clock alone could be the audio track; a video size means a video frame was decoded too.
      if (lastTime >= 0 && time > lastTime && video.videoWidth) { reportFrame("clock"); return; }
      lastTime = time;
      pc.getStats().then(function (stats) {
        if (gen !== generation || sawFrame) { return; }
        stats.forEach(function (report) {
          if (report.type === "inbound-rtp" && (report.kind === "video" || report.mediaType === "video") &&
              report.framesDecoded > 0) {
            reportFrame("stats");
          }
        });
      }).catch(function () {});
    }, 250);
  }

  // The codec the stream actually decodes, from the inbound video RTP stats: "video/H265" and so on. Only for the
  // badge, so nothing here is fatal.
  function readCodec(gen, attempt) {
    if (!pc || gen !== generation) { return; }
    pc.getStats().then(function (stats) {
      if (gen !== generation) { return; }
      var codecs = {};
      var codecId = null;
      stats.forEach(function (report) {
        if (report.type === "codec") { codecs[report.id] = report; }
        if (report.type === "inbound-rtp" && (report.kind === "video" || report.mediaType === "video")) {
          codecId = report.codecId || codecId;
        }
      });
      var codec = codecId ? codecs[codecId] : null;
      if (codec && codec.mimeType) {
        post({ type: "codec", mimeType: String(codec.mimeType) });
      } else if (attempt < 10) {
        codecTimer = setTimeout(function () { readCodec(gen, attempt + 1); }, 500);
      }
    }).catch(function (error) { if (gen === generation) { note("stats", error); } });
  }

  video.addEventListener("loadeddata", onMediaEvent);
  video.addEventListener("playing", onMediaEvent);
  video.addEventListener("resize", onMediaEvent);

  window.khala = {
    start: function (config) {
      cleanUp();
      var gen = generation;
      try {
        pc = new RTCPeerConnection(config.configuration || {});
      } catch (error) {
        fail("peer connection", error);
        return true;
      }
      if (config.dataChannel) {
        // Some cameras (Nest) only start sending once the channel exists, as in the frontend.
        try { pc.createDataChannel(config.dataChannel); } catch (error) { note("data channel", error); }
      }
      stream = new MediaStream();
      // Attached once. Setting srcObject again (one track event per audio and video) restarts the element's load,
      // which rejects the play() still pending with AbortError — that is what made build 30.1 give way at once.
      video.srcObject = stream;
      pc.onnegotiationneeded = function () {
        if (!pc || gen !== generation) { return; }
        var connection = pc;
        connection.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: true })
          .then(function (offer) {
            if (gen !== generation) { return null; }
            return connection.setLocalDescription(offer).then(function () {
              if (gen !== generation) { return; }
              post({ type: "offer", sdp: offer.sdp });
            });
          })
          .catch(function (error) { if (gen === generation) { fail("offer", error); } });
      };
      pc.onicecandidate = function (event) {
        if (gen !== generation || !event.candidate || !event.candidate.candidate) { return; }
        post({ type: "candidate", candidate: event.candidate.toJSON() });
      };
      pc.oniceconnectionstatechange = function () {
        if (!pc || gen !== generation) { return; }
        post({ type: "ice", state: pc.iceConnectionState });
      };
      pc.ontrack = function (event) {
        if (gen !== generation || !stream) { return; }
        stream.addTrack(event.track);
        if (event.track.kind !== "video") { return; }
        watchForFrames(gen);
        // Muted autoplay normally starts it by itself; a refused or interrupted play() is not a failure — the
        // first-frame deadline decides that.
        var playing = video.play();
        if (playing && playing.catch) {
          playing.catch(function (error) { if (gen === generation) { note("play", error); } });
        }
      };
      pc.addTransceiver("audio", { direction: "recvonly" });
      pc.addTransceiver("video", { direction: "recvonly" });
      return true;
    },
    answer: function (sdp) {
      if (!pc || pc.signalingState !== "have-local-offer") { return true; }
      var gen = generation;
      pc.setRemoteDescription({ type: "answer", sdp: sdp })
        .catch(function (error) { if (gen === generation) { fail("answer", error); } });
      return true;
    },
    candidate: function (init) {
      if (!pc) { return true; }
      // A remote candidate that does not apply is not fatal: ICE goes on with the others.
      pc.addIceCandidate(init).catch(function () {});
      return true;
    },
    setMuted: function (muted) {
      video.muted = !!muted;
      if (!muted && pc) {
        var playing = video.play();
        if (playing && playing.catch) { playing.catch(function (error) { note("unmute", error); }); }
      }
      return true;
    },
    stop: function () {
      cleanUp();
      return true;
    }
  };

  post({ type: "ready" });
})();
</script>
</body>
</html>
"""#
}
