// Rules shared by every player in the app -- `<rellm-video>` (public/rellm-video.js), the post cards' inline `<audio>`,
// `Shared.VideoPlayerPanel`'s miniplayer and `Shared.AudioPlayerPanel`'s bar -- so they behave as one:
//
//   * Navigation tracking (`window.rellmMedia.lastNavigation()`): where the app last navigated from, and when. A player
//     that's removed along with its page within a moment of a navigation was playing when the viewer left it, which is
//     what carries it over to its panel.
//   * One at a time: starting something audible pauses whatever else is playing -- an inline video, a post card's audio,
//     either panel -- so you never hear two. Silent autoplay previews neither pause anything nor get paused.
//   * Audio handoff: a post card's `<audio>` that's playing when its page is navigated away from (or whose "play in the
//     audio player" button is pressed) moves to the audio bar, at the same moment, like a video moves to the miniplayer.
//     The `rellm-audio-handoff` window event carries `{ id, host, positionMs, playing }`; `index.html` forwards it to
//     Elm over a port, and `Shared` fetches the track and opens it in `Shared.AudioPlayerPanel`.
//
// Elm navigates with `history.pushState` (the back/forward buttons fire `popstate`); `replaceState` only tweaks the
// current page, so it doesn't count as leaving it.
(function () {
  "use strict";
  if (window.rellmMedia) { return; }

  var NAVIGATION_WINDOW_MS = 1500;

  // ---- navigation tracking ------------------------------------------------------------------------------

  var lastNavigation = { time: 0, from: window.location.href };
  var currentHref = window.location.href;
  var noteNavigation = function () {
    lastNavigation = { time: Date.now(), from: currentHref };
    currentHref = window.location.href;
  };
  var originalPushState = window.history.pushState;
  window.history.pushState = function () {
    var result = originalPushState.apply(this, arguments);
    noteNavigation();
    return result;
  };
  window.addEventListener("popstate", noteNavigation);
  var originalReplaceState = window.history.replaceState;
  window.history.replaceState = function () {
    var result = originalReplaceState.apply(this, arguments);
    currentHref = window.location.href;
    return result;
  };

  var justNavigated = function () { return Date.now() - lastNavigation.time <= NAVIGATION_WINDOW_MS; };

  // ---- one at a time ------------------------------------------------------------------------------------

  var inAudioBar = function (el) { return !!(el.closest && el.closest(".audio-player-panel")); };

  // Media events don't bubble, but they do capture. The audio bar has two `<audio>` slots that hand playback to each other
  // while changing quality, so a slot starting never pauses the other audio (only videos); everything else pauses everything.
  document.addEventListener("play", function (event) {
    var started = event.target;
    if (!started || (started.tagName !== "AUDIO" && started.tagName !== "VIDEO") || started.muted) { return; }
    Array.prototype.forEach.call(document.querySelectorAll("audio, video"), function (other) {
      if (other === started || other.paused || other.muted) { return; }
      if (inAudioBar(started) && other.tagName === "AUDIO") { return; }
      other.pause();
    });
  }, true);

  // ---- audio handoff ------------------------------------------------------------------------------------

  // The `<audio>` elements a post card renders (`Components.MediaRenderer`) carry `data-media-id` and `data-host` -- the
  // track and the server it lives on -- unless they aren't ours to hand over (a federated attachment, or the media viewer's).
  var handoffTarget = function (audio) {
    return audio && audio.tagName === "AUDIO" && audio.hasAttribute("data-media-id") && audio.hasAttribute("data-host") &&
      !(audio.closest && audio.closest(".media-viewer-panel"));
  };

  var handoffAudio = function (audio, playing) {
    if (!handoffTarget(audio)) { return false; }
    window.dispatchEvent(new CustomEvent("rellm-audio-handoff", {
      detail: {
        id: audio.getAttribute("data-media-id"),
        host: audio.getAttribute("data-host"),
        positionMs: Math.round((audio.currentTime || 0) * 1000),
        playing: playing
      }
    }));
    return true;
  };

  // Which post-card audio is playing, so a removal can tell it was (the browser pauses a removed element, after observers run
  // but possibly before we look), and the card can show its "play in the audio player" button only then.
  var playingAudio = new WeakSet();
  var track = function (event, playing) {
    var audio = event.target;
    if (!handoffTarget(audio)) { return; }
    if (playing) { playingAudio.add(audio); } else { playingAudio.delete(audio); }
    var card = audio.closest(".media-renderer-audio-preview");
    if (card) { card.classList.toggle("is-playing", playing); }
  };
  document.addEventListener("play", function (event) { track(event, true); }, true);
  ["pause", "ended"].forEach(function (name) {
    document.addEventListener(name, function (event) { track(event, false); }, true);
  });

  // A playing post-card `<audio>` removed along with its page, just after a navigation, carries on in the audio bar.
  var removedAudio = function (node) {
    if (node.nodeType !== 1) { return; }
    var audios = node.tagName === "AUDIO" ? [node] : Array.prototype.slice.call(node.getElementsByTagName("audio"));
    audios.forEach(function (audio) {
      if (playingAudio.has(audio) && justNavigated()) {
        playingAudio.delete(audio);
        handoffAudio(audio, true);
      }
    });
  };
  new MutationObserver(function (records) {
    records.forEach(function (record) { Array.prototype.forEach.call(record.removedNodes, removedAudio); });
  }).observe(document.documentElement, { childList: true, subtree: true });

  // The card's "play in the audio player" button (`.media-renderer-audio-handoff`): hand the audio over and stop this copy.
  document.addEventListener("click", function (event) {
    var button = event.target.closest && event.target.closest("[data-rellm-handoff]");
    if (!button) { return; }
    var audio = button.parentNode && button.parentNode.querySelector("audio");
    if (audio && handoffAudio(audio, !audio.paused)) {
      audio.pause();
    }
  });

  window.rellmMedia = {
    lastNavigation: function () { return lastNavigation; },
    justNavigated: justNavigated
  };
})();
