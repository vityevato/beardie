BSLog("(Beardie) Start content.js");

var mainScript = function() {
    BSLog("(Beardie) Start injection script");

    if (window != window.top) {
        BSLog(window.top);
        BSLog("(Beardie) Injection script stopped, because iframe");
        return;
    }
    BSLog("(Beardie) Injection script running on top window");

    var checkInjectAlready = document.querySelector('#X_Beardie_InjectAlready');
    if (checkInjectAlready != null) {
        BSLog("(Beardie) Script already injected!");
         return;
    }
 
    var injected = document.createElement("div");
    injected.setAttribute("id", "X_Beardie_InjectAlready");
    injected.setAttribute("style", "display: none");
    (document.body || document.documentElement).appendChild(injected);

    // Test webPage for CSP
    var noCSP = false;
    let injectContent = "eval(\"var injected = document.createElement(\\\"div\\\");injected.setAttribute(\\\"id\\\", \\\"BSCheckCSPDiv\\\"); injected.setAttribute(\\\"style\\\", \\\"display: none\\\"); (document.body || document.documentElement).appendChild(injected);\");";
    BSEventClient.sendRequest({"name": "injectScript", "code": injectContent}, (response) => {
        if(response.result) {
            let checkInjected = document.querySelector('#BSCheckCSPDiv');
            noCSP = (checkInjected != null);
            try {
                checkInjected.parentNode.removeChild(checkInjected);
            } catch (ex) {}
            }
        if (!noCSP) {
            console.warn("(Beardie) Message for Developers: Page under CSP. You have access to DOM objects only!");
        }

        // START
        BSLog("Beardie Script Start.");
        BSUtils.sendMessageToGlobal("logLevel");

    });

    var bundleId = null;
    var socket = null;
    var strategyName = null;
    var strategy = null;


    var state = {
        current: { val: 0, str: "init" },
        init: { val: 0, str: "init" },
        reconnecting: { val: 1, str: "reconnecting" },
        accepted: { val: 2, str: "accepted" },
        strategyRequested: { val: 3, str: "strategyRequested" },
        ready: { val: 4, str: "ready" },
        inCommand: { val: 5, str: "inCommand" },
        connecting: { val: 6, str: "connecting" },
        disconnected: { val: 7, str: "disconnected" },
        set: function(st) {
            this.current = st;
            if (this.inCommandIntervalId) {
                clearInterval(this.inCommandIntervalId);
                this.inCommandIntervalId = null;
            }
            if (st.val == state.inCommand.val) {
                    BSLog("(Beardie) inCommand timeout ran");
                this.inCommandIntervalId = setInterval(() => {
                    BSLog("(Beardie) inCommand timeout reached");
                    state.set(state.ready);
                }, 2000);
            }
            BSLog("(Beardie) Set State to \"" + this.current.str + "\"");
        },
        inCommandIntervalId: null
    }

    var bsParameters = {
        'URL': window.location.href,
        'title': window.document.title == "" ? window.location.href : window.document.title
    };


    // Handle message from Global Extension Page
    var handleMessage = function(event) {
        BSLog(event.name);
        BSLog(event.message);
        if (event.name === 'serverIsAlive'
            || event.name === 'reconnect') {

            if (handleMessage.intervalId) {
                clearInterval(handleMessage.intervalId);
                BSLog("Cleared interval: " + handleMessage.intervalId);
                handleMessage.intervalId = null
            }
            if (event.message["result"]) {
                if (event.name === 'reconnect') {
                    reconnect(event);
                }
                else {
                    serverIsAlive(event);
                }
                return;
            }
            else {
                handleMessage.intervalId = setInterval(function () {
                    BSUtils.sendMessageToGlobal(event.name);
                },
                    10000);
            }
        }
        if (event.name === 'logLevel') {
            BSUtils.setLogLevel(event.message.result.debug);
            BSEventClient.sendRequest({ "name": "logLevel", "debug": event.message.result.debug });
            if (state.current.val == state.init.val) {

                //GET ACCEPTERS AFTER GETTING LOGLEVEL
                BSUtils.sendMessageToGlobal("accepters");
            }
        }
        switch (state.current.val) {
            case state.init.val:
            case state.reconnecting.val:
                if (event.name === 'accepters') {
                    accept(event.message);
                }
                break;
            case state.connecting.val:
                if (event.name === 'bundleId') {
                    bundleId = event.message;
                    _send(event.message);
                }
                break;
            case state.accepted.val:
                if (event.name === 'port') {
                    connect(event.message["result"]);
                }
                break;
            case state.inCommand.val:
                switch (event.name) {
                    case 'bundleId':
                        bundleId = event.message;
                    case 'frontmost':
                    case 'activate':
                    case 'hide':
                    case "isActivated":
                        _send(event.message);
                        state.set(state.ready);
                        break;
                    default:
                }
                break;
            default:
        }
    };

    var _clean = function() {
        socket = null;
        strategyName = null;
        strategyAccepterFunc = null;
        strategy = null;
        state.set(state.init);
    }

    var _send = function(obj) {
        try {

            if (socket) {
                socket.send(JSON.stringify(obj));
                BSLog("(Beardie) Socket send:" + JSON.stringify(obj));
            }
        } catch (ex) {
            logError(ex);
            socket.close();
        }
    };
    var _sendOk = function() { _send({ 'result': true }) };

    var logError = function(ex) {
        if (typeof console !== 'undefined' && console.error) {
            BSError('Error in BeardedSpice script');
            BSError(ex);
        }
    };

    var accept = function(accepters) {
        if (!accepters ||
            !(state.current.val == state.init.val ||
                state.current.val == state.reconnecting.val)) {
            return;
        }

        BSLog("(Beardie) Accepters run.");

        try {
            var code = accepters.bsJsFunctions +
                "bsJsFunctions();" +
                "var strategies = " + accepters.strategies + ";" +
                "Object.getOwnPropertyNames(strategies).find(function(val) {" +
                "eval(strategies[val]);" +
                "if (bsAccepter()) {" +
                "strategyName = val;" +
                "strategyAccepterFunc = bsAccepter;" +
                "BSLog(\"(Beardie) Strategy found: \" + strategyName + \".\");" +
                "return true;" +
                "}" +
                "return false;" +
                "});";

            if (noCSP) {
                let injectCode = BSUtils.injectAcceptersScript(code, bsParameters);
                BSEventClient.sendRequest({ "name": "injectScript", "code": injectCode },
                    (response) => {
                        BSLog("(Beardie) Accepters run: without CSP");
                        if (response.result) {
                            BSEventClient.sendRequest({ "name": "accept" }, response => {
                                BSLog("(Beardie) Accepters were ran on web page");

                                strategyName = response.strategyName;
                                if (strategyName) {
                                    state.set(state.accepted);
                                    BSUtils.sendMessageToGlobal("port");
                                } else {
                                    state.set(state.init);
                                }
                            });
                        }
                    });
            } else {
                eval(code);
                BSLog("(Beardie) Accepters run: on CSP");
                if (strategyName) {
                    state.set(state.accepted);
                    BSUtils.sendMessageToGlobal("port");
                } else {
                    state.set(state.init);
                }
            }

        } catch (ex) {
            logError(ex);
        }

    };

    var serverIsAlive = function(event) {
        BSLog("(Beardie) Attempt to connecting on new port.");
        state.set(state.accepted);
        BSUtils.sendMessageToGlobal("port");
    };

    var reconnect = function(event) {

        if (state.current.val === state.reconnecting.val) {
            return;
        }

        BSLog("(Beardie) Attempt to reconnecting.");

        state.set(state.reconnecting);
        if (socket) {
            socket.close();
        }
        _clean();

        BSUtils.sendMessageToGlobal("accepters");
    };

    var connect = function(port) {

        if (state.current.val !== state.accepted.val) {
            return;
        }

        var onSocketDisconnet = function(event) {
            BSLog('(Beardie) onSocketDisconnet');

            if (state.current.val === state.reconnecting.val) {
                return;
            }
            state.set(state.disconnected);

            //sending request to extension
            BSUtils.sendMessageToGlobal('serverIsAlive');
        };

        if (port == 0) {
            BSLog("(Beardie) Port not specified.");
            onSocketDisconnet();
            return;
        }

        state.set(state.connecting);

        // Create WebSocket connection.
        var url = 'wss://localhost:' + port;
        BSLog("(Beardie) Try connect to '" + url + "'");

        socket = new WebSocket(url);

        // Connection opened
        socket.addEventListener('open', function(event) {
            BSLog("(Beardie) Socket open.");
        });

        socket.addEventListener('close', onSocketDisconnet);

        // Listen for messages from Beardie Control Server
        socket.addEventListener('message', function(event) {
            BSLog('(Beardie) Message from server ', event.data);
            BSLog('(Beardie) State: ' + state.current.str);
                                
            switch (state.current.val) {
                case state.connecting.val:
                    if (event.data == "bundleId") {
                        if (bundleId != null) { // if we hold localy bundleId, return it
                            _send(bundleId);
                            break;
                        }
                        //sending request to extension
                        BSUtils.sendMessageToGlobal(event.data);
                        break;
                    }
                    if (event.data == "standalone") {
                        _send({"standalone": BSUtils.isStandalone()});
                        break;    
                    }
                    if (event.data == "ready") {
                        _send({ 'strategy': strategyName });
                        state.set(state.strategyRequested);
                    }
                    break;
                case state.strategyRequested.val:
                    if (noCSP) {
                        BSEventClient.sendRequest({ "name": "injectScript", "code": event.data }, response => {
                            if (response.result) {
                                BSEventClient.sendRequest({ "name": "checkStrategy" }, function (response) {
                                    if (response.result) {
                                        state.set(state.ready);
                                        _sendOk();
                                    }
                                });
                            }
                        });
                    } else {

                        try {
                            eval('var ' + event.data + ';');
                            if (BSStrategy) {
                                BSLog('(Beardie) Strategy obtained.');
                                BSLog(BSStrategy);
                                strategy = BSStrategy;
                                state.set(state.ready);
                                _sendOk();
                            }
                        } catch (ex) {
                            logError(ex);
                            _send({ 'result': false });
                        }
                    }
                    break;

                //Main Command Loop
                case state.ready.val:
                    try {
                        try {
                            var obj = JSON.parse(event.data);
                            if (obj.realBundleId != null) {
                                bundleId = { "result": obj.realBundleId};
                                BSLog("(Beardie) Real Bundle ID set on: %s", bundleId);
                                _sendOk();
                                break;
                            }
                        } catch (ex) { 
                            BSLog("(Beardie) try simple command");
                        }
                        state.set(state.inCommand);
                        switch (event.data) {
                            case "bundleId":
                                if (bundleId != null) { // if we hold localy bundleId, return it 
                                    _send(bundleId);
                                    state.set(state.ready);
                                    break;
                                }
                            case "frontmost":
                            case "activate":
                            case "hide":
                            case "isActivated":
                                //sending request to extension
                                BSUtils.sendMessageToGlobal(event.data);
                                break;
                            default:
                                if (noCSP) {
                                    BSEventClient.sendRequest({ "name": "command", "args": event.data }, function(response) {
                                        _send(response);
                                        state.set(state.ready);
                                    });
                                } else {
                                    _send(BSUtils.strategyCommand(strategy, event.data));
                                    state.set(state.ready);
                                }
                        }
                    } catch (ex) {
                        logError(ex);
                        _send({ 'result': false });
                    }
                    break;
                default:
            }
        });
    };

    var onUrlChangedBy = function(event) {
        BSLog("(Beardie) onUrlChangedBy");

        bsParameters.URL = window.location.href;

        if (strategyName) {
            //strategy was loaded
            //check strategy validity
            if (noCSP) {
                BSEventClient.sendRequest({ "name": "checkAccept" }, function(response) {
                    BSLog("(Beardie) checkAccept run: %o", response);

                    if (response["result"]) {
                        //do nothing
                        return;
                    }
                    reconnect();
                });
                return;
            } else {
                if (strategyAccepterFunc()) {
                    //do nothing
                    return;
                }
            }
        }
        reconnect();
    }

    var installAdditionalEventListeners = function() {
        window.addEventListener("popstate", function(event) {
            BSLog("(Beardie) onPopstate.");
            setTimeout(function() {
                if (bsParameters.URL != window.location.href) {
                    return onUrlChangedBy(event);
                }
            }, 1);
        }, true);
    
        window.addEventListener("click", function(event) {
            BSLog("(Beardie) onClick");
            if (state.current == state.ready.val) {
                if (noCSP) {
                    BSEventClient.sendRequest({ "name": "command", "args": "onClick" }, function(response) {});
                } else {
                    BSUtils.strategyCommand(strategy, "onClick");
                }
                }
            setTimeout(function () {
                if (bsParameters.URL != window.location.href) {
                    return onUrlChangedBy(event);
                }
            }, 1);
        }, true);
    };

    installAdditionalEventListeners();

    BSLog("Beardie Script Injected.");

    BSUtils.handleMessageFromGlobal(handleMessage);

};

var started = false;

if (document.querySelector('#X_Beardie_EventController_Installed') != null) {
    BSLog("(Beardie) 'EventController installed' detected");
    mainScript();
    started = true;
}


document.addEventListener("BSEventController-installed", () => {
    if (started == false) {
        BSLog("(Beardie) start main script from event 'BSEventController-installed'");
        mainScript();
        started = true;
    }
}
, false, true);

