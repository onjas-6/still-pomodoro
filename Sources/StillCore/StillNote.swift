// Created 2026-11-27 · Claude Code
import Foundation

/// A small, self-describing journal record for features added after focus sessions and
/// daily events. Readers that predate notes ignore the `still-note:` marker, and current
/// readers skip a note they cannot decode instead of rejecting the whole journal.
public struct StillNote: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// A dotted name such as `research.check-in`.
    public let kind: String
    private let timestamp: TimeInterval
    public let timeZone: TimeZone
    /// One readable line for the Markdown row.
    public let summary: String
    /// Flat string fields keep the format forward-compatible and easy to analyze.
    public let fields: [String: String]

    public var date: Date { Date(timeIntervalSince1970: timestamp) }

    public init(kind: String, at date: Date, summary: String, fields: [String: String] = [:],
                id: UUID = UUID(), timeZone: TimeZone = .current) {
        self.id = id
        self.kind = kind
        self.timestamp = date.timeIntervalSince1970
        self.timeZone = timeZone
        self.summary = summary
        self.fields = fields
    }

    public subscript(field: String) -> String? { fields[field] }

    /// A single Markdown-safe line: no line breaks and no HTML comment delimiters.
    public var markdownSummary: String {
        let flattened = summary.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "<!--", with: "<!—")
            .replacingOccurrences(of: "-->", with: "—>")
            .trimmingCharacters(in: .whitespaces)
        return flattened.count > 400 ? String(flattened.prefix(399)) + "…" : flattened
    }
}
