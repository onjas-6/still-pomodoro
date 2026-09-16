// Created 2026-09-15 · gpt-5.6-terra · Codex
import Foundation
import SwiftUI

struct Preferences: Codable {
    static let defaultFocusPresets = [30, 45, 60]
    static let compactScaleRange = 0.8...3.0

    var focusMinutes: Int
    var focusPresets: [Int]
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var soundEnabled: Bool
    var notificationsEnabled: Bool
    var floatOnTop: Bool
    var theme: String
    var compactScale: Double
    var backgroundOpacity: Double
    var journalPath: String

    init(
        focusMinutes: Int = 30,
        focusPresets: [Int] = Preferences.defaultFocusPresets,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        soundEnabled: Bool = true,
        notificationsEnabled: Bool = true,
        floatOnTop: Bool = true,
        theme: String = "system",
        compactScale: Double = 1,
        backgroundOpacity: Double = 0.5,
        journalPath: String = ""
    ) {
        self.focusMinutes = Self.clamp(focusMinutes, to: 1...180)
        self.focusPresets = Self.normalizedFocusPresets(focusPresets)
        self.shortBreakMinutes = Self.clamp(shortBreakMinutes, to: 1...60)
        self.longBreakMinutes = Self.clamp(longBreakMinutes, to: 1...90)
        self.soundEnabled = soundEnabled
        self.notificationsEnabled = notificationsEnabled
        self.floatOnTop = floatOnTop
        self.theme = Self.normalizedTheme(theme)
        self.compactScale = Self.clamp(compactScale, to: Self.compactScaleRange)
        self.backgroundOpacity = Self.clamp(backgroundOpacity, to: 0.15...0.9)
        self.journalPath = journalPath
    }

    enum CodingKeys: String, CodingKey {
        case focusMinutes
        case focusPresets
        case shortBreakMinutes
        case longBreakMinutes
        case soundEnabled
        case notificationsEnabled
        case floatOnTop
        case theme
        case compactScale
        case backgroundOpacity
        case journalPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        self.init(
            focusMinutes: try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? defaults.focusMinutes,
            focusPresets: try container.decodeIfPresent([Int].self, forKey: .focusPresets) ?? defaults.focusPresets,
            shortBreakMinutes: try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? defaults.shortBreakMinutes,
            longBreakMinutes: try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? defaults.longBreakMinutes,
            soundEnabled: try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? defaults.soundEnabled,
            notificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled,
            floatOnTop: try container.decodeIfPresent(Bool.self, forKey: .floatOnTop) ?? defaults.floatOnTop,
            theme: try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme,
            compactScale: try container.decodeIfPresent(Double.self, forKey: .compactScale) ?? defaults.compactScale,
            backgroundOpacity: try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? defaults.backgroundOpacity,
            journalPath: try container.decodeIfPresent(String.self, forKey: .journalPath) ?? defaults.journalPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focusMinutes, forKey: .focusMinutes)
        try container.encode(Self.normalizedFocusPresets(focusPresets), forKey: .focusPresets)
        try container.encode(shortBreakMinutes, forKey: .shortBreakMinutes)
        try container.encode(longBreakMinutes, forKey: .longBreakMinutes)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(floatOnTop, forKey: .floatOnTop)
        try container.encode(Self.normalizedTheme(theme), forKey: .theme)
        try container.encode(Self.clamp(compactScale, to: Self.compactScaleRange), forKey: .compactScale)
        try container.encode(Self.clamp(backgroundOpacity, to: 0.15...0.9), forKey: .backgroundOpacity)
        try container.encode(journalPath, forKey: .journalPath)
    }

    mutating func sanitize() {
        focusMinutes = Self.clamp(focusMinutes, to: 1...180)
        focusPresets = Self.normalizedFocusPresets(focusPresets)
        shortBreakMinutes = Self.clamp(shortBreakMinutes, to: 1...60)
        longBreakMinutes = Self.clamp(longBreakMinutes, to: 1...90)
        theme = Self.normalizedTheme(theme)
        compactScale = Self.clamp(compactScale, to: Self.compactScaleRange)
        backgroundOpacity = Self.clamp(backgroundOpacity, to: 0.15...0.9)
    }

    func preferredColorScheme() -> ColorScheme? {
        switch Self.normalizedTheme(theme) {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private static func normalizedTheme(_ value: String) -> String {
        switch value.lowercased() {
        case "light", "dark", "system": return value.lowercased()
        // v1 atmosphere values intentionally become a neutral system appearance.
        case "sage", "clay", "dusk": return "system"
        default: return "system"
        }
    }

    private static func normalizedFocusPresets(_ values: [Int]) -> [Int] {
        var normalized = Array(values.prefix(defaultFocusPresets.count))
        while normalized.count < defaultFocusPresets.count {
            normalized.append(defaultFocusPresets[normalized.count])
        }
        return normalized.map { clamp($0, to: 1...180) }
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
