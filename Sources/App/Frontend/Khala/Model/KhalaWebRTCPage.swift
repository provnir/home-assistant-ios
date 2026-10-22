import Foundation

/// The page `KhalaWebKitLivePlayer` loads into its WKWebView: the Home Assistant frontend's camera player, ported
/// (Apache-2.0, home-assistant/frontend release 20260930.4, the frontend HA 2026.10.x serves) into one local page
/// with two lanes, as `ha-camera-stream` mounts two players:
///
/// - the WebRTC lane is `src/components/ha-web-rtc-player.ts`: an `RTCPeerConnection` on the server's ICE
///   configuration, the optional data channel, recvonly audio + video transceivers, the offer on
///   `negotiationneeded`, trickled candidates both ways (the empty end-of-candidates included), an audio track held
///   back from the stream while muted (`_addTrack`). Apple's WebRTC negotiates the H.265 the cameras send, which the
///   app's bundled libwebrtc cannot;
/// - the HLS lane is `src/components/ha-hls-player.ts` on WebKit's native HLS (`_renderHLSNative`: `src`, then
///   `play()` on `loadedmetadata`), with the playlist native resolved and parsed (`KhalaHLSPlaylist`);
/// - both videos stack in the same place (`object-fit` as the host asks); the one `KhalaStreamSelection` shows is
///   on top. Where the frontend hides the other with `display: none`, here it stays rendered underneath, so the
///   lane racing behind keeps playing (WebKit pauses muted autoplay it cannot see) and the switch is a z-order
///   change, not a re-attach;
/// - `poster` on both videos, as the frontend sets it, so the still sits in the video element itself until the
///   first frame replaces it.
///
/// Improvements on top: picture in picture (`webkitSetPresentationMode`), a full-resolution frame grab, and raw
/// stats for the info sheet.
///
/// The page never talks to Home Assistant itself: it has no token and no remote script. Signaling goes through
/// native (`KhalaWebRTCSignaling`), which rides the app's existing websocket; the HLS lane plays only the playlist
/// native gives it.
///
/// - page → native, `window.webkit.messageHandlers.khala.postMessage(...)`, one of `KhalaWebRTCPageMessage`:
///   `ready`, `offer {sdp}`, `candidate {candidate}`, `ice {state}`, `frame {width, height, how}`, `audio`,
///   `codec {mimeType}`, `hls {event, ...}`, `presentation {mode}`, `poster`, `error {message}` (fatal) and
///   `note {message}` (logged only);
/// - native → page, `window.khala.start(config)`, `.answer(sdp)`, `.candidate(init)`, `.endOfCandidates()`,
///   `.setMuted(bool)`, `.stop()`, `.hlsStart(url)`, `.hlsStop()`, `.show(lane)`, `.setPoster(dataURL)`,
///   `.togglePictureInPicture()` (see `KhalaWebRTCPageCommand`), and the async `.snapshot()` and `.stats()`.
///
/// Errors are reported by message only — never the SDP, a candidate, an address, the ICE configuration (which can
/// carry TURN credentials) or the playlist location, and nothing is written to the console.
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
  pointer-events: none; z-index: 1; }
