// Content script: publishes Media Session and media element state to the
// Beardie Now Playing background page.

(function () {
  const NP = self.BeardieNowPlaying;
  if (!NP || !NP.api || !NP.api.runtime) {
    return;
  }

  const api = NP.api;
  let sendTimer = null;
  let mediaPollTimer = null;

  function mediaElements() {
    return Array.from(document.querySelectorAll("audio, video"));
  }

  function primaryMediaElement() {
    const elements = mediaElements();
    if (elements.length === 0) {
      return null;
    }
    return (
      elements.find((element) => !element.paused && element.currentTime > 0) ||
      elements.find((element) => !element.paused) ||
      elements.find((element) => element.currentTime > 0) ||
      elements[0]
    );
  }

  function metadata() {
    const session = navigator.mediaSession;
    const data = session && session.metadata;
    if (!data) {
      return {
        title: document.title || null,
        artist: null,
        album: null,
        artworkURLs: []
      };
    }
    return {
      title: data.title || document.title || null,
      artist: data.artist || null,
      album: data.album || null,
      artworkURLs: (data.artwork || []).map((item) => item.src).filter(Boolean)
    };
  }

  function collectState() {
    const element = primaryMediaElement();
    if (!element) {
      return null;
    }
    const data = metadata();
    const playing = !element.paused && !element.ended;
    return {
      title: data.title,
      artist: data.artist,
      album: data.album,
      artworkURLs: data.artworkURLs,
      playbackState: playing ? "playing" : "paused",
      position: Number.isFinite(element.currentTime) ? element.currentTime : null,
      duration: Number.isFinite(element.duration) ? element.duration : null,
      playbackRate: Number.isFinite(element.playbackRate) ? element.playbackRate : null
    };
  }

  function sendState() {
    const state = collectState();
    try {
      api.runtime.sendMessage({ type: "mediaState", state: state });
    } catch (_) {
      // The background may be restarting; the next poll will retry.
    }
  }

  function scheduleState() {
    if (sendTimer) {
      clearTimeout(sendTimer);
    }
    sendTimer = setTimeout(sendState, 200);
  }

  function ensurePolling() {
    if (mediaPollTimer) {
      return;
    }
    mediaPollTimer = setInterval(sendState, 1000);
  }

  ["play", "pause", "ended", "loadedmetadata", "durationchange", "seeked", "ratechange", "volumechange"].forEach(
    (eventName) => document.addEventListener(eventName, scheduleState, true)
  );
  document.addEventListener("visibilitychange", scheduleState, true);
  ensurePolling();

  api.runtime.onMessage.addListener(function (message, _sender, sendResponse) {
    if (!message || message.type !== "command") {
      return false;
    }

    const element = primaryMediaElement();
    if (!element) {
      sendResponse({ success: false, error: "no-media-element" });
      return false;
    }

    try {
      switch (message.command) {
        case "play":
          element.play();
          break;
        case "pause":
          element.pause();
          break;
        case "toggle":
          if (element.paused) {
            element.play();
          } else {
            element.pause();
          }
          break;
        case "seek":
          if (typeof message.position === "number") {
            element.currentTime = message.position;
          }
          break;
        default:
          sendResponse({ success: false, error: "unsupported-command" });
          return false;
      }
      sendResponse({ success: true });
    } catch (error) {
      sendResponse({ success: false, error: String(error) });
    }
    return false;
  });

  sendState();
})();
