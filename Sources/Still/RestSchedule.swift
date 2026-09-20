// Created 2026-09-18 · gpt-6-astra · Codex
import Foundation

/// A local clock window. An end earlier than the start crosses midnight.
enum RestSchedule {
    static func contains(_ date: Date, startMinute: Int, endMinute: Int, calendar: Calendar = .current) -> Bool {
        guard startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}
