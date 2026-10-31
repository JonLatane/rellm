// `<rellm-video>`: the video player chrome `Components.MediaRenderer` wraps every video in (Rellm,
// Bluesky and Mastodon alike), instead of the browser's own `controls`. Elm renders
//
//     <rellm-video class="media-renderer-video-frame" data-media-size="small|extra-small|natural">
//       <video ...></video>
//     </rellm-video>
//
// and this draws the controls in a shadow root, so Elm's virtual DOM never sees them and the page's CSS
// can't break them. (Elm only ever sets the host's `class`/`data-media-size`; the state classes this adds
// -- `compact`, `tiny`, `idle`, `enlarged`, ... -- are safe from its diffing, which only touches
// attributes whose *vnode* value changed.)
//
// What it has:
//   * play/pause, a seek bar that shows what's buffered and the time under the pointer, elapsed/total time
//   * a volume button that opens a slider (just below it in the top-right corner, above it in the bar)
//   * playback speed, loop, and -- for HLS (hls.js, see `public/index.html`) -- quality, in a menu opened
//     from the speed button at the bottom-right
//   * fullscreen, picture-in-picture, and enlarge/restore: a thumbnail (`data-media-size` small or
//     extra-small) can grow to the "natural" size `Components.MediaRenderer.Natural` gives a video, and
//     a restore button at the top-left puts it back
//   * keyboard shortcuts while it has focus (space/k, arrows, j/l, m, f, i, p, 0-9, </>, ...), double-click or
//     double-tap to seek +/-10s (sides) or go fullscreen (middle), a buffering spinner, a big play/replay
//     button, an error message, and controls that fade out while playing
//   * volume, mute and speed are remembered (localStorage, where it's available)
//   * a miniplayer button (and the `i` key): the video carries on in `Shared.VideoPlayerPanel`'s floating
//     player while you browse, and so does one that's playing when you navigate away from its page. The
//     player raises a `rellm-miniplayer` window event (`index.html` hands it to Elm over a port) with where
//     the video was; the panel's own `<rellm-video>` gets `data-miniplayer-panel`, `data-start-at` and
//     `data-resume` to pick it up
//   * only one thing plays at a time (see `rellm-media.js`, which also owns the navigation tracking used here)
//
// Narrow or short frames (thumbnails) get a trimmed layout: `compact` keeps play and seek along the
// bottom with fullscreen/enlarge top-left, volume top-right; `tiny` (< 120px wide) also drops the seek bar.
(function () {
  "use strict";
  if (!window.customElements || customElements.get("rellm-video")) { return; }

  var svg = function (path) { return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + path + '"/></svg>'; };
  var ICONS = {
    play: svg("M8 5v14l11-7z"),
    pause: svg("M6 5h4v14H6zM14 5h4v14h-4z"),
    replay: svg("M12 5V1L7 6l5 5V7a6 6 0 1 1-6 6H4a8 8 0 1 0 8-8z"),
    volume: svg("M3 9v6h4l5 5V4L7 9zM16.5 12A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"),
    volumeLow: svg("M3 9v6h4l5 5V4L7 9zM16.5 12A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4z"),
    muted: svg("M3 9v6h4l5 5V4L7 9zM16 9.4 17.4 8 19.5 10.1 21.6 8 23 9.4 20.9 11.5 23 13.6 21.6 15 19.5 12.9 17.4 15 16 13.6 18.1 11.5z"),
    fullscreen: svg("M5 5h5v2H7v3H5zM14 5h5v5h-2V7h-3zM5 14h2v3h3v2H5zM17 14h2v5h-5v-2h3z"),
    exitFullscreen: svg("M8 5h2v5H5V8h3zM14 5h2v3h3v2h-5zM5 14h5v5H8v-3H5zM14 14h5v2h-3v3h-2z"),
    enlarge: svg("M14 4h6v6h-2V7.4l-4.3 4.3-1.4-1.4L16.6 6H14zM10 20H4v-6h2v2.6l4.3-4.3 1.4 1.4L7.4 18H10z"),
    restore: svg("M20 5.4 15.4 10H18v2h-6V6h2v2.6L18.6 4zM4 18.6 8.6 14H6v-2h6v6h-2v-2.6L5.4 20z"),
    pip: svg("M19 7H5v10h5v2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4h-2zM12 13h9v6h-9z"),
    mini: svg("M19 11h-8v6h8zm4 8V4.98C23 3.88 22.1 3 21 3H3c-1.1 0-2 .88-2 1.98V19c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2zm-2 .02H3V4.97h18z"),
    gear: svg("M19.4 13a7.5 7.5 0 0 0 0-2l2.1-1.6-2-3.5-2.5 1a7.4 7.4 0 0 0-1.7-1L15 3.3h-4l-.4 2.6a7.4 7.4 0 0 0-1.7 1l-2.5-1-2 3.5L6.6 11a7.5 7.5 0 0 0 0 2l-2.1 1.6 2 3.5 2.5-1a7.4 7.4 0 0 0 1.7 1l.4 2.6h4l.4-2.6a7.4 7.4 0 0 0 1.7-1l2.5 1 2-3.5zM13 15.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7z")
  };

  var SPEEDS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
  var IDLE_MS = 2500;
  var VOLUME_PANEL_MS = 3000;
  var SKIP_SECONDS = 5;
  var BIG_SKIP_SECONDS = 10;
  var PREFS_KEY = "rellm-video-prefs";

  var STYLE = [
    ":host{display:inline-block;position:relative;vertical-align:top;max-width:100%;line-height:0;background:#000;outline:none;" +
      "-webkit-tap-highlight-color:transparent;--rv-vol-h:84px}",
    ":host(:fullscreen){display:block;width:100%;height:100%}",
    ":host(.idle){cursor:none}",
    ":host(:focus-visible){box-shadow:0 0 0 2px #fff inset}",
    "slot{display:contents}",
    "[hidden]{display:none!important}",
    // Chrome common to everything drawn over the picture.
    "button{flex:none;display:flex;align-items:center;justify-content:center;width:28px;height:28px;padding:0;margin:0;border:0;" +
      "border-radius:50%;background:transparent;color:#fff;font:inherit;cursor:pointer;-webkit-tap-highlight-color:transparent}",
    "button:hover{background:rgba(255,255,255,.2)}",
    "button:focus-visible,input:focus-visible{outline:2px solid #fff;outline-offset:1px}",
    "svg{width:20px;height:20px;fill:currentColor;pointer-events:none}",
    ".fade{transition:opacity .2s}",
    ":host(.idle) .fade{opacity:0;pointer-events:none}",
    // The bottom bar.
    ".bar{position:absolute;left:0;right:0;bottom:0;display:flex;align-items:center;gap:.5rem;padding:1.4rem .6rem .4rem;box-sizing:border-box;" +
      "color:#fff;font:12px/1 system-ui,-apple-system,sans-serif;font-variant-numeric:tabular-nums;" +
      "background:linear-gradient(to top,rgba(0,0,0,.75),rgba(0,0,0,0));user-select:none;-webkit-user-select:none}",
    ".time{flex:none;min-width:2.6em;text-align:center;line-height:1}",
    ".speed{width:auto;min-width:34px;padding:0 6px;border-radius:14px;font:600 12px/1 system-ui,-apple-system,sans-serif;font-variant-numeric:tabular-nums}",
    // Seek bar: the played part is solid, the buffered part lighter. `--progress`/`--buffered` are percentages.
    ".seekwrap{position:relative;flex:1 1 auto;min-width:40px;display:flex;align-items:center}",
    "input[type=range]{margin:0;background:transparent;cursor:pointer;-webkit-appearance:none;appearance:none}",
    ".seek{flex:1 1 auto;width:100%;min-width:0;height:20px}",
    "input[type=range]::-webkit-slider-runnable-track{height:4px;border-radius:2px;background:linear-gradient(to right," +
      "#fff var(--progress,0%),rgba(255,255,255,.55) var(--progress,0%),rgba(255,255,255,.55) var(--buffered,0%),rgba(255,255,255,.28) var(--buffered,0%))}",
    "input[type=range]::-moz-range-track{height:4px;border-radius:2px;background:linear-gradient(to right," +
      "#fff var(--progress,0%),rgba(255,255,255,.55) var(--progress,0%),rgba(255,255,255,.55) var(--buffered,0%),rgba(255,255,255,.28) var(--buffered,0%))}",
    "input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:12px;height:12px;margin-top:-4px;border:0;border-radius:50%;background:#fff}",
    "input[type=range]::-moz-range-thumb{width:12px;height:12px;border:0;border-radius:50%;background:#fff}",
    ".tip{position:absolute;bottom:22px;transform:translateX(-50%);padding:3px 6px;border-radius:4px;background:rgba(0,0,0,.8);color:#fff;" +
      "font:12px/1 system-ui,-apple-system,sans-serif;font-variant-numeric:tabular-nums;pointer-events:none;white-space:nowrap}",
    // Volume: a button that opens a vertical slider (rotated horizontal range).
    ".vol{position:relative;flex:none;display:flex}",
    ".vol-panel{position:absolute;left:50%;width:30px;height:calc(var(--rv-vol-h) + 12px);margin-left:-15px;border-radius:15px;" +
      "background:rgba(0,0,0,.75);opacity:0;pointer-events:none;transition:opacity .15s}",
    ".vol.open .vol-panel{opacity:1;pointer-events:auto}",
    ".vol-panel input{position:absolute;left:50%;top:50%;width:var(--rv-vol-h);height:20px;transform:translate(-50%,-50%) rotate(-90deg)}",
    ".bar .vol-panel{bottom:calc(100% + 4px)}",
    ".corner-vol .vol-panel{top:calc(100% + 4px)}",
    // Corner buttons (compact/tiny frames, and restore when enlarged).
    ".tl,.tr{position:absolute;top:.35rem;display:flex;gap:4px;align-items:flex-start}",
    ".tl{left:.35rem}",
    ".tr{right:.35rem;display:none}",
    ".corner{background:rgba(0,0,0,.5);width:26px;height:26px}",
    ".corner svg{width:18px;height:18px}",
    ".tl .fs-corner{display:none}",
    ".enlarge{display:var(--rellm-video-enlarge-display,flex)}",
    // Centered overlays.
    ".big{position:absolute;left:50%;top:50%;width:56px;height:56px;margin:-28px 0 0 -28px;background:rgba(0,0,0,.6)}",
    ".big svg{width:32px;height:32px}",
    ".spinner{position:absolute;left:50%;top:50%;width:36px;height:36px;margin:-18px 0 0 -18px;border:3px solid rgba(255,255,255,.3);" +
      "border-top-color:#fff;border-radius:50%;animation:spin .9s linear infinite;pointer-events:none}",
    "@keyframes spin{to{transform:rotate(360deg)}}",
    ".toast{position:absolute;left:50%;top:18%;transform:translateX(-50%);padding:6px 12px;border-radius:6px;background:rgba(0,0,0,.7);color:#fff;" +
      "font:600 14px/1 system-ui,-apple-system,sans-serif;pointer-events:none;opacity:0;transition:opacity .2s;white-space:nowrap}",
    ".toast.show{opacity:1}",
    ".message{position:absolute;left:0;right:0;top:50%;transform:translateY(-50%);padding:0 1rem;text-align:center;color:#fff;" +
      "font:14px/1.3 system-ui,-apple-system,sans-serif;pointer-events:none}",
    // The settings menu (speed, loop, quality).
    ".menu{position:absolute;right:.5rem;bottom:calc(100% + 4px);min-width:150px;max-height:calc(var(--rv-frame-h,240px) - 70px);overflow-y:auto;" +
      "padding:6px 0;border-radius:8px;background:rgba(20,20,22,.95);color:#fff;font:13px/1 system-ui,-apple-system,sans-serif;text-align:left}",
    ".menu h4{margin:0;padding:8px 14px 4px;font:600 11px/1 system-ui,-apple-system,sans-serif;text-transform:uppercase;letter-spacing:.06em;opacity:.65}",
    ".menu button{display:flex;width:100%;height:auto;padding:8px 14px;border-radius:0;justify-content:flex-start;gap:8px;text-align:left}",
    ".menu button[aria-checked=true]::before{content:'\\2713';width:1em}",
    ".menu button[aria-checked=false]::before{content:'';width:1em}",
    // Zero-height anchor on the bar's top edge, so the menu opens upward from there.
    ".menubox{position:absolute;top:0;right:0;left:0;height:0}",
    // Responsive trims, set by `_layout`.
    ":host(.compact) .time,:host(.compact) .bar .vol,:host(.compact) .bar .fs,:host(.compact) .pip,:host(.compact) .mini{display:none}",
    ":host(.compact) .bar{gap:.25rem;padding:.9rem .35rem .25rem}",
    ":host(.compact) .tl .fs-corner,:host(.compact) .tr{display:flex}",
    ":host(.compact) .big{width:44px;height:44px;margin:-22px 0 0 -22px}",
    ":host(.compact) .big svg{width:26px;height:26px}",
    ":host(.tiny) .seekwrap,:host(.tiny) .speed,:host(.tiny) .big{display:none}",
    ":host(.tiny) .bar{padding:.9rem .1rem .1rem}",
    ":host(.tiny) .bar .vol{display:flex}",
    ":host(.tiny) .corner-vol{display:none}",
    ":host(.tiny) .corner{width:20px;height:20px}",
    ":host(.tiny) .corner svg{width:14px;height:14px}",
    ":host(.tiny) .tl,:host(.tiny) .tr{top:3px;gap:2px}",
    ":host(.tiny) .tl{left:3px}",
    ":host(.tiny) .tr{right:3px}",
    ":host(.no-duration) .seekwrap,:host(.no-duration) .time{display:none}",
    ":host(.no-duration) .bar{justify-content:flex-start}",
    ":host(.no-fullscreen) .fs{display:none!important}",
    ":host(.no-pip) .pip{display:none!important}",
    // The miniplayer panel's own player can't be sent to a miniplayer (or enlarged).
    ":host(.in-panel) .mini,:host(.in-panel) .enlarge{display:none!important}",
    // Enlarge: only thumbnails (`.enlargeable`) not already enlarged; restore only when enlarged.
    ":host(:not(.enlargeable)) .enlarge,:host(.enlarged) .enlarge{display:none!important}",
    ".restore{display:none}",
    ":host(.enlarged) .restore{display:flex}",
    ".big.hidden{display:none}"
  ].join("\n");

  var TEMPLATE =
    "<style>" + STYLE + "</style>" +
    "<slot></slot>" +
    '<div class="spinner" hidden></div>' +
    '<div class="message" role="alert" hidden></div>' +
    '<div class="toast" role="status" aria-live="polite"></div>' +
    '<button type="button" class="big fade" aria-label="Play"></button>' +
    '<div class="tl fade">' +
    '<button type="button" class="corner restore" aria-label="Back to thumbnail size"></button>' +
    '<button type="button" class="corner fs fs-corner" aria-label="Fullscreen"></button>' +
    '<button type="button" class="corner enlarge" aria-label="Enlarge"></button>' +
    "</div>" +
    '<div class="tr fade"><div class="vol corner-vol">' +
    '<button type="button" class="corner mute" aria-label="Mute" aria-haspopup="true"></button>' +
    '<div class="vol-panel"><input class="vol-slider" type="range" min="0" max="100" step="1" value="100" aria-label="Volume"></div>' +
    "</div></div>" +
    '<div class="bar fade">' +
    '<button type="button" class="play" aria-label="Play"></button>' +
    '<span class="time cur">0:00</span>' +
    '<div class="seekwrap"><input class="seek" type="range" min="0" max="1000" step="1" value="0" aria-label="Seek"><span class="tip" hidden></span></div>' +
    '<span class="time dur">0:00</span>' +
    '<div class="vol bar-vol">' +
    '<button type="button" class="mute" aria-label="Mute" aria-haspopup="true"></button>' +
    '<div class="vol-panel"><input class="vol-slider" type="range" min="0" max="100" step="1" value="100" aria-label="Volume"></div>' +
    "</div>" +
    '<span class="menubox"><span class="menu" role="menu" hidden></span></span>' +
    '<button type="button" class="speed" aria-label="Playback speed and settings" aria-haspopup="menu" aria-expanded="false">1\u00d7</button>' +
    '<button type="button" class="mini" aria-label="Miniplayer (i)"></button>' +
    '<button type="button" class="pip" aria-label="Picture in picture"></button>' +
    '<button type="button" class="fs" aria-label="Fullscreen"></button>' +
    "</div>";

  function formatTime(seconds) {
    if (!isFinite(seconds) || seconds < 0) { seconds = 0; }
    var s = Math.floor(seconds % 60);
    var m = Math.floor(seconds / 60) % 60;
    var h = Math.floor(seconds / 3600);
    var pad = s < 10 ? "0" + s : "" + s;
    return h > 0 ? h + ":" + (m < 10 ? "0" + m : m) + ":" + pad : m + ":" + pad;
  }

  function formatRate(rate) { return rate + "\u00d7"; }

  function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)); }

  // Volume/mute/speed outlive the page. Storage can be unavailable or throw (private windows, blocked
  // site data), so every access is wrapped and the player works the same without it.
  var prefs = (function () {
    var cache = null;
    function load() {
      if (cache) { return cache; }
      try { cache = JSON.parse(window.localStorage.getItem(PREFS_KEY)) || {}; } catch (e) { cache = {}; }
      if (typeof cache !== "object") { cache = {}; }
      return cache;
    }
    return {
      get: function () { return load(); },
      set: function (patch) {
        var current = load();
        for (var key in patch) { if (Object.prototype.hasOwnProperty.call(patch, key)) { current[key] = patch[key]; } }
        try { window.localStorage.setItem(PREFS_KEY, JSON.stringify(current)); } catch (e) { /* not persisted */ }
      }
    };
  })();

  // The player that last started playing owns the OS media controls (lock screen, headset buttons, the browser's
  // media hub) -- and the `enterpictureinpicture` action, which is how a browser asks a page to go to PiP by itself
  // (e.g. when its tab is hidden, where supported). The app's audio panel may set its own handlers; whoever plays last wins.
  var sessionOwner = null;

  // What the queue calls a video handed over from a page: the page's title, without the app's own " | host" suffix.
  function pageTitle() {
    var title = (document.title || "").trim();
    var suffix = " | " + window.location.hostname;
    if (title.length > suffix.length && title.slice(-suffix.length) === suffix) { title = title.slice(0, -suffix.length); }
    return title || null;
  }

  // Navigation tracking and "one thing plays at a time" are `public/rellm-media.js`'s (shared with the audio players).
  var media = window.rellmMedia || { lastNavigation: function () { return { time: 0, from: window.location.href }; } };

  var VIDEO_EVENTS = [
    "play", "pause", "ended", "timeupdate", "durationchange", "loadedmetadata", "volumechange", "ratechange",
    "seeking", "seeked", "emptied", "progress", "waiting", "stalled", "playing", "canplay", "error", "rellm-hls-error"
  ];

  class RellmVideo extends HTMLElement {
    connectedCallback() {
      if (!this._built) { this._build(); }
      this._bind();
    }

    disconnectedCallback() {
      this._miniplayerIfNavigatedAway();
      this._unbind();
      clearTimeout(this._idleTimer);
      clearTimeout(this._volTimer);
      clearTimeout(this._toastTimer);
      this._idleTimer = this._volTimer = null;
      if (this._resizeObserver) { this._resizeObserver.disconnect(); }
      document.removeEventListener("fullscreenchange", this._onDocumentChange);
      document.removeEventListener("webkitfullscreenchange", this._onDocumentChange);
      document.removeEventListener("pointerdown", this._onOutsidePointer, true);
      this._releaseMediaSession();
      // `connectedCallback` runs again if Elm re-inserts this exact node.
      this._docBound = false;
    }

    // ---- construction -------------------------------------------------------------------------------

    _build() {
      this._built = true;
      var self = this;
      var root = this.attachShadow({ mode: "open" });
      root.innerHTML = TEMPLATE;
      this._root = root;
      var q = function (selector) { return root.querySelector(selector); };
      var all = function (selector) { return Array.prototype.slice.call(root.querySelectorAll(selector)); };
      this._els = {
        bar: q(".bar"), play: q(".play"), big: q(".big"), cur: q(".cur"), dur: q(".dur"), seek: q(".seek"), tip: q(".tip"),
        seekwrap: q(".seekwrap"), speed: q(".speed"), menu: q(".menu"), pip: q(".pip"), mini: q(".mini"), toast: q(".toast"),
        message: q(".message"), spinner: q(".spinner"), restore: q(".restore"), enlarge: q(".enlarge"),
        mute: all(".mute"), fs: all(".fs"), vols: all(".vol"), volSliders: all(".vol-slider")
      };
      if (!this.hasAttribute("tabindex")) { this.tabIndex = 0; }
      if (!this.hasAttribute("role")) { this.setAttribute("role", "group"); }
      if (!this.hasAttribute("aria-label")) { this.setAttribute("aria-label", "Video player"); }

      this._dragging = false;
      this._idleTimer = null;
      this._volTimer = null;
      this._toastTimer = null;
      this._menuOpen = false;
      this._revealTap = false;
      this._lastClick = null;
      this._userPlay = false;
      this._onVideoEvent = function (event) { self._onVideo(event); };
      this._onDocumentChange = function () { self._sync(); };
      this._onOutsidePointer = function (event) { self._closePopupsFor(event); };

      var e = this._els;
      root.querySelector("slot").addEventListener("slotchange", function () { self._bind(); });

      e.play.addEventListener("click", function () { self._togglePlay(); });
      e.big.addEventListener("click", function () { self._togglePlay(); });
      e.mute.forEach(function (button) {
        button.addEventListener("click", function () { self._toggleMute(); self._openVolume(button.closest(".vol")); });
      });
      e.fs.forEach(function (button) { button.addEventListener("click", function () { self._toggleFullscreen(); }); });
      e.pip.addEventListener("click", function () { self._togglePip(); });
      e.mini.addEventListener("click", function () { self._miniplayer(); });
      e.enlarge.addEventListener("click", function () { self._setEnlarged(true); });
      e.restore.addEventListener("click", function () { self._setEnlarged(false); });
      e.speed.addEventListener("click", function () { self._toggleMenu(); });

      e.vols.forEach(function (vol) {
        // Hovering (mouse) or focusing the button opens the slider, like clicking it; it closes a moment after.
        vol.addEventListener("pointerenter", function (event) { if (event.pointerType === "mouse") { self._openVolume(vol); } });
        vol.addEventListener("pointerleave", function (event) { if (event.pointerType === "mouse") { self._scheduleVolumeClose(400); } });
        vol.addEventListener("focusin", function () { self._openVolume(vol); });
        vol.addEventListener("keydown", function (event) { if (event.key === "Escape") { self._closeVolume(); event.stopPropagation(); } });
      });
      e.volSliders.forEach(function (slider) {
        slider.addEventListener("input", function () {
          self._setVolume(slider.value / 100, true);
          self._scheduleVolumeClose(VOLUME_PANEL_MS);
        });
      });

      e.seek.addEventListener("input", function () {
        var v = self._video;
        if (v && isFinite(v.duration)) { v.currentTime = (e.seek.value / 1000) * v.duration; }
        self._sync();
      });
      e.seek.addEventListener("pointerdown", function () { self._dragging = true; });
      ["pointerup", "pointercancel", "blur"].forEach(function (name) {
        e.seek.addEventListener(name, function () { self._dragging = false; });
      });
      e.seek.addEventListener("pointermove", function (event) { self._showTip(event); });
      e.seek.addEventListener("pointerleave", function () { e.tip.hidden = true; });

      // Picture clicks: play/pause, except the tap that merely brings back hidden controls (noted when it
      // starts, since `pointerdown` itself wakes them before `click` fires). Two quick clicks are a
      // double-click: the sides seek, the middle goes fullscreen (the clicks' own two toggles cancel out).
      this.addEventListener("pointerdown", function () {
        self._revealTap = self.classList.contains("idle");
        self._wake();
      });
      this.addEventListener("click", function (event) { self._onPictureClick(event); });
      ["pointermove", "focusin"].forEach(function (name) {
        self.addEventListener(name, function () { self._wake(); });
      });
      this.addEventListener("keydown", function (event) { self._onKey(event); });
      this.addEventListener("pointerleave", function () { self._scheduleIdle(); });

      this._resizeObserver = typeof ResizeObserver === "function"
        ? new ResizeObserver(function () { self._layout(); }) : null;
    }

    _bind() {
      var e = this._els;
      var video = this.querySelector("video");
      if (video !== this._video) {
        this._unbind();
        this._video = video;
        if (video) {
          video.controls = false;
          this._applyPrefs(video);
          this._applyHandoff(video);
          for (var i = 0; i < VIDEO_EVENTS.length; i++) { video.addEventListener(VIDEO_EVENTS[i], this._onVideoEvent); }
        }
      }
      if (!this._docBound) {
        this._docBound = true;
        document.addEventListener("fullscreenchange", this._onDocumentChange);
        document.addEventListener("webkitfullscreenchange", this._onDocumentChange);
        document.addEventListener("pointerdown", this._onOutsidePointer, true);
        if (this._resizeObserver) { this._resizeObserver.observe(this); }
      }
      var canPip = !!(document.pictureInPictureEnabled && video && video.requestPictureInPicture && !video.disablePictureInPicture);
      this.classList.toggle("no-pip", !canPip);
      this.classList.toggle("enlargeable", /^(small|extra-small)$/.test(this.getAttribute("data-media-size") || ""));
      this.classList.toggle("in-panel", this.hasAttribute("data-miniplayer-panel"));
      // A video the viewer pressed play on (it autoplays muted) is theirs, unlike a silent preview.
      if (this.hasAttribute("data-user-started")) { this._userPlay = true; }
      e.tip.hidden = true;
      this._layout();
      this._sync();
    }

    _unbind() {
      var v = this._video;
      if (!v) { return; }
      for (var i = 0; i < VIDEO_EVENTS.length; i++) { v.removeEventListener(VIDEO_EVENTS[i], this._onVideoEvent); }
      this._video = null;
    }

    // A video the miniplayer panel hands over from a page starts where that one was (`data-start-at`, seconds) and,
    // if it was playing, carries on (`data-resume`). Setting the position before metadata is known is remembered
    // by the browser; it's set again on `loadedmetadata` for streams (hls.js) that can ignore the early one.
    _applyHandoff(video) {
      var startAt = parseFloat(this.getAttribute("data-start-at"));
      if (isFinite(startAt) && startAt > 0) {
        try { video.currentTime = startAt; } catch (e) { /* set again below */ }
        video.addEventListener("loadedmetadata", function seek() {
          video.removeEventListener("loadedmetadata", seek);
          if (Math.abs(video.currentTime - startAt) > 1) { video.currentTime = startAt; }
        });
      }
      if (this.hasAttribute("data-resume")) {
        this._userPlay = true;
        var resume = function () {
          var played = video.play();
          if (played && played.catch) { played.catch(function () { /* autoplay blocked: waits for a click */ }); }
        };
        // A stream (HLS) is handed to hls.js a moment after it's inserted, which reloads the element and would drop a
        // `play()` made before then: wait for `index.html`'s attach (or, if that never comes, a few seconds) first.
        var isStream = /\.m3u8(\?|#|$)/.test(video.getAttribute("src") || "");
        if (!isStream || (typeof window.rellmHlsFor === "function" && window.rellmHlsFor(video))) {
          resume();
        } else {
          var done = false;
          var once = function () { if (!done) { done = true; video.removeEventListener("rellm-hls-attached", once); resume(); } };
          video.addEventListener("rellm-hls-attached", once);
          setTimeout(once, 4000);
        }
      }
    }

    // ---- miniplayer ------------------------------------------------------------------------------------

    // Asks the app to carry this video on in the floating miniplayer (`Shared.VideoPlayerPanel`), where `from` is the
    // page it was on. `index.html` forwards the event to Elm over a port.
    _requestMiniplayer(from) {
      var v = this._video;
      if (!v) { return false; }
      var original = typeof window.rellmOriginalSrc === "function" ? window.rellmOriginalSrc(v) : v.getAttribute("src");
      var src = (original || "").split("#")[0];
      if (!src) { return false; }
      window.dispatchEvent(new CustomEvent("rellm-miniplayer", {
        detail: {
          src: src,
          poster: v.getAttribute("poster") || null,
          time: v.currentTime || 0,
          playing: !v.paused && !v.ended,
          aspectRatio: v.videoWidth > 0 && v.videoHeight > 0 ? v.videoWidth / v.videoHeight : 16 / 9,
          title: pageTitle(),
          returnUrl: from
        }
      }));
      return true;
    }

    // The miniplayer button / `i`: the video moves to the floating player and this one stops.
    _miniplayer() {
      if (this.hasAttribute("data-miniplayer-panel")) { return; }
      if (this._requestMiniplayer(window.location.href)) {
        var v = this._video;
        if (v) { v.pause(); }
        this._toast("Miniplayer");
      }
    }

    // A video the viewer started that is still playing when its page is replaced by a navigation (Elm removes the
    // element, within a moment of the history change) goes to the miniplayer instead of stopping. Silent autoplay
    // previews never count: only a video someone chose to play.
    _miniplayerIfNavigatedAway() {
      var v = this._video;
      if (!v || this.hasAttribute("data-miniplayer-panel") || !this._userPlay) { return; }
      var navigation = media.lastNavigation();
      if (v.paused || v.ended || Date.now() - navigation.time > 1500) { return; }
      this._requestMiniplayer(navigation.from);
    }

    // Remembered volume, mute and speed. A muted-autoplay video (a feed preview) is left muted, and a saved
    // "muted" only applies to videos that aren't autoplaying -- they can't start unmuted anyway.
    _applyPrefs(video) {
      var saved = prefs.get();
      if (typeof saved.volume === "number") { video.volume = clamp(saved.volume, 0, 1); }
      if (typeof saved.rate === "number" && SPEEDS.indexOf(saved.rate) >= 0) {
        video.defaultPlaybackRate = saved.rate;
        video.playbackRate = saved.rate;
      }
      if (saved.muted === true && !video.autoplay) { video.muted = true; }
    }

    // ---- events from the <video> --------------------------------------------------------------------

    _onVideo(event) {
      var v = this._video;
      var e = this._els;
      if (!v) { return; }
      this._reportToQueue(event.type);
      switch (event.type) {
        case "play":
          this._claimMediaSession();
          break;
        case "volumechange":
          // Unmuting a playing video is choosing to watch it, too.
          if (!v.paused && !v.muted && v.volume > 0) { this._userPlay = true; }
          break;
        case "waiting":
        case "stalled":
          if (!v.paused || v.seeking) { e.spinner.hidden = false; }
          break;
        case "seeking":
          e.spinner.hidden = false;
          break;
        case "playing":
        case "canplay":
        case "seeked":
        case "pause":
        case "ended":
          e.spinner.hidden = true;
          break;
        case "error":
        case "rellm-hls-error":
          e.spinner.hidden = true;
          e.message.textContent = "This video can\u2019t be played.";
          e.message.hidden = false;
          break;
        case "loadedmetadata":
        case "emptied":
          e.message.hidden = true;
          break;
        default:
          break;
      }
      this._sync();
    }

    // ---- OS media controls ---------------------------------------------------------------------------

    _claimMediaSession() {
      var session = navigator.mediaSession;
      var self = this;
      if (!session) { return; }
      sessionOwner = this;
      var set = function (action, handler) { try { session.setActionHandler(action, handler); } catch (e) { /* not supported here */ } };
      try { session.metadata = new window.MediaMetadata({ title: document.title }); } catch (e) { /* not supported here */ }
      set("play", function () { var v = self._video; if (v) { v.play(); } });
      set("pause", function () { var v = self._video; if (v) { v.pause(); } });
      set("seekbackward", function (details) { self._seekBy(-((details && details.seekOffset) || BIG_SKIP_SECONDS)); });
      set("seekforward", function (details) { self._seekBy((details && details.seekOffset) || BIG_SKIP_SECONDS); });
      set("seekto", function (details) {
        var v = self._video;
        if (v && details && typeof details.seekTime === "number") { v.currentTime = details.seekTime; }
      });
      set("enterpictureinpicture", function () {
        var v = self._video;
        if (v && !self.classList.contains("no-pip") && document.pictureInPictureElement !== v) { v.requestPictureInPicture().catch(function () {}); }
      });
    }

    _releaseMediaSession() {
      var session = navigator.mediaSession;
      if (!session || sessionOwner !== this) { return; }
      sessionOwner = null;
      ["play", "pause", "seekbackward", "seekforward", "seekto", "enterpictureinpicture"].forEach(function (action) {
        try { session.setActionHandler(action, null); } catch (e) { /* not supported here */ }
      });
      try { session.metadata = null; } catch (e) { /* not supported here */ }
    }

    // The miniplayer's video tells the queue (`Shared.AudioPlayerPanel`, via `index.html`'s port) where it is, whether it's
    // playing, and when it ends -- the bar shows the position, and the end means "next".
    _reportToQueue(type) {
      var v = this._video;
      if (!v || !this.hasAttribute("data-miniplayer-panel")) { return; }
      if (["play", "pause", "timeupdate", "durationchange", "loadedmetadata", "seeked", "ended"].indexOf(type) < 0) { return; }
      window.dispatchEvent(new CustomEvent("rellm-miniplayer-state", {
        detail: {
          playing: !v.paused && !v.ended,
          positionMs: Math.round((v.currentTime || 0) * 1000),
          durationMs: isFinite(v.duration) ? Math.round(v.duration * 1000) : 0,
          ended: type === "ended"
        }
      }));
    }

    // ---- actions ------------------------------------------------------------------------------------

    _togglePlay() {
      var v = this._video;
      if (!v) { return; }
      if (v.paused || v.ended) {
        this._userPlay = true;
        var played = v.play();
        if (played && played.catch) { played.catch(function () {}); }
      } else {
        v.pause();
      }
    }

    _seekBy(seconds) {
      var v = this._video;
      if (!v || !isFinite(v.duration)) { return; }
      v.currentTime = clamp(v.currentTime + seconds, 0, v.duration);
      this._toast((seconds > 0 ? "+" : "\u2212") + Math.abs(seconds) + "s");
    }

    _seekToFraction(fraction) {
      var v = this._video;
      if (!v || !isFinite(v.duration)) { return; }
      v.currentTime = clamp(fraction, 0, 1) * v.duration;
    }

    _setVolume(volume, fromSlider) {
      var v = this._video;
      if (!v) { return; }
      volume = clamp(volume, 0, 1);
      v.volume = volume;
      v.muted = volume === 0;
      prefs.set(volume > 0 ? { volume: volume, muted: false } : { muted: true });
      if (!fromSlider) { this._toast("Volume " + Math.round(volume * 100) + "%"); }
    }

    _toggleMute() {
      var v = this._video;
      if (!v) { return; }
      v.muted = !v.muted;
      // Unmuting from zero volume has to bring some volume back.
      if (!v.muted && v.volume === 0) { v.volume = 0.5; }
      prefs.set({ muted: v.muted });
    }

    _setRate(rate) {
      var v = this._video;
      if (!v) { return; }
      v.defaultPlaybackRate = rate;
      v.playbackRate = rate;
      prefs.set({ rate: rate });
      this._toast(formatRate(rate));
    }

    _stepRate(direction) {
      var v = this._video;
      if (!v) { return; }
      var index = SPEEDS.indexOf(v.playbackRate);
      if (index < 0) { index = SPEEDS.indexOf(1); }
      var next = clamp(index + direction, 0, SPEEDS.length - 1);
      if (next !== index) { this._setRate(SPEEDS[next]); }
    }

    _fullscreenElement() {
      return document.fullscreenElement || document.webkitFullscreenElement || null;
    }

    _toggleFullscreen() {
      var v = this._video;
      if (this._fullscreenElement() === this) {
        (document.exitFullscreen || document.webkitExitFullscreen).call(document);
      } else if (this.requestFullscreen) {
        this.requestFullscreen().catch(function () {});
      } else if (this.webkitRequestFullscreen) {
        this.webkitRequestFullscreen();
      } else if (v && v.webkitEnterFullscreen) {
        v.webkitEnterFullscreen(); // iPhone Safari can only fullscreen the <video> itself
      }
    }

    _togglePip() {
      var v = this._video;
      if (!v || !v.requestPictureInPicture) { return; }
      var request = document.pictureInPictureElement === v ? document.exitPictureInPicture() : v.requestPictureInPicture();
      if (request && request.catch) { request.catch(function () {}); }
    }

    // A thumbnail grows to the size `Components.MediaRenderer.Natural` gives a video (see `media.css`'s
    // `.enlarged` rules); the restore button puts it back.
    _setEnlarged(enlarged) {
      this.classList.toggle("enlarged", enlarged);
      this._layout();
      this._sync();
      var self = this;
      if (enlarged) {
        // The strip may have it partly off-screen once it's bigger.
        requestAnimationFrame(function () {
          if (typeof self.scrollIntoView === "function") { self.scrollIntoView({ block: "nearest", inline: "nearest" }); }
        });
      }
      this.dispatchEvent(new CustomEvent(enlarged ? "rellm-video-enlarge" : "rellm-video-restore", { bubbles: true, composed: true }));
    }

    // ---- picture clicks, double-clicks, keyboard ------------------------------------------------------

    _onPictureClick(event) {
      var v = this._video;
      if (!v || event.composedPath()[0] !== v) { return; }
      if (this._revealTap) { this._revealTap = false; return; }
      this._togglePlay();
      var now = Date.now();
      var previous = this._lastClick;
      this._lastClick = { time: now, x: event.clientX, y: event.clientY };
      if (!previous || now - previous.time > 320 || Math.abs(previous.x - event.clientX) > 40 || Math.abs(previous.y - event.clientY) > 40) { return; }
      this._lastClick = null;
      var rect = this.getBoundingClientRect();
      var fraction = rect.width > 0 ? (event.clientX - rect.left) / rect.width : 0.5;
      if (fraction < 0.33) {
        this._seekBy(-BIG_SKIP_SECONDS);
      } else if (fraction > 0.67) {
        this._seekBy(BIG_SKIP_SECONDS);
      } else {
        this._toggleFullscreen();
      }
    }

    _onKey(event) {
      var v = this._video;
      if (!v || event.ctrlKey || event.metaKey || event.altKey) { return; }
      var target = event.composedPath()[0];
      var tag = target && target.tagName;
      var onInput = tag === "INPUT";
      var onButton = tag === "BUTTON";
      var handled = true;
      switch (event.key) {
        case " ":
          if (onButton || onInput) { handled = false; } else { this._togglePlay(); }
          break;
        case "k": case "K": this._togglePlay(); break;
        case "ArrowLeft": if (onInput) { handled = false; } else { this._seekBy(-SKIP_SECONDS); } break;
        case "ArrowRight": if (onInput) { handled = false; } else { this._seekBy(SKIP_SECONDS); } break;
        case "j": case "J": this._seekBy(-BIG_SKIP_SECONDS); break;
        case "l": case "L": this._seekBy(BIG_SKIP_SECONDS); break;
        case "ArrowUp": if (onInput) { handled = false; } else { this._setVolume((v.muted ? 0 : v.volume) + 0.05); } break;
        case "ArrowDown": if (onInput) { handled = false; } else { this._setVolume((v.muted ? 0 : v.volume) - 0.05); } break;
        case "m": case "M": this._toggleMute(); this._toast(v.muted ? "Muted" : "Volume " + Math.round(v.volume * 100) + "%"); break;
        case "f": case "F": this._toggleFullscreen(); break;
        case "i": case "I": if (!this.classList.contains("in-panel")) { this._miniplayer(); } else { handled = false; } break;
        case "p": case "P": if (!this.classList.contains("no-pip")) { this._togglePip(); } else { handled = false; } break;
        case "<": this._stepRate(-1); break;
        case ">": this._stepRate(1); break;
        case "Home": if (onInput) { handled = false; } else { this._seekToFraction(0); } break;
        case "End": if (onInput) { handled = false; } else { this._seekToFraction(1); } break;
        case "Escape":
          if (this._menuOpen || this._volumeOpen()) { this._closeMenu(); this._closeVolume(); } else { handled = false; }
          break;
        default:
          if (/^[0-9]$/.test(event.key) && !onInput) { this._seekToFraction(Number(event.key) / 10); } else { handled = false; }
      }
      if (handled) {
        event.preventDefault();
        event.stopPropagation(); // the page has its own shortcuts; these belong to the player while it has focus
        this._wake();
      }
    }

    // ---- popups: volume slider, settings menu ---------------------------------------------------------

    _volumeOpen() {
      return this._els.vols.some(function (vol) { return vol.classList.contains("open"); });
    }

    _openVolume(vol) {
      this._els.vols.forEach(function (other) { other.classList.toggle("open", other === vol); });
      this._scheduleVolumeClose(VOLUME_PANEL_MS);
    }

    _closeVolume() {
      clearTimeout(this._volTimer);
      this._els.vols.forEach(function (vol) { vol.classList.remove("open"); });
    }

    _scheduleVolumeClose(ms) {
      var self = this;
      clearTimeout(this._volTimer);
      this._volTimer = setTimeout(function () {
        // Stays up while the pointer or keyboard focus is inside it.
        var inside = self._els.vols.some(function (vol) { return vol.matches(":hover") || vol.matches(":focus-within"); });
        if (inside) { self._scheduleVolumeClose(VOLUME_PANEL_MS); } else { self._closeVolume(); }
      }, ms);
    }

    _closePopupsFor(event) {
      var path = event.composedPath();
      if (this._menuOpen && path.indexOf(this._els.menu) < 0 && path.indexOf(this._els.speed) < 0) { this._closeMenu(); }
      if (this._volumeOpen() && !this._els.vols.some(function (vol) { return path.indexOf(vol) >= 0; })) { this._closeVolume(); }
    }

    _toggleMenu() {
      if (this._menuOpen) { this._closeMenu(); } else { this._openMenu(); }
    }

    _closeMenu() {
      this._menuOpen = false;
      this._els.menu.hidden = true;
      this._els.speed.setAttribute("aria-expanded", "false");
    }

    _hls() {
      return this._video && typeof window.rellmHlsFor === "function" ? window.rellmHlsFor(this._video) : null;
    }

    _openMenu() {
      var self = this;
      var v = this._video;
      var menu = this._els.menu;
      if (!v) { return; }
      var item = function (label, checked, role, onChoose) {
        var button = document.createElement("button");
        button.type = "button";
        button.setAttribute("role", role);
        button.setAttribute("aria-checked", checked ? "true" : "false");
        button.textContent = label;
        // Like YouTube's, the menu closes once a choice is made (and focus goes back to its button).
        button.addEventListener("click", function () { onChoose(); self._closeMenu(); self._els.speed.focus({ preventScroll: true }); });
        return button;
      };
      var heading = function (text) { var h = document.createElement("h4"); h.textContent = text; return h; };
      menu.textContent = "";
      menu.appendChild(heading("Speed"));
      SPEEDS.forEach(function (rate) {
        menu.appendChild(item(rate === 1 ? "Normal" : formatRate(rate), v.playbackRate === rate, "menuitemradio", function () { self._setRate(rate); }));
      });
      var hls = this._hls();
      if (hls && hls.levels && hls.levels.length > 1) {
        menu.appendChild(heading("Quality"));
        menu.appendChild(item("Auto", !!hls.autoLevelEnabled, "menuitemradio", function () { hls.currentLevel = -1; }));
        hls.levels
          .map(function (level, index) { return { level: level, index: index }; })
          .sort(function (a, b) { return (b.level.height || 0) - (a.level.height || 0); })
          .forEach(function (entry) {
            var label = entry.level.height ? entry.level.height + "p" : Math.round((entry.level.bitrate || 0) / 1000) + " kbps";
            menu.appendChild(item(label, !hls.autoLevelEnabled && hls.currentLevel === entry.index, "menuitemradio", function () { hls.currentLevel = entry.index; }));
          });
      }
      menu.appendChild(heading("Playback"));
      menu.appendChild(item("Loop", v.loop, "menuitemcheckbox", function () { v.loop = !v.loop; self._toast(v.loop ? "Loop on" : "Loop off"); }));
      this._menuOpen = true;
      menu.hidden = false;
      this._els.speed.setAttribute("aria-expanded", "true");
      this._layout(); // sizes the menu's max-height to the frame
      var checked = menu.querySelector("[aria-checked=true]");
      if (checked && checked.scrollIntoView) { checked.scrollIntoView({ block: "nearest" }); }
    }

    // ---- idle fade, toast, tooltip ---------------------------------------------------------------------

    // Controls fade out a moment after playback starts and the pointer rests; they stay up while paused or
    // while a popup is open.
    _wake() {
      this.classList.remove("idle");
      this._scheduleIdle();
    }

    _scheduleIdle() {
      var self = this;
      clearTimeout(this._idleTimer);
      this._idleTimer = setTimeout(function () {
        self._idleTimer = null;
        var v = self._video;
        if (v && !v.paused && !v.ended && !self._dragging && !self._menuOpen && !self._volumeOpen() && !self.matches(":focus-within")) {
          self.classList.add("idle");
        }
      }, IDLE_MS);
    }

    _toast(text) {
      var el = this._els.toast;
      el.textContent = text;
      el.classList.add("show");
      clearTimeout(this._toastTimer);
      this._toastTimer = setTimeout(function () { el.classList.remove("show"); }, 900);
    }

    _showTip(event) {
      var v = this._video;
      var e = this._els;
      if (!v || !isFinite(v.duration) || v.duration <= 0) { return; }
      var rect = e.seek.getBoundingClientRect();
      if (rect.width <= 0) { return; }
      var fraction = clamp((event.clientX - rect.left) / rect.width, 0, 1);
      e.tip.textContent = formatTime(fraction * v.duration);
      e.tip.style.left = clamp(event.clientX - e.seekwrap.getBoundingClientRect().left, 18, rect.width - 18) + "px";
      e.tip.hidden = false;
    }

    // ---- layout and state sync -------------------------------------------------------------------------

    // Narrow/short frames (thumbnails, the strip) get the trimmed layout; very narrow ones (a portrait video at
    // thumbnail height is ~50px wide) lose the seek bar too.
    _layout() {
      var rect = this.getBoundingClientRect();
      this.classList.toggle("compact", rect.width > 0 && (rect.width < 300 || rect.height < 140));
      this.classList.toggle("tiny", rect.width > 0 && rect.width < 120);
      var video = this._video;
      var canFullscreen = !!(this.requestFullscreen || this.webkitRequestFullscreen || (video && video.webkitEnterFullscreen));
      this.classList.toggle("no-fullscreen", !canFullscreen);
      // Slider and menu heights follow the frame, so they fit inside a small one.
      this.style.setProperty("--rv-frame-h", rect.height + "px");
      this.style.setProperty("--rv-vol-h", clamp(rect.height - 96, 40, 96) + "px");
    }

    _sync() {
      var v = this._video;
      var e = this._els;
      if (!v || !e) { return; }
      var playing = !v.paused && !v.ended;
      var duration = v.duration;
      var hasDuration = isFinite(duration) && duration > 0;

      e.play.innerHTML = playing ? ICONS.pause : (v.ended ? ICONS.replay : ICONS.play);
      e.play.setAttribute("aria-label", playing ? "Pause" : (v.ended ? "Replay" : "Play"));
      // The big center button: before the first play and after the end (never while autoplaying).
      var showBig = !playing && !v.autoplay && (v.currentTime === 0 || v.ended);
      e.big.classList.toggle("hidden", !showBig);
      e.big.innerHTML = v.ended ? ICONS.replay : ICONS.play;
      e.big.setAttribute("aria-label", v.ended ? "Replay" : "Play");

      var silent = v.muted || v.volume === 0;
      var level = silent ? 0 : Math.round(v.volume * 100);
      e.mute.forEach(function (button) {
        button.innerHTML = silent ? ICONS.muted : (level < 50 ? ICONS.volumeLow : ICONS.volume);
        button.setAttribute("aria-label", silent ? "Unmute" : "Mute");
      });
      e.volSliders.forEach(function (slider) {
        slider.value = level;
        slider.style.setProperty("--progress", level + "%");
        slider.setAttribute("aria-valuetext", level + "%");
      });

      var isFullscreen = this._fullscreenElement() === this;
      e.fs.forEach(function (button) {
        button.innerHTML = isFullscreen ? ICONS.exitFullscreen : ICONS.fullscreen;
        button.setAttribute("aria-label", isFullscreen ? "Exit fullscreen" : "Fullscreen");
      });
      e.pip.innerHTML = ICONS.pip;
      e.mini.innerHTML = ICONS.mini;
      e.enlarge.innerHTML = ICONS.enlarge;
      e.restore.innerHTML = ICONS.restore;
      e.speed.textContent = formatRate(v.playbackRate || 1);

      this.classList.toggle("no-duration", !hasDuration);
      e.cur.textContent = formatTime(v.currentTime);
      e.dur.textContent = hasDuration ? formatTime(duration) : "0:00";
      if (!this._dragging) {
        var fraction = hasDuration ? Math.min(1, v.currentTime / duration) : 0;
        e.seek.value = Math.round(fraction * 1000);
      }
      e.seek.style.setProperty("--progress", e.seek.value / 10 + "%");
      var buffered = 0;
      if (hasDuration && v.buffered) {
        for (var i = 0; i < v.buffered.length; i++) {
          if (v.buffered.start(i) <= v.currentTime + 0.5 && v.buffered.end(i) > buffered) { buffered = v.buffered.end(i); }
        }
      }
      e.seek.style.setProperty("--buffered", (hasDuration ? Math.min(100, (buffered / duration) * 100) : 0) + "%");
      e.seek.setAttribute("aria-valuetext", formatTime(v.currentTime) + " of " + (hasDuration ? formatTime(duration) : "unknown length"));

      // Start the fade-out countdown once, when playback starts (`timeupdate` syncs must not keep restarting it).
      if (playing) {
        if (!this._idleTimer && !this.classList.contains("idle")) { this._scheduleIdle(); }
      } else {
        clearTimeout(this._idleTimer);
        this._idleTimer = null;
        this.classList.remove("idle");
      }
    }
  }

  customElements.define("rellm-video", RellmVideo);
})();
