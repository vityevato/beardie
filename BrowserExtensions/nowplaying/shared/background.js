// Background bridge: discovers the Beardie loopback endpoint through native
// messaging, keeps a WebSocket open and publishes tab/media state.
//
// This file is shared by the Chrome MV3 service worker and the Safari event
// page. It expects `constants.js` and `shared/utils.js` to be loaded first.

(function () {
  const NP = self.BeardieNowPlaying;
  if (!NP || !NP.api) {
    return;
  }

  const api = NP.api;
  const PROTOCOL_VERSION = 1;
  const HOST = "127.0.0.1";
  const PATH = "/nowplaying";
  const RECONNECT_DELAY = 5000;
  const NATIVE_RETRY_DELAY = 5000;
  const INSTANCE_ID_KEY = "BeardieNowPlayingInstanceId";

  const NATIVE_HOST =
    (typeof BSConstants !== "undefined" && BSConstants.BS_B_NATIVE_MESSAGING_CONNECTOR_BUNDLE_ID) ||
    "com.calm-apps.mac.beardie";

  let instanceId = null;
  let socket = null;
  let bridgeInfo = null;
  let connectTimer = null;
  let connecting = false;
  let snapshotTimer = null;
  let snapshotInFlight = false;
  let statePending = false;
  let refreshPromise = null;
  let previousContext = null;
  const tabMedia = new Map();
  const tabMediaFrames = new Map();

  function log() {
    NP.log.apply(null, Array.from(arguments));
  }

  function storageGet(key) {
    return new Promise((resolve) => {
      try {
        const result = api.storage.local.get(key);
        if (result && typeof result.then === "function") {
          result.then((value) => resolve(value ? value[key] : null)).catch(() => resolve(null));
          return;
        }
      } catch (_) {
        // Fall through to the callback form.
      }
      api.storage.local.get(key, (value) => resolve(value ? value[key] : null));
    });
  }

  function storageSet(key, value) {
    try {
      const result = api.storage.local.set({ [key]: value });
      if (result && typeof result.catch === "function") {
        result.catch(() => {});
      }
    } catch (_) {
      // Storage is best effort.
    }
  }

  async function ensureInstanceId() {
    if (instanceId) {
      return instanceId;
    }
    const stored = await storageGet(INSTANCE_ID_KEY);
    instanceId = stored || NP.uuid();
    storageSet(INSTANCE_ID_KEY, instanceId);
    return instanceId;
  }

  function nativeRequest(message) {
    return new Promise((resolve, reject) => {
      try {
        api.runtime.sendNativeMessage(NATIVE_HOST, message, (response) => {
          if (api.runtime.lastError) {
            reject(new Error(api.runtime.lastError.message || "native messaging failed"));
            return;
          }
          if (!response) {
            reject(new Error("empty native response"));
            return;
          }
          resolve(response);
        });
      } catch (error) {
        reject(error);
      }
    });
  }

  async function discoverBridge() {
    const response = await nativeRequest({ msg: "bridge", id: NP.uuid() });
    const body = response.body || response;
    storageSet(
      "BeardieNowPlayingBridgeResponse",
      JSON.stringify({
        responseKeys: response && typeof response === "object" ? Object.keys(response) : [],
        bodyKeys: body && typeof body === "object" ? Object.keys(body) : [],
        port: body && body.port,
        protocolVersion: body && body.protocolVersion,
        error: body && body.error
      })
    );
    if (!body || !body.port || !body.token || body.protocolVersion !== PROTOCOL_VERSION) {
      throw new Error("bridge endpoint is not available");
    }
    return body;
  }

  function sendJSON(object) {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      return false;
    }
    socket.send(JSON.stringify(object));
    return true;
  }

  function sendAck(requestId, success, error) {
    if (!requestId) {
      return;
    }
    sendJSON({ type: "ack", requestId: requestId, success: success, error: error || null });
  }

  function tabPayload(tab, media, now) {
    return {
      tabId: tab.id,
      windowId: tab.windowId,
      active: Boolean(tab.active),
      title: tab.title || null,
      url: tab.url ? NP.cleanUrl(tab.url) : null,
      mediaTitle: media && media.title ? media.title : null,
      artist: media && media.artist ? media.artist : null,
      album: media && media.album ? media.album : null,
      playbackState: media && media.playbackState ? media.playbackState : null,
      position: media && typeof media.position === "number" ? media.position : null,
      duration: media && typeof media.duration === "number" ? media.duration : null,
      artworkURLs: (media && media.artworkURLs) || [],
      updatedAt: now
    };
  }

  function queryTabs() {
    return new Promise((resolve) => {
      try {
        const result = api.tabs.query({});
        if (result && typeof result.then === "function") {
          result.then(resolve).catch(() => resolve([]));
          return;
        }
      } catch (_) {
        // Fall through to the callback form.
      }
      api.tabs.query({}, (tabs) => resolve(tabs || []));
    });
  }

  async function sendState() {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      return;
    }
    if (snapshotInFlight) {
      statePending = true;
      return;
    }
    snapshotInFlight = true;
    try {
      const tabs = await queryTabs();
      const now = Date.now();
      sendJSON({
        type: "state",
        instanceId: instanceId,
        tabs: tabs.map((tab) => tabPayload(tab, tabMedia.get(tab.id), now))
      });
    } catch (error) {
      log("state snapshot failed", error);
    } finally {
      snapshotInFlight = false;
      if (statePending) {
        statePending = false;
        sendState();
      }
    }
  }

  function scheduleState() {
    if (snapshotTimer) {
      clearTimeout(snapshotTimer);
    }
    snapshotTimer = setTimeout(sendState, 250);
  }

  // Content scripts run in every frame. A YouTube page can have several
  // iframes; a frame without media must not erase the main frame's playing
  // state. Keep state per frame and expose one effective state per tab.
  function frameKey(sender, message) {
    if (sender && typeof sender.frameId === "number") {
      return sender.frameId;
    }
    return message && message.topFrame ? 0 : -1;
  }

  function betterFrame(state, frameId, bestState, bestFrameId) {
    const playing = state.playbackState === "playing";
    const bestPlaying = bestState.playbackState === "playing";
    if (playing !== bestPlaying) {
      return playing;
    }
    if (Boolean(state.title) !== Boolean(bestState.title)) {
      return Boolean(state.title);
    }
    return frameId < bestFrameId;
  }

  function effectiveMedia(tabId) {
    const frames = tabMediaFrames.get(tabId);
    if (!frames || frames.size === 0) {
      return null;
    }
    let bestState = null;
    let bestFrameId = Number.POSITIVE_INFINITY;
    for (const [frameId, state] of frames) {
      if (!state) {
        continue;
      }
      if (!bestState || betterFrame(state, frameId, bestState, bestFrameId)) {
        bestState = state;
        bestFrameId = frameId;
      }
    }
    return bestState;
  }

  function updateFrameMedia(tabId, frameId, state) {
    let frames = tabMediaFrames.get(tabId);
    if (!frames) {
      frames = new Map();
      tabMediaFrames.set(tabId, frames);
    }
    if (state) {
      frames.set(frameId, state);
    } else {
      frames.delete(frameId);
    }
    if (frames.size === 0) {
      tabMediaFrames.delete(tabId);
    }
    const effective = effectiveMedia(tabId);
    if (effective) {
      tabMedia.set(tabId, effective);
    } else {
      tabMedia.delete(tabId);
    }
  }

  function clearTabMedia(tabId) {
    tabMediaFrames.delete(tabId);
    tabMedia.delete(tabId);
  }

  function activeTab(windowId) {
    return new Promise((resolve) => {
      const query = windowId ? { active: true, windowId: windowId } : { active: true, lastFocusedWindow: true };
      try {
        const result = api.tabs.query(query);
        if (result && typeof result.then === "function") {
          result.then((tabs) => resolve(tabs && tabs.length ? tabs[0] : null)).catch(() => resolve(null));
          return;
        }
      } catch (_) {
        // Fall through to the callback form.
      }
      api.tabs.query(query, (tabs) => resolve(tabs && tabs.length ? tabs[0] : null));
    });
  }

  async function focusWindow(windowId) {
    if (!api.windows || typeof api.windows.update !== "function") {
      storageSet("BeardieNowPlayingLastFocusError", "windows.update is unavailable");
      return false;
    }
    try {
      const result = api.windows.update(windowId, { focused: true });
      if (result && typeof result.catch === "function") {
        await result;
      }
      storageSet("BeardieNowPlayingLastFocusError", "");
      return true;
    } catch (error) {
      storageSet("BeardieNowPlayingLastFocusError", String(error));
      log("window focus failed", error);
      return false;
    }
  }

  async function activateTab(message) {
    if (previousContext === null) {
      const current = await activeTab(message.windowId);
      if (current && current.id !== message.tabId) {
        previousContext = { tabId: current.id, windowId: current.windowId };
      }
    }

    try {
      const updateResult = api.tabs.update(message.tabId, { active: true });
      if (updateResult && typeof updateResult.catch === "function") {
        await updateResult;
      }
    } catch (error) {
      sendAck(message.requestId, false, String(error));
      return;
    }
    await focusWindow(message.windowId);
    sendAck(message.requestId, true);
  }

  async function restoreTab(message) {
    const target = previousContext || {
      tabId: message.tabId,
      windowId: message.windowId
    };
    previousContext = null;
    try {
      const updateResult = api.tabs.update(target.tabId, { active: true });
      if (updateResult && typeof updateResult.catch === "function") {
        await updateResult;
      }
    } catch (error) {
      sendAck(message.requestId, false, String(error));
      return;
    }
    await focusWindow(target.windowId);
    sendAck(message.requestId, true);
  }

  function tabMessage(tabId, message) {
    return new Promise((resolve) => {
      try {
        const result = api.tabs.sendMessage(tabId, message);
        if (result && typeof result.then === "function") {
          result.then(resolve).catch((error) => resolve({ success: false, error: String(error) }));
          return;
        }
      } catch (_) {
        // Fall through to the callback form.
      }
      api.tabs.sendMessage(tabId, message, (response) => resolve(response || { success: false }));
    });
  }

  function requestTabState(tabId) {
    return tabMessage(tabId, { type: "requestState" });
  }

  // Asks every content script for its current state. Content scripts respond
  // with per-frame mediaState messages, so wait briefly for those messages
  // before taking the snapshot.
  function refreshTabMedia() {
    if (refreshPromise) {
      return refreshPromise;
    }

    refreshPromise = (async function () {
      const tabs = await queryTabs();
      await Promise.all(
        tabs.map(async function (tab) {
          if (typeof tab.id !== "number" || (tab.url && !/^(https?|file):/i.test(tab.url))) {
            return;
          }
          await requestTabState(tab.id);
        })
      );
      await new Promise(function (resolve) {
        setTimeout(resolve, 100);
      });
    })();

    refreshPromise = refreshPromise.then(
      function () {
        refreshPromise = null;
      },
      function (error) {
        refreshPromise = null;
        log("state refresh failed", error);
      }
    );
    return refreshPromise;
  }

  async function refreshAndSendState() {
    try {
      await refreshTabMedia();
      await sendState();
    } catch (error) {
      log("state publish failed", error);
    }
  }

  async function commandTab(message) {
    const response = await tabMessage(message.tabId, {
      type: "command",
      command: message.command,
      position: message.position
    });
    sendAck(message.requestId, Boolean(response && response.success), response && response.error);
  }

  function handleServerMessage(event) {
    let message = null;
    try {
      message = JSON.parse(event.data);
    } catch (_) {
      return;
    }
    if (!message || !message.type) {
      return;
    }

    switch (message.type) {
      case "getState":
        refreshAndSendState();
        break;
      case "activateTab":
        activateTab(message);
        break;
      case "restoreTab":
        restoreTab(message);
        break;
      case "command":
        commandTab(message);
        break;
      default:
        break;
    }
  }

  function scheduleReconnect() {
    if (connectTimer) {
      return;
    }
    connectTimer = setTimeout(() => {
      connectTimer = null;
      connect();
    }, RECONNECT_DELAY);
  }

  async function connect() {
    if (connecting) {
      return;
    }
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
      return;
    }

    connecting = true;
    let ws = null;
    try {
      try {
        await ensureInstanceId();
        bridgeInfo = await discoverBridge();
      } catch (error) {
        log("bridge discovery failed", error);
        storageSet("BeardieNowPlayingLastError", String(error));
        if (connectTimer) {
          clearTimeout(connectTimer);
        }
        connectTimer = setTimeout(() => {
          connectTimer = null;
          connect();
        }, NATIVE_RETRY_DELAY);
        return;
      }

      storageSet("BeardieNowPlayingLastError", "");
      storageSet("BeardieNowPlayingBridgePort", bridgeInfo.port);

      const url = `ws://${HOST}:${bridgeInfo.port}${PATH}?token=${encodeURIComponent(bridgeInfo.token)}`;
      try {
        ws = new WebSocket(url);
      } catch (error) {
        log("WebSocket construction failed", error);
        scheduleReconnect();
        return;
      }

      socket = ws;

      ws.onopen = function () {
        if (socket !== ws) {
          return;
        }
        log("bridge connected");
        storageSet("BeardieNowPlayingStatus", "connected");
        sendJSON({
          type: "hello",
          protocolVersion: PROTOCOL_VERSION,
          instanceId: instanceId,
          browser: bridgeInfo.bundleId || bridgeInfo.browser || "unknown",
          bundleId: bridgeInfo.bundleId || null,
          processIdentifier: bridgeInfo.pid || null
        });
        refreshAndSendState();
      };

      ws.onmessage = handleServerMessage;

      ws.onerror = function () {
        log("bridge socket error");
        storageSet("BeardieNowPlayingStatus", "error");
      };

      ws.onclose = function () {
        if (socket === ws) {
          socket = null;
        }
        storageSet("BeardieNowPlayingStatus", "closed");
        scheduleReconnect();
      };
    } finally {
      connecting = false;
    }
  }

  function registerSafariMediaSessionShim() {
    const manifest = api.runtime.getManifest ? api.runtime.getManifest() : null;
    if (!manifest || manifest.manifest_version !== 2) {
      return;
    }
    if (!api.scripting || typeof api.scripting.registerContentScripts !== "function") {
      return;
    }

    const registration = {
      id: "beardie-mediasession-main",
      matches: ["<all_urls>"],
      js: ["shared/mediasession-main.js"],
      runAt: "document_start",
      allFrames: true,
      world: "MAIN",
      persistAcrossSessions: true
    };

    try {
      const result = api.scripting.registerContentScripts([registration]);
      if (result && typeof result.catch === "function") {
        result.catch(function () {
          // Already registered or unsupported by this Safari build.
        });
      }
    } catch (_) {
      // Safari without MAIN-world support keeps the MediaRemote fallback.
    }
  }

  function registerListeners() {
    api.runtime.onMessage.addListener(function (message, sender, _sendResponse) {
      if (!message || message.type !== "mediaState" || !sender.tab) {
        return false;
      }
      updateFrameMedia(
        sender.tab.id,
        frameKey(sender, message),
        message.state || null
      );
      // A content script can outlive the background page or service worker.
      // Any message means the extension is active again, so reconnect instead
      // of waiting for the next alarm or reconnect timer.
      if (!socket || socket.readyState !== WebSocket.OPEN) {
        connect();
      }
      scheduleState();
      return false;
    });

    if (api.tabs.onUpdated) {
      api.tabs.onUpdated.addListener(function (tabId, changeInfo) {
        if (changeInfo && (changeInfo.url || changeInfo.status === "loading")) {
          clearTabMedia(tabId);
          // One-shot refresh after navigation. This is event-driven: no
          // periodic polling and no timer per second.
          setTimeout(function () {
            requestTabState(tabId);
          }, 300);
        }
        if (changeInfo && (changeInfo.status || changeInfo.title || changeInfo.url)) {
          scheduleState();
        }
      });
    }
    if (api.tabs.onRemoved) {
      api.tabs.onRemoved.addListener(function (tabId) {
        clearTabMedia(tabId);
        scheduleState();
      });
    }
    if (api.tabs.onActivated) {
      api.tabs.onActivated.addListener(function (activeInfo) {
        scheduleState();
        if (activeInfo && typeof activeInfo.tabId === "number") {
          requestTabState(activeInfo.tabId);
        }
      });
    }
    if (api.windows && api.windows.onFocusChanged) {
      api.windows.onFocusChanged.addListener(scheduleState);
    }

    // Chrome MV3 service workers are non-persistent and need one wake-up
    // mechanism. Safari uses a persistent background page and gets no alarms.
    const manifest = api.runtime.getManifest ? api.runtime.getManifest() : null;
    const usesServiceWorker = Boolean(manifest && manifest.background && manifest.background.service_worker);
    if (usesServiceWorker && api.alarms) {
      try {
        api.alarms.create("beardie-nowplaying-keepalive", { periodInMinutes: 0.5 });
        api.alarms.onAlarm.addListener(function (alarm) {
          if (alarm && alarm.name === "beardie-nowplaying-keepalive") {
            sendState();
            if (!socket || socket.readyState !== WebSocket.OPEN) {
              connect();
            }
          }
        });
      } catch (_) {
        // Alarms are optional; a persistent background does not need them.
      }
    }
  }

  refreshTabMedia();
  registerSafariMediaSessionShim();
  registerListeners();
  connect();
})();
