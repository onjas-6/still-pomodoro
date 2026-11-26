import AppKit
import SwiftUI

@MainActor
final class FocusNoticePanel {
    var dismiss: (() -> Void)?
    private var panel: NSPanel?

    func present(_ notice: FocusNotice?) {
        guard let notice else {
            panel?.orderOut(nil)
            panel = nil
            return
        }
        let window = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        window.title = "Still — Focus reminder"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hidesOnDeactivate = false
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: FocusNoticeView(notice: notice, dismiss: { [weak self] in self?.dismiss?() }))
        window.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 30,
                                   width: size.width, height: size.height), display: true)
        }
        window.orderFrontRegardless()
        panel = window
    }
}

private struct FocusNoticeView: View {
    let notice: FocusNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: notice == .browserAccess ? "globe" : "scope")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color(red: 0.99, green: 0.78, blue: 0.33))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                switch notice {
                case let .distraction(target):
                    Text("You need to focus.").font(.system(size: 29, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(target) is on your focus reminder list.").font(.callout)
                    Button("Dismiss for this visit", action: dismiss).padding(.top, 5)
                case .browserAccess:
                    Text("Enable website reminders").font(.system(size: 20, weight: .semibold))
                    Text("Allow Still in Accessibility so it can check the active site during focus.")
                        .font(.callout)
                    HStack {
                        Button("Allow access…") { dismiss(); BrowserLocation.requestAccess() }
                        Button("Later", action: dismiss)
                    }.padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22).frame(width: 438, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white).colorScheme(.dark)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.14, green: 0.17, blue: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(red: 0.99, green: 0.78, blue: 0.33), lineWidth: 3))
    }
}
