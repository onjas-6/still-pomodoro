import Foundation

/// A revision to a day's commitment or a focus timer explicitly stopped early.
/// Completed timers keep their original FocusSession representation and identifiers.
public struct DailyEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case goal(Int)
        case stopped(startedAt: Date)
    }

    public let id: UUID
    public let kind: Kind
    // Keep sub-second ordering for edits even in the ISO-8601 recovery archive.
    private let timestamp: TimeInterval
    public let timeZone: TimeZone
    public var date: Date { Date(timeIntervalSince1970: timestamp) }
    public static let goalRange = 0...99

    public init(_ kind: Kind, at date: Date, id: UUID = UUID(), timeZone: TimeZone = .current) {
        self.kind = kind
        self.id = id
        self.timestamp = date.timeIntervalSince1970
        self.timeZone = timeZone
    }

    public static func dayID(for date: Date, in zone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

public struct JournalEntries: Sendable {
    public var sessions: [FocusSession]
    public var events: [DailyEvent]
    public var notes: [StillNote]

    public init(sessions: [FocusSession] = [], events: [DailyEvent] = [], notes: [StillNote] = []) {
        self.sessions = sessions
        self.events = events
        self.notes = notes
    }

    public var isEmpty: Bool { sessions.isEmpty && events.isEmpty && notes.isEmpty }

    public func missing(from existing: JournalEntries) -> JournalEntries {
        var sessionIDs = Set(existing.sessions.map(\.id))
        var eventIDs = Set(existing.events.map(\.id))
        var noteIDs = Set(existing.notes.map(\.id))
        return JournalEntries(sessions: sessions.filter { sessionIDs.insert($0.id).inserted },
                              events: events.filter { eventIDs.insert($0.id).inserted },
                              notes: notes.filter { noteIDs.insert($0.id).inserted })
    }

    public mutating func append(_ missing: JournalEntries) {
        sessions.append(contentsOf: missing.sessions)
        events.append(contentsOf: missing.events)
        notes.append(contentsOf: missing.notes)
    }
}
