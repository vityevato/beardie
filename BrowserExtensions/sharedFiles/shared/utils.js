(function(){
    if (typeof BSUtils !== "undefined" && BSUtils) {
        return;
    }

    if (typeof BSConstants !== "undefined" && (BSConstants.BS_B_BUID_CONFIG != "Debug")) {
        //PREVENTS LOG OUTPUT
        BSLog = function () { };
    }
    else {
        BSLog = function () {
            console.log.apply(console, [`[${new Date().toISOString().replace("T", " ").replace(/\..+/, "")}]`+ [].shift.call(arguments), ...arguments])
        };
    }
    BSError = function () {
        console.error.apply(console, [`[${new Date().toISOString().replace("T", " ").replace(/\..+/, "")}]`+ [].shift.call(arguments), ...arguments])
    };
    BSWarn = function () {
        console.warn.apply(console, [`[${new Date().toISOString().replace("T", " ").replace(/\..+/, "")}]`+ [].shift.call(arguments), ...arguments])
    };
    BSInfo = function () {
        console.info.apply(console, [`[${new Date().toISOString().replace("T", " ").replace(/\..+/, "")}]`+ [].shift.call(arguments), ...arguments])
    };
})();

var BSUtils = {

    checkThatTabIsReal: function(tab) {
        if (typeof safari !== "undefined" && safari && tab.page) {
            return true;
        } else if (typeof chrome !== "undefined" && chrome && tab.id && tab.id != chrome.tabs.TAB_ID_NONE) {
            return true;
        }
        return false;
    },

    forEachTabs: function(callback) {
        if (typeof callback !== "function")
            return;

        if (typeof safari !== "undefined" && safari && safari.application) {
            safari.application.browserWindows.forEach(function(val) {
                val.tabs.forEach(function(tab) {
                    if (tab.url && tab.url.length && tab.page) {
                        callback(tab);
                    }
                });
            });

        } else if (typeof chrome !== "undefined" && chrome && chrome.tabs) {
            chrome.tabs.query({}, function(result) {
                if (result && result.length) {
                    result.forEach(function(tab) {
                        if (tab.id && tab.id != chrome.tabs.TAB_ID_NONE)
                            callback(tab);
                    });
                }
            });
        }
    },

    frontmostTab: function (tab, callback) {
        if (! tab) {
            if (callback) callback(false);
            return;
        }
        this.getActiveTab(function (activeTab ) {
            if (! activeTab) {
                if (callback) callback(false);
                return;
            }
            if (typeof safari !== "undefined" && safari) {
                if (callback) callback(activeTab === tab);
            } else if (typeof chrome !== "undefined" && chrome && chrome.tabs) {
                if (callback) callback(activeTab.id && tab.id && activeTab.id === tab.id);
            }
        });
    },

    getActiveTab: function(callback, forWindowWhereTab) {
        BSLog("(Beardie) getActiveTab.");
        if (typeof safari !== "undefined" && safari && safari.application) {

            var tab = forWindowWhereTab ? forWindowWhereTab.browserWindow.activeTab : safari.application.activeBrowserWindow.activeTab;
            if (callback) callback(tab);
        } else if (typeof chrome !== "undefined" && chrome && chrome.tabs) {
            var query = forWindowWhereTab != undefined ? { active: true, windowId: forWindowWhereTab.windowId } : { active: true, lastFocusedWindow: true };
            chrome.tabs.query(query, function(result) {
                var tab;
                if (result && result.length)
                    tab = result[0];
                callback(tab);
            });
        }
    },

    setActiveTab: function(tab, withWindow, callback) {
        BSLog("(Beardie) setActiveTab withWindow: %s, for tab %o", withWindow, tab);
        if (typeof safari !== "undefined" && safari) {
            if (withWindow) tab.browserWindow.activate();
            tab.activate();
            if (callback) callback();
        } else if (typeof chrome !== "undefined" && chrome && chrome.windows) {
            if (withWindow) chrome.windows.update(tab.windowId, { focused: true });
            chrome.tabs.update(tab.id, { active: true }, function(tab) {
                if (callback) callback();
            });
        }
    },

    storageGet: function(name, callback) {
        if (typeof safari !== "undefined" && safari && safari.extension && safari.extension.settings) {
            var value = safari.extension.settings[name];
            BSLog("(Beardie) storageGet name: %s, value: %o.",  name, value);
            if (callback) callback(value);
        } else if (typeof chrome !== "undefined" && chrome && chrome.storage) {
            chrome.storage.local.get(name, function(items) {
                BSLog("(Beardie) storageGet name: %s, value: %o.",  name, items);
                if (callback) callback(items[name]);
            });
        }
    },

    storageSet: function(name, value, callback) {
        if (typeof safari !== "undefined" && safari && safari.extension && safari.extension.settings) {
            BSLog("(Beardie) storageSet name: %s value: %o.", name, value);
            safari.extension.settings[name] = value;
            if (callback) callback();
        } else if (typeof chrome !== "undefined" && chrome && chrome.storage) {
            var val = {};
            val[name] = value;
            BSLog("(Beardie) storageSet dict: %O", val);
            chrome.storage.local.set( val, callback);
        }
    },

    isStandalone: function(){
        if (typeof safari !== "undefined" && safari ) {
            return (window.navigator.standalone === true);
        } else if (typeof chrome !== "undefined" && chrome) {
            return !(window.matchMedia('(display-mode: browser)').matches);
        }
    },

    sendMessageToGlobal: function(name, message) {
        BSLog("(Beardie) sendMessageToGlobal name: %s, message: %o", name, message);
        if (typeof safari !== "undefined" && safari && safari.extension) {
            safari.extension.dispatchMessage(name, message);
        } else if (typeof chrome !== "undefined" && chrome && chrome.runtime) {
            chrome.runtime.sendMessage({ "name": name, "message": message });
        }
    },

    handleMessageFromGlobal: function(callback) {

        if (typeof safari !== "undefined" && safari && safari.self) {
            safari.self.addEventListener("message", callback);
        } else if (typeof chrome !== "undefined" && chrome && chrome.runtime) {
            chrome.runtime.onMessage.addListener(
                function(request, sender) {
                    if (!sender.tab) {
                        Object.assign(request, sender);
                        callback(request);
                    }
                    return false;
                });
        }
    },

    sendMessageToTab: function(tab, name, message) {

        BSLog("(Beardie) sendMessageToTab name: %s, message: %o", name, message);
        if (typeof safari !== "undefined" && tab && tab.page) {
            tab.page.dispatchMessage(name, message);
        } else if (typeof chrome !== "undefined" && chrome && chrome.tabs && tab && tab.id) {
            chrome.tabs.sendMessage(tab.id, { "name": name, "message": message });
        }
    },

    handleMessageFromTabs: function(callback) {

        if (typeof safari !== "undefined" && safari && safari.application) {
            safari.application.addEventListener("message", callback, false);
        } else if (typeof chrome !== "undefined" && chrome && chrome.runtime) {
            chrome.runtime.onMessage.addListener(
                function(request, sender) {
                    if (sender.tab) {
                        Object.assign(request, sender);
                        request.target = request.tab;
                        callback(request);
                    }
                    return false;
                });
        }
    },

    injectExtScript: function(script, className = null) {

        var injected = document.createElement("script");
        injected.setAttribute("type", "text/javascript");
        var src = "";
        if (typeof safari !== "undefined" && safari && safari.extension) {
            src = safari.extension.baseURI + script;
        } else if (typeof chrome !== "undefined" && chrome && chrome.extension) {
            src = chrome.extension.getURL(script);
        }
        injected.setAttribute("src", src);
        injected.setAttribute("class", className || "x_Beardie_InjectScript");
        try {
            (document.head || document.documentElement).appendChild(injected);
            BSLog('(Beardie) injectExtScript: ' + src);
        } catch (error) {
            BSInfo('(Beardie) injectExtScript: ' + src + 'error:' + error);
        }
    },

    injectAcceptersScript: function(code, parameters) {
        return "window.bsParameters = " + JSON.stringify(parameters) + ";" +
               "window.BSAccepters = { \
                    strategyName: null,\
                    strategyAccepterFunc: null,\
                    evaluate: function () {\
                        var strategyName = null;\
                        var strategyAccepterFunc = null;"
                    + code +
                       "this.strategyName = strategyName;\
                        this.strategyAccepterFunc = strategyAccepterFunc;\
                        return strategyName && (strategyName.length > 0);\
                    }\
                };\
            ";
    },

    strategyCommand: function(strategy, command) {
        BSLog('(Beardie) strategyCommand:');
        BSLog(strategy);
        BSLog(command);

        var okResult = { 'result': true };
        try {

            if (strategy) {

                BSLog('(Beardie) Strategy command obtained.');

                if (command == 'title') {
                    var title = window.document.title == "" ? window.location.href : window.document.title;
                    return { 'result': title };
                } else if (command == 'toggle') {
                    strategy.toggle();
                    return okResult;
                } else if (command == 'pause') {
                    strategy.pause();
                    return okResult;
                } else if (command == 'next') {
                    strategy.next();
                    return okResult;
                } else if (command == 'previous') {
                    strategy.previous();
                    return okResult;
                } else if (command == 'favorite') {
                    strategy.favorite();
                    return okResult;
                } else if (command == 'trackInfo') {
                    return strategy.trackInfo();
                } else if (command == 'isPlaying') {
                    return { 'result': strategy.isPlaying() };
                } else if (command == 'onClick') {
                    if (strategy.onClick) strategy.onClick();
                    return okResult;
                } else {
                    BSError('(Beardie) Strategy command not found.');
                    return { 'result': false };
                }
            }
        } catch (ex) {
            BSInfo('(Beardie) command exception:' + ex);
            return { 'result': false };
        }

    }
};
