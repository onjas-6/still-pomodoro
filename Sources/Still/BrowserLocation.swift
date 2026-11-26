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
        let app = AXUIElementCreateApplication(pid)
        guard let window = attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let root = window as! AXUIElement
        guard attribute(root, kAXMinimizedAttribute) as? Bool != true else { return nil }
        if let document = attribute(root, kAXDocumentAttribute), let host = webHost(document) { return host }

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
                return attribute(element, kAXURLAttribute).flatMap(webHost)
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

    private static func webHost(_ value: CFTypeRef) -> String? {
        let url = value as? URL ?? (value as? String).flatMap(URL.init(string:))
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host else { return nil }
        return FocusTargets.domain(host)
    }
}
