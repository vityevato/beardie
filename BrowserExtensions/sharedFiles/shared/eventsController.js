var BSEventResponder = {
    listenRequest: function(callback) { // analogue of chrome.extension.onRequest.addListener

        document.addEventListener("BSEventClient-query", function(event) {
            var node = event.target;
            if (!node || node.nodeType != Node.TEXT_NODE)
                return;

            var doc = node.ownerDocument;
            callback(event.detail, doc, function(response) {

                var event = new CustomEvent("BSEventClient-response", {
                    detail: response,
                    "bubbles": true,
                    "cancelable": false
                });
                return node.dispatchEvent(event);
            });
        }, false, true);

        var event = new CustomEvent("BSEventController-installed", {
            "bubbles": true,
            "cancelable": false
        });
        document.dispatchEvent(event);
    },

    // callback function example
    callback: function(request, sender, callback) {

        return callback({ "result": true });
    }
}

BSEventResponder.listenRequest(function(request, sender, callback) {

    // BSLog("(Beardie) BSEventResponder get request.");
    // BSLog(request);
    // BSLog(sender);

    switch (request.name) {
        case "injectScript":
            try {
                window.eval(request.code);
                return callback({ "result": true });
            } catch (error) {
                BSError("(BeardedSpace) Error injecting script through eval in eventsController.js:" + error);
                return callback({ "result": false });
            }
            break;
        case "accept":
            if (BSAccepters && BSAccepters.evaluate()) {
                return callback({ "strategyName": BSAccepters.strategyName });
            }
            return callback({ "result": false });
        case "checkAccept":
            return callback({ "result": BSAccepters && BSAccepters.strategyAccepterFunc && BSAccepters.strategyAccepterFunc() });
        case "checkStrategy":
            return callback({ result: (typeof(BSStrategy) !== "undefined") });
        case "command":
            return callback(BSUtils.strategyCommand(BSStrategy, request.args));
        default:
            return callback({ "result": false });
    }
});