video.front { z-index: 2; }
</style>
</head>
<body>
<video id="rtc" class="front" playsinline muted autoplay></video>
<video id="hls" playsinline muted autoplay></video>
<script>
"use strict";
// Ported from the Home Assistant frontend (Apache-2.0), release 20260930.4: src/components/ha-web-rtc-player.ts
// (the WebRTC lane), src/components/ha-hls-player.ts (the HLS lane, its native path) and
// src/components/ha-camera-stream.ts (two lanes, one shown). Signaling and the choice of lane are native's.
(function () {
  var video = document.getElementById("rtc");
  var hlsVideo = document.getElementById("hls");
  var front = video;
  var pc = null;
  var stream = null;
  var heldAudio = [];
  var muted = true;
  var generation = 0;
  var hlsGeneration = 0;
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

  // A refused or interrupted play() is never a failure: the first-frame deadline decides that.
  function resume(element, where) {
    try {
      var playing = element.play();
      if (playing && playing.catch) { playing.catch(function (error) { note(where, error); }); }
    } catch (error) {
      note(where, error);
    }
  }

  window.addEventListener("error", function (event) {
    fail("script", event && event.message ? event.message : "error");
  });
  window.addEventListener("unhandledrejection", function (event) {
    note("promise", event && event.reason ? event.reason : "rejection");
  });

  // ha-web-rtc-player `_cleanUp`: stop the tracks, release the element, close the peer connection.
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
    heldAudio.forEach(function (track) { try { track.stop(); } catch (e) {} });
    heldAudio = [];
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

  // ha-hls-player `_cleanUp`.
  function hlsCleanUp() {
    hlsGeneration += 1;
    hlsVideo.onloadedmetadata = null;
    hlsVideo.onloadeddata = null;
    hlsVideo.onerror = null;
    try { hlsVideo.pause(); } catch (e) {}
    hlsVideo.removeAttribute("src");
    try { hlsVideo.load(); } catch (e) {}
  }

  function presentation(element) {
    if (element.webkitPresentationMode) { return String(element.webkitPresentationMode); }
    return document.pictureInPictureElement === element ? "picture-in-picture" : "inline";
  }

  [video, hlsVideo].forEach(function (element) {
    var report = function () { post({ type: "presentation", mode: presentation(element) }); };
    element.addEventListener("webkitpresentationmodechanged", report);
    element.addEventListener("enterpictureinpicture", report);
    element.addEventListener("leavepictureinpicture", report);
  });

  // WebKit pauses video while the app is in the background; the lane on screen picks up again on return (native
  // decides whether the stream itself is kept, as the frontend's 60 s hidden clean-up does).
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && (pc || hlsVideo.getAttribute("src"))) { resume(front, "resume"); }
  });

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
        // "Some cameras (such as nest) require a data channel to establish a stream".
        try { pc.createDataChannel(config.dataChannel); } catch (error) { note("data channel", error); }
      }
      stream = new MediaStream();
      // Attached once. Setting srcObject again (one track event per audio and video) restarts the element's load,
      // which rejects the play() still pending with AbortError — that is what made build 30.1 give way at once.
      video.srcObject = stream;
      video.muted = muted;
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
        if (event.track.kind === "audio") {
          post({ type: "audio" });
          // ha-web-rtc-player `_addTrack`: "If the track is audio and the player is muted, we do not add it to the
          // stream." Held here instead, so unmuting can add it without a new session.
          if (muted) { heldAudio.push(event.track); return; }
        }
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
    endOfCandidates: function () {
      if (!pc) { return true; }
      // As the frontend passes an empty candidate on: `new RTCIceCandidate({candidate: "", sdpMid: "0"})`.
      pc.addIceCandidate({ candidate: "", sdpMid: "0" }).catch(function () {});
      return true;
    },
    setMuted: function (value) {
      muted = !!value;
      video.muted = muted;
      hlsVideo.muted = muted;
      if (!muted && stream && heldAudio.length) {
        heldAudio.forEach(function (track) { stream.addTrack(track); });
        heldAudio = [];
      }
      if (!muted) { resume(front, "unmute"); }
      return true;
    },
    stop: function () {
      cleanUp();
      return true;
    },
    // ha-hls-player `_renderHLSNative`: the source, then play() once the metadata is in.
    hlsStart: function (url) {
      hlsCleanUp();
      var gen = hlsGeneration;
      hlsVideo.muted = muted;
      hlsVideo.onloadedmetadata = function () { if (gen === hlsGeneration) { resume(hlsVideo, "hls play"); } };
      hlsVideo.onloadeddata = function () {
        if (gen !== hlsGeneration) { return; }
        post({ type: "hls", event: "frame", width: hlsVideo.videoWidth || 0, height: hlsVideo.videoHeight || 0 });
      };
      hlsVideo.onerror = function () {
        if (gen !== hlsGeneration) { return; }
        var error = hlsVideo.error;
        post({ type: "hls", event: "error", message: "media error " + (error ? error.code : 0) });
      };
      hlsVideo.setAttribute("src", url);
      return true;
    },
    hlsStop: function () {
      hlsCleanUp();
      return true;
    },
    // ha-camera-stream: the shown player is the visible one; the other stays mounted underneath.
    show: function (lane) {
      front = lane === "hls" ? hlsVideo : video;
      var back = front === video ? hlsVideo : video;
      front.className = "front";
      back.className = "";
      resume(front, "show");
      return true;
    },
    // The frontend's `poster` (its cached `camera_proxy` still); decoded first so a broken one never blanks it.
    setPoster: function (url) {
      var image = new Image();
      image.onload = function () {
        video.poster = url;
        hlsVideo.poster = url;
        post({ type: "poster" });
      };
      image.onerror = function () { note("poster", "unreadable"); };
      image.setAttribute("src", url);
      return true;
    },
    togglePictureInPicture: function () {
      var element = front;
      try {
        if (element.webkitSupportsPresentationMode && element.webkitSupportsPresentationMode("picture-in-picture")) {
          var mode = element.webkitPresentationMode === "picture-in-picture" ? "inline" : "picture-in-picture";
          element.webkitSetPresentationMode(mode);
        } else if (document.pictureInPictureElement) {
          document.exitPictureInPicture().catch(function (error) { note("pip", error); });
        } else if (element.requestPictureInPicture) {
          element.requestPictureInPicture().catch(function (error) { note("pip", error); });
        } else {
          note("pip", "not supported");
        }
      } catch (error) {
        note("pip", error);
      }
      return true;
    },
    // The frame on screen at the stream's own resolution, as a JPEG data URL; null when there is none or the
    // canvas is tainted (an HLS lane served from another origin), and native falls back to the server's still.
    snapshot: function () {
      var element = front;
      var width = element.videoWidth;
      var height = element.videoHeight;
      if (!width || !height) { return null; }
      try {
        var canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        canvas.getContext("2d").drawImage(element, 0, 0, width, height);
        return canvas.toDataURL("image/jpeg", 0.92);
      } catch (error) {
        note("snapshot", error);
        return null;
      }
    },
    // Raw counters for the info sheet (`KhalaLiveStats`); candidate types only, never an address.
    stats: function () {
      if (front === hlsVideo) {
        var seekable = hlsVideo.seekable;
        var behind = null;
        if (seekable && seekable.length) {
          behind = Math.max(0, seekable.end(seekable.length - 1) - hlsVideo.currentTime);
        }
        var quality = hlsVideo.getVideoPlaybackQuality ? hlsVideo.getVideoPlaybackQuality() : null;
        return Promise.resolve({
          lane: "hls", t: performance.now(), bytes: hlsVideo.webkitVideoDecodedByteCount,
          frames: quality ? quality.totalVideoFrames : hlsVideo.webkitDecodedFrameCount,
          dropped: quality ? quality.droppedVideoFrames : hlsVideo.webkitDroppedFrameCount,
          w: hlsVideo.videoWidth, h: hlsVideo.videoHeight, behind: behind
        });
      }
      if (!pc) { return Promise.resolve(null); }
      return pc.getStats().then(function (stats) {
        var out = { lane: "webrtc", t: 0 };
        var codecs = {};
        var candidates = {};
        var pairs = [];
        var codecId = null;
        var selected = null;
        stats.forEach(function (report) {
          if (report.type === "codec") {
            codecs[report.id] = report;
          } else if (report.type === "inbound-rtp" && (report.kind === "video" || report.mediaType === "video")) {
            out.t = report.timestamp;
            out.bytes = report.bytesReceived;
            out.frames = report.framesDecoded;
            out.fps = report.framesPerSecond;
            out.w = report.frameWidth;
            out.h = report.frameHeight;
            out.dropped = report.framesDropped;
            out.lost = report.packetsLost;
            out.jitter = report.jitter;
            codecId = report.codecId;
          } else if (report.type === "candidate-pair") {
            pairs.push(report);
          } else if (report.type === "local-candidate" || report.type === "remote-candidate") {
            candidates[report.id] = report;
          } else if (report.type === "transport" && report.selectedCandidatePairId) {
            selected = report.selectedCandidatePairId;
          }
        });
        var pair = null;
        pairs.forEach(function (candidate) {
          if (candidate.id === selected || (!selected && candidate.nominated && candidate.state === "succeeded")) {
            pair = candidate;
          }
        });
        if (pair) {
          out.rtt = pair.currentRoundTripTime;
          var local = candidates[pair.localCandidateId];
          var remote = candidates[pair.remoteCandidateId];
          if (local) { out.local = local.candidateType; out.protocol = local.protocol; }
          if (remote) { out.remote = remote.candidateType; }
        }
        if (codecId && codecs[codecId]) { out.codec = codecs[codecId].mimeType; }
        if (!out.t) { out.t = performance.now(); }
        return out;
      });
    }
  };

  post({ type: "ready" });
})();
</script>
</body>
</html>
"""#
}
