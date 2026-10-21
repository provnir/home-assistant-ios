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
///   `ready`, `offer {sdp}`, `candidate {candidate}`, `ice {state}`, `frame {width, height}`,
///   `codec {mimeType}`, `error {message}`;
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

  function post(message) {
    try {
      window.webkit.messageHandlers.khala.postMessage(message);
    } catch (e) {
      // No native side to tell; nothing else to do.
    }
  }

  function fail(where, error) {
    var text = (error && error.message) ? String(error.message) : String(error);
    post({ type: "error", message: where + ": " + text.slice(0, 200) });
  }

  window.addEventListener("error", function (event) {
    fail("script", event && event.message ? event.message : "error");
  });
  window.addEventListener("unhandledrejection", function (event) {
    fail("promise", event && event.reason ? event.reason : "rejection");
  });

  function cleanUp() {
    generation += 1;
    sawFrame = false;
    if (codecTimer) { clearTimeout(codecTimer); codecTimer = null; }
    if (stream) {
      stream.getTracks().forEach(function (track) { track.stop(); });
      stream = null;
    }
    try { video.srcObject = null; } catch (e) {}
    if (pc) {
      pc.onnegotiationneeded = null;
      pc.onicecandidate = null;
      pc.oniceconnectionstatechange = null;
      pc.ontrack = null;
      try { pc.close(); } catch (e) {}
      pc = null;
    }
  }

  function reportFrame() {
    if (sawFrame || !video.videoWidth) { return; }
    sawFrame = true;
    post({ type: "frame", width: video.videoWidth, height: video.videoHeight });
    readCodec(generation, 0);
  }

  // The codec the stream actually decodes, from the inbound video RTP stats: "video/H265" and so on.
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
    }).catch(function (error) { fail("stats", error); });
  }

  video.addEventListener("loadeddata", reportFrame);
  video.addEventListener("playing", reportFrame);
  video.addEventListener("resize", reportFrame);

  window.khala = {
    start: function (config) {
      cleanUp();
      var gen = generation;
      try {
        pc = new RTCPeerConnection(config.configuration || {});
      } catch (error) {
        fail("peer connection", error);
        return;
      }
      if (config.dataChannel) {
        // Some cameras (Nest) only start sending once the channel exists, as in the frontend.
        pc.createDataChannel(config.dataChannel);
      }
      stream = new MediaStream();
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
        video.srcObject = stream;
        var playing = video.play();
        if (playing && playing.catch) { playing.catch(function (error) { fail("play", error); }); }
      };
      pc.addTransceiver("audio", { direction: "recvonly" });
      pc.addTransceiver("video", { direction: "recvonly" });
    },
    answer: function (sdp) {
      if (!pc || pc.signalingState !== "have-local-offer") { return; }
      var gen = generation;
      pc.setRemoteDescription({ type: "answer", sdp: sdp })
        .catch(function (error) { if (gen === generation) { fail("answer", error); } });
    },
    candidate: function (init) {
      if (!pc) { return; }
      // A remote candidate that does not apply is not fatal: ICE goes on with the others.
      pc.addIceCandidate(init).catch(function () {});
    },
    setMuted: function (muted) {
      video.muted = !!muted;
    },
    stop: function () {
      cleanUp();
    }
  };

  post({ type: "ready" });
})();
</script>
</body>
</html>
"""#
}
