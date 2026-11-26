// Created 2026-09-18 · gpt-6-astra · Codex
import Foundation
import UserNotifications

/// A local clock window. An end earlier than the start crosses midnight.
enum RestSchedule {
    static let notificationID = "still.rest.start"

    static func notificationRequest(for preferences: Preferences) -> UNNotificationRequest? {
        guard preferences.restReminderEnabled, preferences.restStartMinute != preferences.restEndMinute else { return nil }
        let minute = preferences.restStartMinute
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: minute / 60, minute: minute % 60), repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Time to rest"
        content.body = preferences.restMessage
        return UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
    }

    static func contains(_ date: Date, startMinute: Int, endMinute: Int, calendar: Calendar = .current) -> Bool {
        guard startMinute != endMinute else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute < endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}
