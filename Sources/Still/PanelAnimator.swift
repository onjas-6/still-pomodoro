// Created 2026-09-15 · gpt-6-astra · Codex
import AppKit

/// One interruptible clock owns the native frame and the SwiftUI reveal together.
/// Resizing never relies on the hosting view's intrinsic size or window animations.
@MainActor
final class PanelAnimator {
    private var timer: Timer?
    private(set) var isAnimating = false

    func cancel() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
    }

    func animate(from start: NSRect, to end: NSRect, duration: TimeInterval,
                 update: @escaping (NSRect, CGFloat) -> Void,
                 completion: @escaping () -> Void) {
        cancel()
        guard duration > 0 else { update(end, 1); completion(); return }
        isAnimating = true
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            let eased = CGFloat(1 - pow(1 - t, 4))
            let frame = NSRect(x: start.minX + (end.minX - start.minX) * eased,
                               y: start.minY + (end.minY - start.minY) * eased,
                               width: start.width + (end.width - start.width) * eased,
                               height: start.height + (end.height - start.height) * eased)
            update(t >= 1 ? end : frame, eased)
            if t >= 1 { self.cancel(); completion() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
