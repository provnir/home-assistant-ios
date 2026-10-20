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
enum KhalaFrontendScript {
    /// The `WKScriptMessageHandler` name the script posts to.
    static let messageHandlerName = "khalaShell"

    /// Height of the native header's row below the status bar: 9 pt above the 44 pt glass buttons, 9 below
    /// (the shell's pinned menu button sits at 9 pt, `KhalaShellView.menuButtonInset`).
    static let headerInset: Double = 9 + 44 + 9

    /// JavaScript that calls the script's `back()`; the result is "dialog", "frontend" or "none".
    static let backCall = "window.__khala ? window.__khala.back() : 'none'"

    /// JavaScript that asks the script for a fresh report.
    static let reportCall = "window.__khala && window.__khala.report()"

    /// JavaScript that performs one of the dashboard's toolbar actions; the result is true when it ran.
    static func performCall(actionId: String, title: String) -> String {
        "window.__khala ? window.__khala.perform(\(literal(actionId)), \(literal(title))) : false"
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
        return #"""
        (() => {
          if (window.__khala) { return; }
          const HANDLER = "\#(messageHandlerName)";
          const INSET = \#(inset);
          const ATTRIBUTE = "khala-native-header";

          const post = (message) => {
            try { window.webkit.messageHandlers[HANDLER].postMessage(message); } catch (e) {}
          };
          const problems = new Set();
          const problem = (what) => {
            if (problems.has(what)) { return; }
            problems.add(what);
            post({ type: "problem", message: String(what) });
          };

          // 1. Room for the native header, through the frontend's own inset hook.
          const insetValue = `calc(env(safe-area-inset-top, 0px) + ${INSET}px)`;
          const ensureInset = () => {
            const root = document.documentElement;
            if (!root) { return; }
            if (root.style.getPropertyValue("--app-safe-area-inset-top") !== insetValue) {
              root.style.setProperty("--app-safe-area-inset-top", insetValue);
            }
          };
          ensureInset();

          // 2. hui-root: hide its header (outside edit mode), track its instances.
          const CSS = `
            :host([${ATTRIBUTE}]) > div:not(.edit-mode) { --header-height: 0px; }
            :host([${ATTRIBUTE}]) > div:not(.edit-mode) > .header { display: none !important; }
          `;
          let sheet = null;
          const adopt = (element) => {
            const shadow = element.shadowRoot;
            if (!shadow) { problem("hui-root has no shadow root"); return; }
            try {
              if ("adoptedStyleSheets" in shadow && typeof CSSStyleSheet === "function"
                  && "replaceSync" in CSSStyleSheet.prototype) {
                if (!sheet) { sheet = new CSSStyleSheet(); sheet.replaceSync(CSS); }
                if (!shadow.adoptedStyleSheets.includes(sheet)) {
                  shadow.adoptedStyleSheets = [...shadow.adoptedStyleSheets, sheet];
                }
              } else if (!shadow.querySelector("style[data-khala]")) {
                const style = document.createElement("style");
                style.dataset.khala = "";
                style.textContent = CSS;
                shadow.appendChild(style);
              }
            } catch (e) { problem("could not style hui-root: " + e); }
          };

          const roots = new Set();
          const track = (element) => {
            if (roots.has(element)) { return; }
            roots.add(element);
            adopt(element);
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

          // Pages not drawn by hui-root (config, history, ...): a visible frontend back arrow is the frontend's own
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

          let last = null;
          const report = () => {
            try {
              ensureInset();
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
              const state = {
                path: location.pathname,
                dialog: history.state && typeof history.state.dialog === "string" ? history.state.dialog : null,
                dashboard,
                actions,
                pageBack: onDashboard ? null : pageHasBack(),
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

          customElements.whenDefined("hui-root").then(() => {
            const definition = customElements.get("hui-root");
            const proto = definition && definition.prototype;
            if (!proto || proto.__khalaPatched) { return; }
            // Lifecycle callbacks (connectedCallback, ...) are captured when the element is defined, so a patch
            // can't reach them; `updated` is an ordinary method Lit calls after every render, the first included.
            const updated = proto.updated;
            if (typeof updated !== "function") {
              problem("hui-root lifecycle changed: updated() missing");
              return;
            }
            proto.updated = function (changed) {
              updated.call(this, changed);
              track(this);
              schedule();
            };
            proto.__khalaPatched = true;
            // Instances that rendered before this patch (none usually) are picked up now.
            deepFindAll("hui-root").forEach(track);
            schedule();
          });

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
          const back = () => {
            if (history.state && history.state.dialog) {
              history.back();
              return "dialog";
            }
            const element = activeRoot();
            const arrow = element && element.shadowRoot
              && element.shadowRoot.querySelector(".toolbar ha-icon-button-arrow-prev");
            if (arrow) {
              tap(arrow);
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
            const handler = handlers.get(id);
            if (!handler || handler.title !== title) { problem("toolbar action gone: " + title); return false; }
            try { handler.run(); return true; } catch (e) { problem("toolbar action failed: " + e); return false; }
          };
          window.__khala = Object.freeze({
            back,
            perform,
            report: () => { last = null; report(); },
          });
        })();
        """#
    }
}
