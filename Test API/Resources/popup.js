import Beardie from "./browser.js";

console.log("Hello World!", browser);

async function clickFunc()
{
    console.warn ("TUTA", browser);
    debugger;
    let activeTab = await Beardie.getActiveTab();
    Beardie.everyTabs ( async tab => {
        if (tab.windowId != activeTab.windowId) 
        {
            await Beardie.setActiveTab (tab);
            return false;
        }
        return true;
    });
}

window.addEventListener("load", (ev) => {
    console.warn("TIPA", browser);
    let btn = document.getElementById("button");
    btn.addEventListener("click", clickFunc);
});
