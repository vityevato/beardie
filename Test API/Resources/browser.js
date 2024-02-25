const api = (typeof chrome !== "undefined" && chrome) ? chrome : browser;

export default {

    everyTabs: function (callback) {
        if (typeof callback !== "function") {
            return;
        }

        (async function () {
            let tabs = await api.tabs.query({});
            if (!(tabs && tabs.length)) {
                return;
            }
            tabs.every(tab => {
                if (tab.id && tab.id != api.tabs.TAB_ID_NONE) {
                    return callback(tab);
                }
                return true;
            });

        })();
    },

    isFrontmostTab: async function (tab) {
        if (!(tab && tab.id)) {
            return false;
        }

        let activeTab = this.getActiveTab();
        return(activeTab && activeTab.id && activeTab.id === tab.id);
    },

    getActiveTab: async function (forWindowId = null) {
        let query = forWindowId == null ? {
            active: true,
            lastFocusedWindow: true
        } : {
            active: true,
            windowId: forWindowWhereTab.windowId
        };
        let [tab] = await api.tabs.query(query);
        return tab;
    },

    setActiveTab: async function (tab, raiseWindow = true) {
        if (raiseWindow) {
            await api.windows.update(tab.windowId, {focused: true});
        }
        await api.tabs.update(tab.id, {active: true});
    },

    isStandalone: function () {
        return !(window.matchMedia('(display-mode: browser)').matches);
    },

    executeScript: async (script, tab) => {
        if (!tab || !tab.id || script.length === 0) {
            return;
        }

        const functionToInject = (script) => {
            const scriptTag = document.createElement('script');
            scriptTag.setAttribute('type', 'text/javascript');
            scriptTag.textContent = script;

            const parent = document.head || document.documentElement;
            parent.appendChild(scriptTag);

            if (scriptTag.parentNode) {
                scriptTag.parentNode.removeChild(scriptTag);
            }
        };

        try {
            await chrome.scripting.executeScript({
                target: tab,
                func: functionToInject,
                injectImmediately: true,
                world: 'MAIN', // ISOLATED doesn't allow to execute code inline
                args: [script]
            });
        } catch (e) {
            logger.debug(`Error on executeScript in the tab ${tab.id}:`, chrome.runtime.lastError, e);
        }
    }

};
