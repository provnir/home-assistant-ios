import Foundation

/// The script Khala injects into the web frontend (document start, main frame) so the native header can stand in
/// for the frontend's own. Checked against home-assistant/frontend 20260930.4; everything it relies on is looked
/// up at run time, and every failure leaves the frontend as it was (its own header showing under ours) and is
/// reported once as a `problem` message, which the app logs.
///
/// What it does, and the frontend code each step rests on:
/// 1. **Room for the native header.** Sets `--app-safe-area-inset-top` on the document to the status bar plus
///    `headerInset`. That variable is the frontend's own hook for an app's insets
///    (`src/resources/theme/main.globals.ts`: `--safe-area-inset-top: var(--app-safe-area-inset-top,
///    env(safe-area-inset-top))`), and every page, dialog and iframe panel lays out from it, so nothing the
///    frontend draws starts under our header — while the web view itself still runs edge to edge beneath it.
/// 2. **No frontend header on dashboards.** `hui-root` (`src/panels/lovelace/hui-root.ts`, also behind the Home and
///    Energy panels) draws the dashboard toolbar: menu button or back arrow, title or view tabs, action buttons.
///    The script adds one stylesheet to its shadow root that hides `.header` and zeroes `--header-height` (which
///    `hui-view-container` pads by), outside edit mode only — the edit-mode toolbar is an editing tool, not app
///    chrome. It only switches on (`khala-native-header` attribute) once the views could be read, and switches
///    back off if the header is still visible or the content didn't move down by the inset.
/// 3. **Report.** Posts `{type: "state", state}` to `messageHandlerName` whenever it changes: the path, the open
///    dialog (`history.state.dialog`, kept by `src/dialogs/make-dialog-manager.ts`), the dashboard's selectable
///    views from `hui-root.lovelace.config.views` (the frontend's resolved config, so strategy dashboards such as an
///    auto-generated Overview have views too — `lovelace/config` returns none for them) filtered like its tab bar
///    (no sub-views, `visible` honoured), the current view, sub-view/back-button/edit state, the toolbar's
///    action items, and — on pages `hui-root` doesn't draw (`/config/...`) — whether the page shows the frontend's
///    own back arrow (`pageBack`; its top-level pages show the menu button there instead).
/// 4. **Drive.** `window.__khala.back()` uses the frontend's own back paths: a dialog closes through
///    `history.back()` (how the dialog manager expects to be closed), a sub-view or sub-page through a click on
///    the frontend's own back arrow (so `back_path` and unsaved-changes guards still apply). `perform(id, title)`
///    runs a toolbar action through the frontend's handler. Navigation itself uses the external bus `navigate`
///    command, not this script.
/// 5. **Pages that aren't dashboards.** Settings pages and the History / Logbook / To-do / Media panels draw their
///    own chrome with one of three layouts: `hass-subpage` and `hass-tabs-subpage` (`src/layouts/`, the latter
///    also inside `hass-tabs-subpage-data-table`) and `ha-top-app-bar-fixed` (`src/components/`, plus its two-pane
///    subclass). The script tracks their instances (same `updated` patch as `hui-root`), reads the one on screen —
///    title (`header` / the `header` or `title` slot), back arrow vs menu button, tabs (`hass-tabs-subpage.tabs`
///    filtered like `_getTabs` does), the search field in its header slot (`ha-input-search`), its "+" FAB (the
///    `fab` slot, only when its icon is `mdiPlus`) and its toolbar tools (the `toolbar-icon` / `actionItems` slot:
///    buttons and `ha-dropdown` items) — and hides ("lifts") the toolbar row, the tab bar and the lifted FAB with
///    one stylesheet in its shadow root, keeping the toolbar's safe-area padding as the spacer under Khala's
///    header. The top inset then grows by the header's title (and search) block: `KhalaPageHeader.height`.
///    `search(text)` types into the page's own field (value + `input` event, what its `@input` handler reads),
///    `tab(path)` clicks the page's own (hidden) tab link (its `_tabClicked` navigates with `replace`), and
///    `perform` runs a tool or the FAB through the page's own handlers. Not lifted (the frontend's toolbar stays,
///    under Khala's slim header): a page in selection mode (its `toolbar` slot is taken), an editor whose
///    navigation icon is a close button, a header or tool the script can't read, or a lift whose result doesn't
///    check out (toolbar still showing, content not below the header) — each logged once as a `problem`.
enum KhalaFrontendScript {
    /// The `WKScriptMessageHandler` name the script posts to.
    static let messageHandlerName = "khalaShell"

    /// Height of the native header's row below the status bar: 9 pt above the 44 pt glass buttons, 9 below
    /// (the shell's pinned menu button sits at 9 pt, `KhalaShellView.menuButtonInset`).
    static let headerInset: Double = 9 + 44 + 9

    /// Room a lifted page leaves at its bottom for Khala's glass sub-tabs: the 62 pt bar, 8 pt under it, 8 pt over.
    static let tabBarInset: Double = 62 + 8 + 8

