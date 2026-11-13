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
//     The `rellm-audio-handoff` window event carries `{ id, host, positionMs, playing, postUrl }`; `index.html` forwards it to
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

  // `started` is audible and playing: pause everything else that is. The audio bar has two `<audio>` slots that hand playback to
  // each other while changing quality, so a bar slot never pauses the *bar's* other slot (it does pause anything else).
  // (The audio bar's slots briefly play a silent clip on the first tap -- `index.html`'s `unlockAudioSlots`, which iOS needs
  // before it lets code start them -- and that is not something to pause a video for.)
  var isUnlockClip = function (el) { return /^data:audio\/wav/.test(el.getAttribute("src") || ""); };
  var isAudible = function (el) {
    return !!el && (el.tagName === "AUDIO" || el.tagName === "VIDEO") && !el.paused && !el.muted && el.volume > 0 && !isUnlockClip(el);
  };

  var pauseOthers = function (started) {
    Array.prototype.forEach.call(document.querySelectorAll("audio, video"), function (other) {
      if (other === started || !isAudible(other)) { return; }
      if (inAudioBar(started) && inAudioBar(other)) { return; }
      other.pause();
    });
  };

  // Media events don't bubble, but they do capture. Starting something audible pauses the rest -- and so does a playing video
  // becoming audible (unmuted, or its volume raised from zero) without another `play`.
  document.addEventListener("play", function (event) { if (isAudible(event.target)) { pauseOthers(event.target); } }, true);
  document.addEventListener("volumechange", function (event) { if (isAudible(event.target)) { pauseOthers(event.target); } }, true);

  // ---- audio handoff ------------------------------------------------------------------------------------

  // The `<audio>` elements a post card renders (`Components.MediaRenderer`) carry `data-media-id` and `data-host` -- the
  // track and the server it lives on -- unless they aren't ours to hand over (a federated attachment, or the media viewer's).
  var handoffTarget = function (audio) {
    return audio && audio.tagName === "AUDIO" && audio.hasAttribute("data-media-id") && audio.hasAttribute("data-host") &&
      !(audio.closest && audio.closest(".media-viewer-panel"));
  };

  // The post (or event) page a video or audio belongs to, as a link within the app: the card it is on (its `.post-card-link-overlay`
  // href), else -- on a post's own page -- that page. `from` is the page the request is made from.
  function postLinkFor(el, from) {
    var card = el.closest ? el.closest(".post-card") : null;
    var overlay = card ? card.querySelector(".post-card-link-overlay") : null;
    var href = overlay ? overlay.getAttribute("href") : null;
    if (href) { return href; }
    try {
      var url = new URL(from, window.location.href);
      if (/\/(post|event)\/|\/~/.test(url.pathname)) { return url.pathname + url.search + url.hash; }
    } catch (e) { /* not a URL */ }
    return null;
  }

  var handoffAudio = function (audio, playing) {
    if (!handoffTarget(audio)) { return false; }
    window.dispatchEvent(new CustomEvent("rellm-audio-handoff", {
      detail: {
        id: audio.getAttribute("data-media-id"),
        host: audio.getAttribute("data-host"),
        positionMs: Math.round((audio.currentTime || 0) * 1000),
        playing: playing,
        postUrl: postLinkFor(audio, window.location.href)
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

  // ---- opening a video in the media viewer -----------------------------------------------------------------
  //
  // A thumbnail's enlarge button opens the viewer, whose video is `Shared.VideoPlayerPanel`'s player -- a different
  // element. The thumbnail leaves where it was (and whether it was playing) here, keyed by the media's id, for the panel's
  // player to take up the moment it's built. It's good for a few seconds only: a stale one must not hijack a later open.
  var ENLARGE_WINDOW_MS = 5000;
  var enlargement = null;
  var setEnlarge = function (details) {
    enlargement = { mediaId: details.mediaId, time: details.time, playing: details.playing, at: Date.now() };
    // A player already showing this video (the panel's, still on it from an earlier open) takes it up straight away; a new one
    // takes it when it's built.
    window.dispatchEvent(new CustomEvent("rellm-enlarge", { detail: { mediaId: details.mediaId } }));
  };
  // `peek` leaves it for whoever builds the player next: the viewer opening can replace a player that already applied it
  // (Elm keys the panel's player by where it started), and the replacement has to start from the same moment.
  var peekEnlarge = function (mediaId) {
    var found = enlargement;
    if (!found || !mediaId || found.mediaId !== mediaId || Date.now() - found.at > ENLARGE_WINDOW_MS) { return null; }
    return { time: found.time, playing: found.playing, at: found.at };
  };
  // Drops the handoff made at `at` (a newer one is left alone) -- for a player that peeked and kept going, once the update that
  // might replace it has had its chance, so the handoff can't leak into a later, unrelated open of the same video.
  var clearEnlarge = function (at) {
    if (enlargement && enlargement.at === at) { enlargement = null; }
  };
  var takeEnlarge = function (mediaId) {
    var found = peekEnlarge(mediaId);
    if (found) { enlargement = null; }
    return found;
  };

  // ---- keeping one <video> across players ---------------------------------------------------------------
  //
  // Moving a video between players (a post's inline player -> the miniplayer or the viewer) by building a new `<video>` in the
  // new place reloads the stream and leaves a gap. So the player giving a video up parks the live element here (`stashVideo`,
  // keyed like `enlargement`: by the media's key), still playing, and the new player takes it over the moment it is built
  // (`takeVideo`), swapping it in for the `<video>` Elm just made. A stash nobody takes within a few seconds is let go.
  //
  // Elm still holds the elements it made, so both the parked one and the one it was swapped for are noted (`noteMoved`) and
  // `removeChild`/`insertBefore`/`replaceChild` tolerate them no longer being where Elm left them, rather than throwing.
  var HANDOFF_WINDOW_MS = 4000;
  var holder = null;
  var stash = null;
  var moved = new WeakSet();

  var noteMoved = function (element) { moved.add(element); };
  var nativeRemoveChild = Node.prototype.removeChild;
  Node.prototype.removeChild = function (child) {
    if (child && moved.has(child) && child.parentNode !== this) { return child; }
    return nativeRemoveChild.call(this, child);
  };
  var nativeInsertBefore = Node.prototype.insertBefore;
  Node.prototype.insertBefore = function (node, reference) {
    if (reference && moved.has(reference) && reference.parentNode !== this) { reference = null; }
    return nativeInsertBefore.call(this, node, reference);
  };
  var nativeReplaceChild = Node.prototype.replaceChild;
  Node.prototype.replaceChild = function (node, old) {
    if (old && moved.has(old) && old.parentNode !== this) { return old; }
    return nativeReplaceChild.call(this, node, old);
  };

  var dropStash = function () {
    if (!stash) { return; }
    clearTimeout(stash.timer);
    var video = stash.video;
    stash = null;
    try { video.pause(); } catch (e) { /* nothing to pause */ }
    if (video.parentNode) { video.parentNode.removeChild(video); }
  };

  // Parked outside <body> (Elm owns that), kept rendered so the browser doesn't treat the video as gone.
  var parkingSpot = function () {
    if (!holder || !holder.isConnected) {
      holder = document.createElement("div");
      holder.setAttribute("aria-hidden", "true");
      holder.style.cssText = "position:fixed;left:0;top:0;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none";
      document.documentElement.appendChild(holder);
    }
    return holder;
  };

  var stashVideo = function (key, video) {
    dropStash();
    noteMoved(video);
    // (Moved synchronously: the browser pauses a video that is out of the document only if it is still out after the task.)
    parkingSpot().appendChild(video);
    stash = { key: key, video: video, timer: setTimeout(dropStash, HANDOFF_WINDOW_MS) };
  };

  var takeVideo = function (key) {
    if (!stash || !key || stash.key !== key) { return null; }
    clearTimeout(stash.timer);
    var video = stash.video;
    stash = null;
    return video;
  };

  window.rellmMedia = {
    stashVideo: stashVideo,
    takeVideo: takeVideo,
    noteMoved: noteMoved,
    lastNavigation: function () { return lastNavigation; },
    postLinkFor: postLinkFor,
    justNavigated: justNavigated,
    setEnlarge: setEnlarge,
    peekEnlarge: peekEnlarge,
    clearEnlarge: clearEnlarge,
    takeEnlarge: takeEnlarge
  };
})();
