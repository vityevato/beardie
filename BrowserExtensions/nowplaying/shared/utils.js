// Beardie Now Playing browser bridge helpers.
// Shared by the Chrome MV3 service worker, the Safari event page and content scripts.

(function (global) {
  const api = global.browser || global.chrome;

  function uuid() {
    if (global.crypto && typeof global.crypto.randomUUID === "function") {
      return global.crypto.randomUUID();
    }
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function cleanUrl(value) {
    try {
      const url = new URL(value);
      return url.origin + url.pathname;
    } catch (_) {
      return value || "";
    }
  }

  function log() {
    if (typeof console !== "undefined" && console.debug) {
      console.debug.apply(console, ["[Beardie NowPlaying]"].concat(Array.from(arguments)));
    }
  }

  global.BeardieNowPlaying = {
    api: api,
    uuid: uuid,
    cleanUrl: cleanUrl,
    log: log
  };
})(typeof self !== "undefined" ? self : this);
