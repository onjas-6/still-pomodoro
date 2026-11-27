// Created 2026-11-27 · Claude Code
import AppKit
import SwiftUI

/// Renders the Preferences window and the research check-in panel to PNG files for layout
/// review, using preview data only. Run locally in a graphical login session:
/// Still --preferences-snapshot <directory>. Preferences are captured in window-height pages.
@MainActor
enum PreferencesSnapshot {
    static func run(model: AppModel, directory: URL, showSettings: () -> Void, window: () -> NSWindow?,
                    research: ResearchSampler) async -> Int32 {
        precondition(model.isPreview, "Snapshots must never use a real user model")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fputs("Could not create \(directory.path): \(error.localizedDescription)\n", stderr)
            return 1
        }
        showSettings()
        var written = 0
        for theme in ["light", "dark"] {
            model.preferences.theme = theme
            model.savePreferences()
            guard let window = window() else { return 1 }
            window.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
            written += await capturePages(of: window, named: "preferences-\(theme)", in: directory)
        }
        // The research card while a study runs (preview stores are never saved).
        research.start()
        model.preferences.theme = "light"
        model.savePreferences()
        if let window = window() {
            window.appearance = NSAppearance(named: .aqua)
            written += await capturePages(of: window, named: "preferences-study-running", in: directory)
        }
        for (name, askingWhy) in [("check-in-question", false), ("check-in-reasons", true)] {
            let hosting = NSHostingView(rootView: ResearchPromptView(
                caption: "Check-in 2 of 4 today · day 3 of 14", askingWhy: askingWhy) { _ in })
            let size = hosting.fittingSize
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                backing: .buffered, defer: false)
            panel.backgroundColor = .windowBackgroundColor
            panel.contentView = hosting
            panel.orderFrontRegardless()
            try? await Task.sleep(nanoseconds: 400_000_000)
            if write(hosting, to: directory.appendingPathComponent("\(name).png")) { written += 1 }
            panel.orderOut(nil)
        }
        return written > 0 ? 0 : 1
    }

    private static func capturePages(of window: NSWindow, named name: String, in directory: URL) async -> Int {
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard let content = window.contentView else { return 0 }
        content.layoutSubtreeIfNeeded()
        let scroll = firstScrollView(in: content)
        let documentHeight = scroll?.documentView?.frame.height ?? content.bounds.height
        let pageHeight = scroll?.contentView.bounds.height ?? content.bounds.height
        var offset: CGFloat = 0
        var page = 1
        var written = 0
        repeat {
            if let scroll {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: flippedOffset(offset, in: scroll, page: pageHeight)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if write(content, to: directory.appendingPathComponent("\(name)-\(page).png")) { written += 1 }
            offset += pageHeight * 0.9
            page += 1
        } while offset < documentHeight - pageHeight * 0.1 && page <= 10
        return written
    }

    private static func write(_ view: NSView, to url: URL) -> Bool {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return false }
        print("Wrote \(url.path)")
        return true
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    /// SwiftUI's document view may or may not be flipped; convert a top-based offset.
    private static func flippedOffset(_ top: CGFloat, in scroll: NSScrollView, page: CGFloat) -> CGFloat {
        guard let document = scroll.documentView, !document.isFlipped else { return top }
        return max(0, document.frame.height - page - top)
    }
}
