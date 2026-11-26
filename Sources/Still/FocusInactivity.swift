import CoreGraphics
import Foundation

/// Tracks input-idle episodes relative to an explicit focus-session baseline.
struct FocusInactivity {
    private var baselineUptime: TimeInterval?

    /// Starts a fresh idle baseline, so input before a focus start, resume, or wake
    /// cannot count toward the next reminder.
    mutating func reset(at uptime: TimeInterval) {
        baselineUptime = uptime.isFinite && uptime >= 0 ? uptime : nil
    }

    /// Returns whether the current uninterrupted input-idle episode has lasted
    /// at least `threshold`. An input resets the result until a new episode reaches
    /// the threshold.
    mutating func evaluate(idleSeconds: TimeInterval, at uptime: TimeInterval, threshold: TimeInterval) -> Bool {
        guard idleSeconds.isFinite, idleSeconds >= 0,
              uptime.isFinite, uptime >= 0,
              threshold.isFinite, threshold > 0 else { return false }

        guard let baseline = baselineUptime else {
            reset(at: uptime)
            return false
        }

        // A clock discontinuity needs a new baseline; a stale one must not carry
        // into a later focus session.
        guard uptime >= baseline else {
            reset(at: uptime)
            return false
        }

        // `idleSeconds` is measured from the most recent input, even if it happened
        // between polls. Capping it at this focus baseline discards pre-focus idle.
        return min(idleSeconds, uptime - baseline) >= threshold
    }

    /// Seconds since any HID input, using the system's monotonic event source.
    static func inputIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            // `kCGAnyInputEventType` is not imported into Swift.
            eventType: CGEventType(rawValue: UInt32.max)!
        )
    }
}
