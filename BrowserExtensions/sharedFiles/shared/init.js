var checkInjectAlready = document.querySelector('#X_Beardie_InjectAlready');
if (checkInjectAlready != null) {
    BSLog("(BeardedSpice eventsController) Script already injected!");
}
else {
    BSUtils.injectExtScript("constants.js");
    BSUtils.injectExtScript("shared/utils.js");
    BSUtils.injectExtScript("shared/eventsController.js", "x_Beardie_EventController");
}

