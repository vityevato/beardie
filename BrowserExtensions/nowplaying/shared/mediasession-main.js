// MAIN-world shim: lets the isolated content script invoke the page's Media
// Session action handlers (for example nexttrack/previoustrack), which the
// isolated world cannot reach directly.
//
// The content script sends a DOM event with a request id; this shim calls the
// handler the page registered with navigator.mediaSession.setActionHandler and
// settles the request with a second DOM event.

(function () {
  if (window.__beardieNowPlayingMainShim) {
    return;
  }
  window.__beardieNowPlayingMainShim = true;

  const REQUEST_EVENT = "beardie-nowplaying-command";
  const RESULT_EVENT = "beardie-nowplaying-command-result";
  const handlers = Object.create(null);

  function remember(action, handler) {
    if (typeof handler === "function") {
      handlers[action] = handler;
    } else {
      delete handlers[action];
    }
  }

  try {
    const session = navigator.mediaSession;
    if (session && typeof session.setActionHandler === "function") {
      const original = session.setActionHandler.bind(session);
      session.setActionHandler = function (action, handler) {
        remember(action, handler);
        try {
          return original(action, handler);
        } catch (_) {
          return undefined;
        }
      };
    }
  } catch (_) {
    // A locked-down mediaSession object is not fatal: the shim simply has no
    // handlers and the content script reports that the command is unsupported.
  }

  function reply(detail) {
    try {
      document.dispatchEvent(new CustomEvent(RESULT_EVENT, { detail: detail }));
    } catch (_) {
      // The page may have removed the document; nothing else to do.
    }
  }

  document.addEventListener(REQUEST_EVENT, function (event) {
    const detail = event && event.detail;
    if (!detail || !detail.requestId) {
      return;
    }

    const action = detail.command;
    const handler = handlers[action];
    if (typeof handler !== "function") {
      reply({ requestId: detail.requestId, success: false, error: "no-handler" });
      return;
    }

    try {
      const result = handler({
        action: action,
        seekTime: typeof detail.position === "number" ? detail.position : undefined,
        seekOffset: undefined
      });
      if (result && typeof result.then === "function") {
        result.then(
          function () {
            reply({ requestId: detail.requestId, success: true });
          },
          function (error) {
            reply({ requestId: detail.requestId, success: false, error: String(error) });
          }
        );
      } else {
        reply({ requestId: detail.requestId, success: true });
      }
    } catch (error) {
      reply({ requestId: detail.requestId, success: false, error: String(error) });
    }
  });
})();
