import Foundation
import StillCore

/// A local calendar day's latest commitment and its actual timeline.
struct FocusDay: Identifiable {
    struct Activity: Identifiable {
        let id: UUID
        let date: Date
        let start: Date?
        let zone: TimeZone
        let detail: String
        let symbol: String

        var timeLabel: String {
            let end = FocusDay.time(date, in: zone)
            guard let start else { return end }
            var format = Date.FormatStyle(date: .omitted, time: .shortened)
            format.timeZone = zone
            if DailyEvent.dayID(for: start, in: zone) != DailyEvent.dayID(for: date, in: zone) {
                format = Date.FormatStyle(date: .abbreviated, time: .shortened)
                format.timeZone = zone
            }
            return "\(start.formatted(format)) – \(end)"
        }
    }

    let id: String
    var goal: Int?
    var completed = 0
    var minutes = 0
    var activity: [Activity] = []

    var progressText: String {
        if let goal, goal > 0 { return "\(completed) / \(goal)" }
        return "\(completed)"
    }

    var hoverText: String {
        switch goal {
        case nil: return "\(completed) today · no goal"
        case 0: return "\(completed) today · rest day"
        default: return "Today  \(progressText)"
        }
    }

    func status(isToday: Bool) -> String {
        guard let goal else { return "No goal set" }
        if goal == 0 { return "Rest day" }
        if completed >= goal { return "Goal met" }
        let remaining = goal - completed
        return isToday ? "\(remaining) to go" : "\(remaining) short"
    }

    static func history(_ entries: JournalEntries) -> [String: FocusDay] {
        var days: [String: FocusDay] = [:]
        for session in entries.sessions {
            let zone = session.timeZone ?? .current
            let day = DailyEvent.dayID(for: session.completedAt, in: zone)
            let minutes = Int((session.duration / 60).rounded())
            days[day, default: FocusDay(id: day)].completed += 1
            days[day]?.minutes += minutes
            days[day]?.activity.append(Activity(id: session.id, date: session.completedAt, start: session.startedAt, zone: zone,
                detail: "Completed · \(minutes) min", symbol: "checkmark.circle"))
        }
        // Equal timestamps from two devices still yield the same final goal on both.
        let events = entries.events.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        for event in events {
            let day = DailyEvent.dayID(for: event.date, in: event.timeZone)
            let detail: String
            let symbol: String
            let start: Date?
            switch event.kind {
            case let .goal(target):
                days[day, default: FocusDay(id: day)].goal = target
                detail = target == 0 ? "Planned a rest day" : "Set goal to \(target)"
                symbol = "flag"
                start = nil
            case let .stopped(startedAt):
                detail = "Stopped early"
                start = startedAt
                symbol = "stop.circle"
            }
            days[day, default: FocusDay(id: day)].activity.append(Activity(
                id: event.id, date: event.date, start: start, zone: event.timeZone, detail: detail, symbol: symbol))
        }
        for id in Array(days.keys) {
            days[id]?.activity.sort { $0.date > $1.date }
        }
        return days
    }

    static func time(_ date: Date, in zone: TimeZone) -> String {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = zone
        return date.formatted(format)
    }
}
