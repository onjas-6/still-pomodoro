// Created 2026-11-27 · Claude Code
import Foundation

/// An experience-sampling study: for a fixed number of days, a few check-ins arrive at
/// random moments inside a daily window. The schedule is derived from the study's
/// identifier, so it survives relaunches without being stored and is never shown ahead.
public struct ResearchStudy: Codable, Equatable, Sendable {
    public static let dayRange = 3...28
    public static let promptRange = 2...8
    public static let defaultDays = 14
    public static let defaultPrompts = 4
    public static let defaultWindow = (start: 10 * 60, end: 23 * 60)

    public let id: UUID
    public let startedAt: Date
    public let days: Int
    public let promptsPerDay: Int
    /// Local minutes after midnight. The window stays within one calendar day.
    public let windowStartMinute: Int
    public let windowEndMinute: Int
    public let timeZone: TimeZone
    public var stoppedAt: Date?

    public init(id: UUID = UUID(), startedAt: Date, days: Int = ResearchStudy.defaultDays,
                promptsPerDay: Int = ResearchStudy.defaultPrompts,
                windowStartMinute: Int = ResearchStudy.defaultWindow.start,
                windowEndMinute: Int = ResearchStudy.defaultWindow.end,
                timeZone: TimeZone = .current, stoppedAt: Date? = nil) {
        let window = Self.normalizedWindow(start: windowStartMinute, end: windowEndMinute)
        self.id = id
        self.startedAt = startedAt
        self.days = min(max(days, Self.dayRange.lowerBound), Self.dayRange.upperBound)
        self.promptsPerDay = min(max(promptsPerDay, Self.promptRange.lowerBound), Self.promptRange.upperBound)
        self.windowStartMinute = window.start
        self.windowEndMinute = window.end
        self.timeZone = timeZone
        self.stoppedAt = stoppedAt
    }

    /// Keeps at least two hours between start and end, inside 00:00–24:00.
    public static func normalizedWindow(start: Int, end: Int) -> (start: Int, end: Int) {
        let start = min(max(start, 0), 22 * 60)
        let end = min(max(end, start + 120), 24 * 60)
        return (start, end)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The first instant after the last study day.
    public var scheduledEnd: Date {
        let first = calendar.startOfDay(for: startedAt)
        return calendar.date(byAdding: .day, value: days, to: first) ?? first.addingTimeInterval(Double(days) * 86_400)
    }

    /// When sampling stops: the end of the last day, or an earlier manual stop.
    public var end: Date { min(stoppedAt ?? scheduledEnd, scheduledEnd) }

    public func isActive(at date: Date) -> Bool { date >= startedAt && date < end }

    /// 1-based study day for a date, or nil outside the study.
    public func dayNumber(at date: Date) -> Int? {
        guard date >= startedAt, date < scheduledEnd else { return nil }
        let first = calendar.startOfDay(for: startedAt)
        let day = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: date)).day ?? 0
        return day + 1
    }

    /// Every check-in from the start of the study through `date`, in time order.
    public func prompts(through date: Date) -> [ResearchPrompt] {
        let last = min(date, end)
        guard last > startedAt else { return [] }
        return allPrompts().filter { $0.date <= last }
    }

    /// The full schedule, excluding times before the study started or after a manual stop.
    public func allPrompts() -> [ResearchPrompt] {
        let first = calendar.startOfDay(for: startedAt)
        var result: [ResearchPrompt] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            result += prompts(onDay: day, number: offset + 1)
        }
        return result.filter { $0.date >= startedAt && $0.date < end }
    }

    /// Stratified random times: the window is split into equal blocks and each check-in
    /// lands in the middle 80% of its block, so two check-ins are never too close.
    private func prompts(onDay day: Date, number: Int) -> [ResearchPrompt] {
        guard let windowStart = time(minute: windowStartMinute, on: day),
              let windowEnd = time(minute: windowEndMinute, on: day), windowEnd > windowStart else { return [] }
        let block = windowEnd.timeIntervalSince(windowStart) / Double(promptsPerDay)
        var random = SplitMix64(seed: seed(day: number))
        let dayID = DailyEvent.dayID(for: day.addingTimeInterval(12 * 3600), in: timeZone)
        return (0..<promptsPerDay).map { index in
            let fraction = 0.1 + 0.8 * random.nextUnit()
            let date = windowStart.addingTimeInterval(block * (Double(index) + fraction)).rounded(toSeconds: 60)
            return ResearchPrompt(key: "\(id.uuidString)/\(dayID)/\(index + 1)", day: number,
                                  slot: index + 1, slots: promptsPerDay, date: date)
        }
    }

    private func time(minute: Int, on day: Date) -> Date? {
        if minute >= 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: day) }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
    }

    private func seed(day: Int) -> UInt64 {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let high = bytes[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = bytes[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return high ^ (low &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(day) &* 0xBF58_476D_1CE4_E5B9)
    }
}

public struct ResearchPrompt: Equatable, Sendable {
    /// Stable across relaunches: study, local day and slot.
    public let key: String
    public let day: Int
    public let slot: Int
    public let slots: Int
    public let date: Date

    public init(key: String, day: Int, slot: Int, slots: Int, date: Date) {
        self.key = key
        self.day = day
        self.slot = slot
        self.slots = slots
        self.date = date
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A uniform value in [0, 1).
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

private extension Date {
    func rounded(toSeconds seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / seconds).rounded() * seconds)
    }
}