    /// JavaScript that calls the script's `back()`; the result is "dialog", "frontend" or "none".
    static let backCall = "window.__khala ? window.__khala.back() : 'none'"

    /// JavaScript that asks the script for a fresh report.
    static let reportCall = "window.__khala && window.__khala.report()"

    /// JavaScript that performs one of the dashboard's toolbar actions; the result is true when it ran.
    static func performCall(actionId: String, title: String) -> String {
        "window.__khala ? window.__khala.perform(\(literal(actionId)), \(literal(title))) : false"
    }

    /// JavaScript that types `text` into the lifted page's own search field; the result is true when it did.
    static func searchCall(_ text: String) -> String {
        "window.__khala ? window.__khala.search(\(literal(text))) : false"
    }

    /// JavaScript that opens one of the lifted page's tabs through the page's own tab link; the result is true
    /// when it did (false: the app navigates itself).
    static func tabCall(path: String) -> String {
        "window.__khala ? window.__khala.tab(\(literal(path))) : false"
    }

    /// A JSON string literal, safe to splice into JavaScript.
    static func literal(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let array = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(array.dropFirst().dropLast())
    }

    static func source(headerInset: Double = headerInset) -> String {
        let inset = String(format: "%.0f", headerInset)
        let title = String(format: "%.0f", KhalaPageHeader.titleHeight)
        let search = String(format: "%.0f", KhalaPageHeader.searchHeight)
        let tabBar = String(format: "%.0f", tabBarInset)
        return #"""
        (() => {
          if (window.__khala) { return; }
          const HANDLER = "\#(messageHandlerName)";
          const INSET = \#(inset);
          const TITLE_BLOCK = \#(title);
          const SEARCH_BLOCK = \#(search);
          const TAB_BAR = \#(tabBar);
          const ATTRIBUTE = "khala-native-header";
          const PAGE_ATTRIBUTE = "khala-page-chrome";
          const TABS_ATTRIBUTE = "khala-page-tabs";
          const FAB_ATTRIBUTE = "khala-page-fab";
          const TABLE_ATTRIBUTE = "khala-page-table";

          const post = (message) => {
            try { window.webkit.messageHandlers[HANDLER].postMessage(message); } catch (e) {}
          };
          const problems = new Set();
          const problem = (what) => {
            if (problems.has(what)) { return; }
            problems.add(what);
            post({ type: "problem", message: String(what) });
          };

          // 1. Room for the native header, through the frontend's own inset hook. Over a lifted page the header also
          //    holds the page's title (and search), so the inset grows by those blocks.
          let insetPx = INSET;
          const insetValue = () => `calc(env(safe-area-inset-top, 0px) + ${insetPx}px)`;
          const ensureInset = () => {
            const root = document.documentElement;
            if (!root) { return; }
            const value = insetValue();
            if (root.style.getPropertyValue("--app-safe-area-inset-top") !== value) {
              root.style.setProperty("--app-safe-area-inset-top", value);
            }
          };
          ensureInset();

          // Stylesheets adopted into a shadow root (or a <style> where adoption isn't supported), one per kind.
          const sheets = new Map();
          const adoptStyle = (element, key, css) => {
            const shadow = element.shadowRoot;
            if (!shadow) { problem(element.localName + " has no shadow root"); return false; }
            try {
              if ("adoptedStyleSheets" in shadow && typeof CSSStyleSheet === "function"
                  && "replaceSync" in CSSStyleSheet.prototype) {
                let sheet = sheets.get(key);
                if (!sheet) { sheet = new CSSStyleSheet(); sheet.replaceSync(css); sheets.set(key, sheet); }
                if (!shadow.adoptedStyleSheets.includes(sheet)) {
                  shadow.adoptedStyleSheets = [...shadow.adoptedStyleSheets, sheet];
                }
              } else if (!shadow.querySelector(`style[data-khala="${key}"]`)) {
                const style = document.createElement("style");
                style.dataset.khala = key;
                style.textContent = css;
                shadow.appendChild(style);
              }
              return true;
            } catch (e) { problem("could not style " + element.localName + ": " + e); return false; }
          };

          // 2. hui-root: hide its header (outside edit mode), track its instances.
          const CSS = `
            :host([${ATTRIBUTE}]) > div:not(.edit-mode) { --header-height: 0px; }
            :host([${ATTRIBUTE}]) > div:not(.edit-mode) > .header { display: none !important; }
          `;

          const roots = new Set();
          const track = (element) => {
            if (roots.has(element)) { return; }
            roots.add(element);
            adoptStyle(element, "hui-root", CSS);
          };
          // The dashboard on screen: the last connected instance that is laid out (a panel the frontend keeps
          // around for later is detached or hidden).
          const activeRoot = () => {
            let found = null;
            let fallback = null;
            roots.forEach((element) => {
              if (!element.isConnected) { roots.delete(element); return; }
              fallback = element;
              if (element.getClientRects().length) { found = element; }
            });
            return found || fallback;
          };

          // Walks the composed tree (shadow roots included) for the first element `test` accepts.
          const deepFind = (test, limit = 20000) => {
            const stack = document.documentElement ? [document.documentElement] : [];
            let seen = 0;
            while (stack.length && seen < limit) {
              const node = stack.pop();
              seen += 1;
              if (node.nodeType === 1 && test(node)) { return node; }
              if (node.shadowRoot) { stack.push(...node.shadowRoot.children); }
              if (node.children) { stack.push(...node.children); }
            }
            return null;
          };
          const deepFindAll = (tag, limit = 20000) => {
            const found = [];
            deepFind((node) => { if (node.localName === tag) { found.push(node); } return false; }, limit);
            return found;
          };

          // 3. Reports.
          const currentFromURL = (element, views) => {
            const prefix = element.route && element.route.prefix;
            if (!prefix) { return null; }
            const rest = location.pathname.startsWith(prefix) ? location.pathname.slice(prefix.length) : "";
            const segment = decodeURIComponent(rest.split("/").filter(Boolean)[0] || "");
            if (!segment) { return views.length ? 0 : null; }
            const byPath = views.findIndex((view) => view && view.path === segment);
            if (byPath >= 0) { return byPath; }
            const index = Number(segment);
            return Number.isInteger(index) && index >= 0 && index < views.length ? index : null;
          };

          const readDashboard = (element) => {
            const lovelace = element.lovelace;
            const views = lovelace && lovelace.config && lovelace.config.views;
            if (!Array.isArray(views)) { return null; } // still loading, or a frontend we don't know
            const prefix = element.route && element.route.prefix;
            if (typeof prefix !== "string") { problem("hui-root has no route prefix"); return null; }
            const userId = element.hass && element.hass.user && element.hass.user.id;
            const hiddenForUser = (view) => view.visible !== undefined && (view.visible === false
              || (Array.isArray(view.visible) && !view.visible.some((entry) => entry && entry.user === userId)));
            const current = typeof element._curView === "number" ? element._curView : currentFromURL(element, views);
            const list = [];
            views.forEach((view, index) => {
              if (!view || view.subview || hiddenForUser(view)) { return; }
              list.push({
                index,
                path: typeof view.path === "string" && view.path ? view.path : null,
                title: typeof view.title === "string" && view.title ? view.title : null,
                icon: typeof view.icon === "string" ? view.icon : null,
              });
            });
            const currentView = typeof current === "number" ? views[current] : undefined;
            let unnamedTitle = null;
            try { unnamedTitle = element.hass.localize("ui.panel.lovelace.views.unnamed_view") || null; } catch (e) {}
            return {
              prefix,
              views: list,
              current: typeof current === "number" ? current : null,
              subview: Boolean(currentView && currentView.subview),
              subviewTitle: currentView && currentView.subview && currentView.title ? currentView.title : null,
              backButton: Boolean(element.backButton),
              editMode: Boolean(lovelace.editMode),
              unnamedTitle,
              headerHidden: false,
            };
          };

          const envTop = () => {
            if (!document.body) { return 0; }
            const probe = document.createElement("div");
            probe.style.cssText = "position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;"
              + "padding-top:env(safe-area-inset-top, 0px)";
            document.body.appendChild(probe);
            const value = parseFloat(getComputedStyle(probe).paddingTop) || 0;
            probe.remove();
            return value;
          };

          const failHeader = (element, why) => {
            element.__khalaHeaderFailed = true;
            element.removeAttribute(ATTRIBUTE);
            problem(why);
          };

          // Hides the dashboard's header and checks that it worked; false leaves the frontend's own header up.
          const engageHeader = (element, dashboard) => {
            if (element.__khalaHeaderFailed) { return false; }
            if (!element.hasAttribute(ATTRIBUTE)) { element.setAttribute(ATTRIBUTE, ""); }
            if (dashboard.editMode) { return false; }
            const shadow = element.shadowRoot;
            const header = shadow && shadow.querySelector(".header");
            if (header && getComputedStyle(header).display !== "none") {
              failHeader(element, "hui-root header still visible: the hide rule no longer matches");
              return false;
            }
            if (!element.__khalaInsetVerified) {
              const container = shadow && shadow.querySelector("hui-view-container");
              if (container) {
                const padding = parseFloat(getComputedStyle(container).paddingTop) || 0;
                if (padding + 1 < INSET + envTop()) {
                  failHeader(element, "dashboard content did not move down by the header inset ("
                    + padding + "px): --app-safe-area-inset-top or --header-height no longer apply");
                  return false;
                }
                element.__khalaInsetVerified = true;
              }
            }
            return true;
          };

          let handlers = new Map();
          const label = (element) => {
            if (!element) { return ""; }
            const text = (typeof element.label === "string" && element.label)
              || (element.getAttribute && element.getAttribute("label")) || element.textContent || "";
            return text.replace(/\s+/g, " ").trim();
          };
          const readActions = (element) => {
            const next = new Map();
            const out = [];
            const shadow = element.shadowRoot;
            const bar = shadow && shadow.querySelector(".toolbar .action-items");
            let count = 0;
            if (bar) {
              Array.from(bar.children).forEach((child) => {
                if (child.localName === "ha-icon-button") {
                  const id = "a" + count++;
                  const title = label(child);
                  if (!title) { return; }
                  next.set(id, { title, run: () => child.click() });
                  out.push({ id, title, key: null });
                } else if (child.localName === "ha-dropdown") {
                  const trigger = child.querySelector('[slot="trigger"]');
                  const items = [];
                  Array.from(child.querySelectorAll("ha-dropdown-item")).forEach((item) => {
                    const id = "a" + count++;
                    const title = label(item);
                    if (!title) { return; }
                    // The toolbar's dropdowns act on `wa-select` with the chosen item (its `.data` is the
                    // action), exactly what a tap on the item sends.
                    next.set(id, {
                      title,
                      run: () => child.dispatchEvent(new CustomEvent("wa-select", { detail: { item } })),
                    });
                    const key = item.data && typeof item.data.key === "string" ? item.data.key
                      : (typeof item.value === "string" ? item.value : null);
                    items.push({ id, title, key });
                  });
                  if (trigger && trigger.id === "dashboardmenu") {
                    out.push(...items);
                  } else if (items.length) {
                    out.push({ id: "g" + count++, title: label(trigger), key: null, children: items });
                  }
                }
              });
            } else {
              problem("hui-root toolbar actions not found");
            }
            handlers = next;
            return out;
          };

          // Pages not drawn by hui-root whose chrome isn't lifted: a visible frontend back arrow is the frontend's own
          // "this is a sub-page" (its top-level pages show the menu button there instead, hidden by `hasSidebar`).
          // A whole-tree walk, so cached per path for a moment.
          let pageBackCache = { path: null, value: false, at: 0 };
          const pageHasBack = () => {
            const now = Date.now();
            if (pageBackCache.path === location.pathname && now - pageBackCache.at < 1500) {
              return pageBackCache.value;
            }
            const value = Boolean(deepFind((node) => node.localName === "ha-icon-button-arrow-prev" && visible(node)));
            pageBackCache = { path: location.pathname, value, at: now };
            return value;
          };

          // 5. Pages that aren't dashboards: their own chrome, lifted into the native header.
          const KINDS = {
            "hass-subpage": "subpage",
            "hass-tabs-subpage": "tabs",
            "ha-top-app-bar-fixed": "appbar",
            "ha-two-pane-top-app-bar-fixed": "appbar",
          };
          const PAGE_CSS = {
            subpage: `
              :host([${PAGE_ATTRIBUTE}]) .toolbar { background: transparent !important; }
              :host([${PAGE_ATTRIBUTE}]) .toolbar-content { display: none !important; }
              :host([${PAGE_ATTRIBUTE}]) .content {
                height: calc(100% - var(--safe-area-inset-top, 0px) - var(--safe-area-inset-bottom, 0px)) !important;
              }
              :host([${FAB_ATTRIBUTE}]) #fab { display: none !important; }
            `,
            tabs: `
              :host([${PAGE_ATTRIBUTE}]) .toolbar {
                height: var(--safe-area-inset-top, 0px) !important;
                background: transparent !important;
                border-bottom: none !important;
              }
              :host([${PAGE_ATTRIBUTE}]) .toolbar-content,
              :host([${PAGE_ATTRIBUTE}]) #tabbar { display: none !important; }
              :host([${PAGE_ATTRIBUTE}]) .container { height: calc(100% - var(--safe-area-inset-top, 0px)) !important; }
              /* The page scrolls on under the floating glass tabs (no band reserved below the content, which
                 read as a full-width footer): the frontend's bottom-tab margin goes, and the last rows get room
                 to scroll clear of the bar instead. A data table scrolls itself: its bottom empty row grows. */
              :host([${PAGE_ATTRIBUTE}][${TABS_ATTRIBUTE}]) .content { margin-bottom: 0 !important; }
              :host([${PAGE_ATTRIBUTE}][${TABS_ATTRIBUTE}]:not([${TABLE_ATTRIBUTE}])) .content::after {
                content: ""; display: block; height: calc(var(--safe-area-inset-bottom, 0px) + ${TAB_BAR}px);
              }
              :host([${PAGE_ATTRIBUTE}][${TABS_ATTRIBUTE}]) ::slotted(ha-data-table) {
                --data-table-empty-row-height: calc(var(--safe-area-inset-bottom, 0px) + ${TAB_BAR}px) !important;
              }
              :host([${FAB_ATTRIBUTE}]) #fab { display: none !important; }
            `,
            appbar: `
              :host([${PAGE_ATTRIBUTE}]) .row { display: none !important; }
              :host([${PAGE_ATTRIBUTE}]) .top-app-bar { background: transparent !important; box-shadow: none !important; }
              :host([${PAGE_ATTRIBUTE}]) .top-app-bar-fixed-adjust {
                top: calc(var(--sub-row-height, 0px) + var(--safe-area-inset-top, 0px)) !important;
              }
              :host([${PAGE_ATTRIBUTE}]) .shadow-container { display: none !important; }
            `,
          };
          const SEARCH_TAGS = ["ha-input-search", "search-input", "search-input-outlined", "ha-search-input"];
          const BUTTON_TAGS = ["ha-icon-button", "ha-button", "mwc-button", "ha-assist-chip", "ha-fab", "mwc-fab", "button"];
          const QUIET_TAGS = ["style", "template", "ha-svg-icon", "ha-icon", "ha-state-icon", "wa-divider", "slot"];
          const PLUS = "M19,13H13V19H11V13H5V11H11V5H13V11H19V13Z";

          const chromes = new Set();
          const trackChrome = (element) => { chromes.add(element); };
          const composedContains = (ancestor, node) => {
            for (let current = node; current; current = current.parentNode || current.host) {
              if (current === ancestor) { return true; }
            }
            return false;
          };
          // The page chrome on screen: the outermost laid-out instance (a tabbed data table holds a tabs-subpage).
          const activeChrome = () => {
            const live = [];
            chromes.forEach((element) => {
              if (!element.isConnected) { chromes.delete(element); return; }
              if (element.getClientRects().length) { live.push(element); }
            });
            return live.find((element) => !live.some((other) => other !== element && composedContains(other, element)))
              || null;
          };

          const assigned = (slot, flatten = true) => {
            if (!slot || typeof slot.assignedElements !== "function") { return []; }
            try { return slot.assignedElements({ flatten }); } catch (e) { return []; }
          };
          const slotIn = (element, name) => element.shadowRoot
            && element.shadowRoot.querySelector(name ? `slot[name="${name}"]` : "slot:not([name])");
          // What fills one of the chrome's slots: the page's elements, or the slot's own fallback when it has none.
          const slotted = (element, name) => assigned(slotIn(element, name));

          // Visits elements depth-first through slots (their assigned or fallback content), light children and shadow
          // roots. `visit` returns true to stop, "skip" not to descend.
          const walk = (nodes, visit, depth = 0) => {
            for (const node of nodes) {
              if (!node || node.nodeType !== 1) { continue; }
              if (node.localName === "slot") {
                if (walk(assigned(node), visit, depth)) { return true; }
                continue;
              }
              const result = visit(node, depth);
              if (result === true) { return true; }
              if (result === "skip" || depth >= 6) { continue; }
              if (walk(Array.from(node.children), visit, depth + 1)) { return true; }
              if (node.shadowRoot && walk(Array.from(node.shadowRoot.children), visit, depth + 1)) { return true; }
            }
            return false;
          };
          // Something a person would see or use, as opposed to an empty wrapper.
          const hasOwnContent = (node) => {
            if (QUIET_TAGS.includes(node.localName)) { return false; }
            if (node.localName.includes("-")) {
              const kids = node.shadowRoot ? Array.from(node.shadowRoot.children) : Array.from(node.children);
              return kids.some((kid) => !QUIET_TAGS.includes(kid.localName));
            }
            return Array.from(node.childNodes).some((kid) => kid.nodeType === 3 && kid.textContent.trim());
          };

          // A click where a finger would land: on the innermost link or button. The frontend's back handler
          // (`layouts/back-navigation.ts`) only acts on a click whose path holds the arrow's own anchor.
          const tap = (element) => {
            let target = element;
            for (let depth = 0; depth < 6; depth += 1) {
              const inner = target.shadowRoot
                && target.shadowRoot.querySelector("a[href], button, ha-icon-button, ha-button");
              if (!inner) { break; }
              target = inner;
            }
            target.click();
          };

          let pageHandlers = new Map();
          let pageCount = 0;
          const register = (title, run) => {
            const id = "p" + pageCount++;
            pageHandlers.set(id, { title, run });
            return { id, title, key: null };
          };
          // A dropdown item, chosen the way a tap chooses it: the item's own click handlers (To-do's list picker uses
          // them), then the dropdown's `wa-select` (the toolbars' menus use that) unless the click already sent it.
          const choose = (dropdown, item) => {
            let selected = false;
            const seen = () => { selected = true; };
            dropdown.addEventListener("wa-select", seen);
            try { item.click(); } finally { dropdown.removeEventListener("wa-select", seen); }
            if (!selected) { dropdown.dispatchEvent(new CustomEvent("wa-select", { detail: { item } })); }
          };
          const readDropdown = (dropdown) => {
            const trigger = dropdown.querySelector('[slot="trigger"]');
            const items = [];
            Array.from(dropdown.querySelectorAll("ha-dropdown-item")).forEach((item) => {
              const title = label(item);
              if (!title) { return; }
              const action = register(title, () => choose(dropdown, item));
              action.key = item.data && typeof item.data.key === "string" ? item.data.key
                : (typeof item.value === "string" && item.value ? item.value : null);
              if (item.type === "checkbox" || (item.getAttribute && item.getAttribute("type") === "checkbox")) {
                action.checked = Boolean(item.checked);
              }
              if (item.disabled) { action.disabled = true; }
              items.push(action);
            });
            return { trigger, title: label(trigger), items };
          };
          // The tools in a toolbar slot: buttons and menus, through wrappers and small components. `unreadable` names
          // a tool that shows something but offers nothing the script can run (the page then keeps its own toolbar).
          const readTools = (elements) => {
            const tools = [];
            let unreadable = null;
            elements.forEach((top) => {
              const before = tools.length;
              let content = false;
              walk([top], (node) => {
                if (hasOwnContent(node)) { content = true; }
                if (node.getAttribute("slot") === "trigger") { return "skip"; }
                if (node.localName === "ha-dropdown") {
                  const menu = readDropdown(node);
                  if (menu.items.length) {
                    tools.push({ id: "p" + pageCount++, title: menu.title, key: null, children: menu.items });
                  }
                  return "skip";
                }
                if (BUTTON_TAGS.includes(node.localName) || (node.localName === "a" && node.hasAttribute("href"))) {
                  const title = label(node);
                  if (title) { tools.push(register(title, () => tap(node))); }
                  return "skip";
                }
                return undefined;
              });
              if (tools.length === before && content && !unreadable) { unreadable = top.localName; }
            });
            return { tools, unreadable };
          };

          // The header area (subpage/tabs `header` slot, app bar `title` slot): plain text is the title, a search
          // field is the page's search, a dropdown is a title menu; anything else can't be drawn natively.
          const readHeader = (elements) => {
            const result = { text: "", search: null, menu: null, unreadable: null };
            walk(elements, (node) => {
              if (SEARCH_TAGS.includes(node.localName)) { result.search = node; return "skip"; }
              if (node.localName === "ha-dropdown") { result.menu = node; return "skip"; }
              if (BUTTON_TAGS.includes(node.localName) || ["a", "input", "select", "textarea"].includes(node.localName)
                  || node.localName.endsWith("-picker") || node.localName.includes("textfield")) {
                result.unreadable = result.unreadable || node.localName;
                return "skip";
              }
              return node.localName.includes("-") && !QUIET_TAGS.includes(node.localName) && node.shadowRoot
                ? "skip" : undefined;
            });
            if (!result.search && !result.menu) {
              result.text = elements.map((element) => element.textContent || "").join(" ").replace(/\s+/g, " ").trim();
            }
            return result;
          };

          // The tabs the frontend would show (`hass-tabs-subpage._getTabs`: `canShowPage`, translated names).
          const shownTabs = (element) => {
            const tabs = Array.isArray(element.tabs) ? element.tabs : [];
            const hass = element.hass;
            const components = (hass && hass.config && Array.isArray(hass.config.components)) ? hass.config.components : [];
            const localize = element.localizeFunc || (hass && hass.localize);
            const active = element._activeTab;
            const here = location.pathname;
            return tabs.filter((page) => {
              if (!page || typeof page.path !== "string") { return false; }
              const loaded = page.core || !page.component
                || [].concat(page.component).some((component) => components.includes(component));
              let passes = true;
              if (typeof page.filter === "function") { try { passes = Boolean(page.filter(hass)); } catch (e) {} }
              return loaded && passes;
            }).map((page) => {
              let title = page.name || "";
              if (page.translationKey && typeof localize === "function") {
                try { title = localize(page.translationKey) || title; } catch (e) {}
              }
              const isActive = active ? active.path === page.path : (here === page.path || here.startsWith(page.path + "/"));
              return { path: page.path, title, active: Boolean(isActive) };
            });
          };

          const readPrimary = (element) => {
            let fab = null;
            walk(slotted(element, "fab"), (node) => {
              if (BUTTON_TAGS.includes(node.localName) || (node.localName === "a" && node.hasAttribute("href"))) {
                fab = node;
                return true;
              }
              return undefined;
            });
            if (!fab) { return null; }
            let isAdd = false;
            walk([fab], (node) => {
              if (node.localName === "ha-svg-icon" && node.path === PLUS) { isAdd = true; return true; }
              return undefined;
            });
            if (!isAdd) { return null; }
            const inner = fab.querySelector && fab.querySelector("ha-fab, ha-button, mwc-fab");
            const title = label(fab) || label(inner) || "+";
            return { element: fab, title };
          };

          // Reads the page's chrome; `liftable` false (with `why`) when Khala can't stand in for it.
          const readPage = (element) => {
            const kind = KINDS[element.localName];
            const shadow = element.shadowRoot;
            if (!kind || !shadow) { return null; }
            pageHandlers = new Map();
            pageCount = 0;
            const page = { kind, title: null, back: false, tabs: [], search: null, primary: null, tools: [], titleMenu: [] };
            let why = null;
            let arrow = null;

            if (kind === "appbar") {
              const nav = slotted(element, "navigationIcon");
              arrow = nav.find((node) => node.localName === "ha-icon-button-arrow-prev") || null;
              const other = nav.find((node) => node.localName !== "ha-icon-button-arrow-prev"
                && node.localName !== "ha-menu-button");
              if (other) { why = "navigation icon " + other.localName; }
            } else {
              if (kind === "tabs" && assigned(slotIn(element, "toolbar"), false).length) {
                why = "toolbar replaced (selection mode)";
              }
              arrow = shadow.querySelector(".toolbar-content ha-icon-button-arrow-prev");
              if (!arrow && !shadow.querySelector(".toolbar-content ha-menu-button") && !why) {
                why = "no back arrow or menu button";
              }
            }
            page.back = Boolean(arrow);

            const header = readHeader(slotted(element, kind === "appbar" ? "title" : "header"));
            if (header.unreadable && !why) { why = "header holds " + header.unreadable; }
            if (header.search) {
              page.search = {
                placeholder: header.search.placeholder || header.search.label || null,
                value: typeof header.search.value === "string" ? header.search.value : "",
              };
            }
            if (header.menu) {
              const menu = readDropdown(header.menu);
              page.title = menu.title || null;
              page.titleMenu = menu.items;
            }
            if (kind === "tabs") {
              page.tabs = shownTabs(element);
              if (!page.title && !header.search && !header.menu && header.text) {
                page.title = header.text;
              } else if (!page.title) {
                const active = page.tabs.find((tab) => tab.active);
                page.title = (page.tabs.length > 1 ? active && active.title : page.tabs[0] && page.tabs[0].title) || null;
              }
            } else if (!page.title) {
              page.title = header.text || (typeof element.header === "string" ? element.header : "") || null;
            }

            const tools = readTools(slotted(element, kind === "appbar" ? "actionItems" : "toolbar-icon"));
            page.tools = tools.tools;
            if (tools.unreadable && !why) { why = "toolbar tool " + tools.unreadable; }

            const primary = readPrimary(element);
            if (primary) {
              const fab = primary.element;
              page.primary = register(primary.title, () => tap(fab));
            }
            return { element, kind, page, arrow, why, search: header.search, hasPrimary: Boolean(primary) };
          };

          const unliftPage = (element) => {
            [PAGE_ATTRIBUTE, TABS_ATTRIBUTE, FAB_ATTRIBUTE, TABLE_ATTRIBUTE].forEach((name) => element.removeAttribute(name));
          };
          const failPage = (element, why) => {
            element.__khalaPageFailed = true;
            unliftPage(element);
            problem(why);
          };
          const setAttribute = (element, name, on) => {
            if (on && !element.hasAttribute(name)) { element.setAttribute(name, ""); }
            if (!on && element.hasAttribute(name)) { element.removeAttribute(name); }
          };
          // Lifts the page's chrome and checks that it worked; false leaves the frontend's own toolbar up.
          const engagePage = (read, dialogOpen) => {
            const { element, kind, page } = read;
            if (element.__khalaPageFailed) { return false; }
            if (read.why) {
              unliftPage(element);
              problem("page chrome left to the frontend on " + location.pathname.split("/").slice(0, 3).join("/")
                + ": " + read.why);
              return false;
            }
            if (!adoptStyle(element, "page-" + kind, PAGE_CSS[kind])) { failPage(element, "page chrome not styled"); return false; }
            setAttribute(element, PAGE_ATTRIBUTE, true);
            setAttribute(element, TABS_ATTRIBUTE, page.tabs.length > 1);
            setAttribute(element, FAB_ATTRIBUTE, read.hasPrimary);
            const outer = element.getRootNode() && element.getRootNode().host;
            setAttribute(element, TABLE_ATTRIBUTE, Boolean(outer && outer.localName === "hass-tabs-subpage-data-table"));
            insetPx = INSET + (dialogOpen ? 0 : TITLE_BLOCK + (page.search ? SEARCH_BLOCK : 0));
            ensureInset();
            const shadow = element.shadowRoot;
            const hidden = shadow.querySelector(kind === "appbar" ? ".row" : ".toolbar-content");
            if (hidden && getComputedStyle(hidden).display !== "none") {
              failPage(element, element.localName + " toolbar still visible: the hide rule no longer matches");
              return false;
            }
            const content = shadow.querySelector(
              kind === "appbar" ? ".top-app-bar-fixed-adjust" : (kind === "tabs" ? ".container" : ".content"));
            // Measured once per element and inset (a layout read plus a probe element, and reports come often).
            if (content && element.__khalaVerifiedInset !== insetPx) {
              const top = content.getBoundingClientRect().top;
              if (top + 1 < insetPx + envTop()) {
                failPage(element, element.localName + " content did not move below the header ("
                  + Math.round(top) + "px): --safe-area-inset-top no longer applies");
                return false;
              }
              element.__khalaVerifiedInset = insetPx;
            }
            return true;
          };

          let activePage = null;
          let last = null;
          const report = () => {
            try {
              const dialog = history.state && typeof history.state.dialog === "string" ? history.state.dialog : null;
              const element = activeRoot();
              let dashboard = null;
              let actions = [];
              if (element) {
                dashboard = readDashboard(element);
                if (dashboard) {
                  dashboard.headerHidden = engageHeader(element, dashboard);
                  if (dashboard.headerHidden) { actions = readActions(element); }
                }
              }
              if (!actions.length) { handlers = new Map(); }
              const onDashboard = Boolean(dashboard && visible(element));
              let page = null;
              activePage = null;
              if (!onDashboard) {
                const chrome = activeChrome();
                const read = chrome ? readPage(chrome) : null;
                if (read) {
                  const lifted = engagePage(read, Boolean(dialog));
                  activePage = { ...read, lifted };
                  page = { ...read.page, lifted };
                  if (!lifted) {
                    page.tools = [];
                    page.titleMenu = [];
                    page.primary = null;
                    page.search = null;
                    pageHandlers = new Map();
                  }
                } else {
                  pageHandlers = new Map();
                }
              } else {
                pageHandlers = new Map();
              }
              if (!page || !page.lifted) {
                insetPx = INSET;
                ensureInset();
              }
              const state = {
                path: location.pathname,
                dialog,
                dashboard,
                actions,
                pageBack: onDashboard ? null : (page && page.lifted ? page.back : pageHasBack()),
                page,
              };
              const json = JSON.stringify(state);
              if (json === last) { return; }
              last = json;
              post({ type: "state", state });
            } catch (e) { problem("report failed: " + e); }
          };
          let pending = null;
          const schedule = () => {
            if (pending !== null) { return; }
            pending = setTimeout(() => { pending = null; report(); }, 60);
          };
          // After a navigation the new page renders a little later: look again once it has.
          const scheduleSettled = () => {
            schedule();
            setTimeout(() => { pageBackCache.at = 0; schedule(); }, 400);
            setTimeout(() => { pageBackCache.at = 0; schedule(); }, 1200);
          };

          // Lifecycle callbacks (connectedCallback, ...) are captured when an element is defined, so a patch can't reach
          // them; `updated` is an ordinary method Lit calls after every render, the first included.
          const patchUpdated = (tag, onUpdate) => {
            customElements.whenDefined(tag).then(() => {
              const definition = customElements.get(tag);
              const proto = definition && definition.prototype;
              if (!proto || Object.prototype.hasOwnProperty.call(proto, "__khalaPatched")) { return; }
              const updated = proto.updated;
              if (typeof updated !== "function") {
                problem(tag + " lifecycle changed: updated() missing");
                return;
              }
              proto.updated = function (changed) {
                updated.call(this, changed);
                onUpdate(this);
                schedule();
              };
              Object.defineProperty(proto, "__khalaPatched", { value: true });
              // Instances that rendered before this patch are picked up now.
              deepFindAll(tag).forEach(onUpdate);
              schedule();
            });
          };
          patchUpdated("hui-root", track);
          Object.keys(KINDS).forEach((tag) => patchUpdated(tag, trackChrome));

          // Navigation and dialogs: the frontend's router fires `location-changed`, the dialog manager pushes
          // and replaces history entries, and back pops them.
          ["pushState", "replaceState"].forEach((name) => {
            const original = history[name];
            if (typeof original !== "function") { return; }
            history[name] = function (...args) {
              const result = original.apply(this, args);
              scheduleSettled();
              return result;
            };
          });
          ["location-changed", "popstate", "show-dialog", "dialog-closed"].forEach((name) => {
            window.addEventListener(name, scheduleSettled);
          });
          document.addEventListener("DOMContentLoaded", scheduleSettled, { once: true });
          window.addEventListener("load", scheduleSettled, { once: true });

          // 4. What the native header drives.
          const visible = (element) => Boolean(element && element.getClientRects().length);
          const back = () => {
            if (history.state && history.state.dialog) {
              history.back();
              return "dialog";
            }
            const element = activeRoot();
            const arrow = element && visible(element) && element.shadowRoot
              && element.shadowRoot.querySelector(".toolbar ha-icon-button-arrow-prev");
            if (arrow) {
              tap(arrow);
              return "frontend";
            }
            // A lifted page's arrow is hidden with its toolbar; it still runs the page's own back handling.
            if (activePage && activePage.arrow && activePage.element.isConnected) {
              tap(activePage.arrow);
              return "frontend";
            }
            const pageArrow = deepFind((node) => node.localName === "ha-icon-button-arrow-prev" && visible(node));
            if (pageArrow) {
              tap(pageArrow);
              return "frontend";
            }
            return "none";
          };
          const perform = (id, title) => {
            const handler = handlers.get(id) || pageHandlers.get(id);
            if (!handler || handler.title !== title) { problem("toolbar action gone: " + title); return false; }
            try { handler.run(); return true; } catch (e) { problem("toolbar action failed: " + e); return false; }
          };
          const search = (text) => {
            const field = activePage && activePage.lifted && activePage.search;
            if (!field || !field.isConnected) { problem("page search gone"); return false; }
            try {
              field.value = String(text);
              field.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
              return true;
            } catch (e) { problem("page search failed: " + e); return false; }
          };
          const tab = (path) => {
            const element = activePage && activePage.lifted && activePage.element;
            const links = element && element.shadowRoot ? Array.from(element.shadowRoot.querySelectorAll("#tabbar a")) : [];
            const link = links.find((anchor) => anchor.getAttribute("href") === path);
            if (!link) { problem("page tab link not found: " + path); return false; }
            link.click();
            return true;
          };
          window.__khala = Object.freeze({
            back,
            perform,
            search,
            tab,
            report: () => { last = null; report(); },
          });
        })();
        """#
    }
}
