import AppKit
import ApplicationServices
import Foundation

enum BrowserLocation {
    static let browsers: Set<String> = [
        "com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome",
        "com.google.chrome.beta", "com.google.chrome.canary", "org.chromium.chromium",
        "com.microsoft.edgemac", "com.brave.browser", "com.vivaldi.vivaldi", "com.operasoftware.opera",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen",
        "company.thebrowser.browser", "company.thebrowser.dia", "com.openai.atlas"
    ]

    enum Result: Sendable {
        case site(String?)
        case accessRequired
    }

    static func read(pid: pid_t) -> Result {
        guard AXIsProcessTrusted() else { return .accessRequired }
        return .site(host(pid: pid))
    }

    static func requestAccess() {
        guard !AXIsProcessTrusted() else { return }
        let key = "didRequestWebsiteAccessibility"
        if UserDefaults.standard.bool(forKey: key),
           let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(pane)
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Only consider a committed web document. Search terms, window titles and text
    /// fields (including partly typed addresses) never participate in matching.
    private static func host(pid: pid_t) -> String? {
        guard let root = focusedWindow(AXUIElementCreateApplication(pid)),
              attribute(root, kAXMinimizedAttribute) as? Bool != true else { return nil }
        return webURL(in: root)?.host.flatMap(FocusTargets.domain)
    }

    /// The focused window's title and the address it shows: a web page in browsers, or a
    /// document file in apps that expose one. Used only for research check-ins.
    static func windowContext(pid: pid_t, isBrowser: Bool) -> (title: String?, url: URL?) {
        guard AXIsProcessTrusted(), let root = focusedWindow(AXUIElementCreateApplication(pid)) else { return (nil, nil) }
        let title = (attribute(root, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        let url = isBrowser ? webURL(in: root) : attribute(root, kAXDocumentAttribute).flatMap(urlValue)
        return (title, url)
    }

    private static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        guard let window = attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    private static func webURL(in root: AXUIElement) -> URL? {
        if let document = attribute(root, kAXDocumentAttribute), let url = webURLValue(document) { return url }

        // Some browsers expose the address on the visible web area's root. Never
        // descend into page content, or select a link or background tab by title.
        var queue = [root]
        var index = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.45
        while index < queue.count && index < 120 && ProcessInfo.processInfo.systemUptime < deadline {
            let element = queue[index]
            index += 1
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == "AXWebArea" {
                return attribute(element, kAXURLAttribute).flatMap(webURLValue)
            }
            guard let role, ["AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea",
                              "AXTabGroup", "AXUnknown"].contains(role) else { continue }
            var children: CFArray?
            let space = 120 - queue.count
            if space > 0, AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, space, &children) == .success,
               let children = children as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private static func urlValue(_ value: CFTypeRef) -> URL? {
        value as? URL ?? (value as? String).flatMap(URL.init(string:))
    }

    private static func webURLValue(_ value: CFTypeRef) -> URL? {
        guard let url = urlValue(value), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
        return url
    }
}
