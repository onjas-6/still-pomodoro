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
    var colorTheme: String
    var edgeStyle: String
    var compactScale: Double
    var backgroundOpacity: Double
    var journalPath: String
    var restReminderEnabled: Bool
    var restStartMinute: Int
    var restEndMinute: Int
    var restMessage: String

    init(
        focusMinutes: Int = 30,
        focusPresets: [Int] = Preferences.defaultFocusPresets,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        soundEnabled: Bool = true,
        notificationsEnabled: Bool = true,
        floatOnTop: Bool = true,
        theme: String = "system",
        colorTheme: String = "sage",
        edgeStyle: String = "glass",
        compactScale: Double = 1,
        backgroundOpacity: Double = 0.5,
        journalPath: String = "",
        restReminderEnabled: Bool = true,
        restStartMinute: Int = 0,
        restEndMinute: Int = 8 * 60,
        restMessage: String = "我是高执行力、高精力的人。现在休息，明天更清醒地行动。"
    ) {
        self.focusMinutes = Self.clamp(focusMinutes, to: 1...180)
        self.focusPresets = Self.normalizedFocusPresets(focusPresets)
        self.shortBreakMinutes = Self.clamp(shortBreakMinutes, to: 1...60)
        self.longBreakMinutes = Self.clamp(longBreakMinutes, to: 1...90)
        self.soundEnabled = soundEnabled
        self.notificationsEnabled = notificationsEnabled
        self.floatOnTop = floatOnTop
        self.theme = Self.normalizedTheme(theme)
        self.colorTheme = Self.normalizedColorTheme(colorTheme)
        self.edgeStyle = Self.normalizedEdgeStyle(edgeStyle)
        self.compactScale = Self.clamp(compactScale, to: Self.compactScaleRange)
        self.backgroundOpacity = Self.clamp(backgroundOpacity, to: 0.15...0.9)
        self.journalPath = journalPath
        self.restReminderEnabled = restReminderEnabled
        self.restStartMinute = Self.clamp(restStartMinute, to: 0...1439)
        self.restEndMinute = Self.clamp(restEndMinute, to: 0...1439)
        self.restMessage = Self.normalizedRestMessage(restMessage)
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
        case colorTheme
        case edgeStyle
        case compactScale
        case backgroundOpacity
        case journalPath
        case restReminderEnabled
        case restStartMinute
        case restEndMinute
        case restMessage
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
            colorTheme: try container.decodeIfPresent(String.self, forKey: .colorTheme) ?? defaults.colorTheme,
            edgeStyle: try container.decodeIfPresent(String.self, forKey: .edgeStyle) ?? defaults.edgeStyle,
            compactScale: try container.decodeIfPresent(Double.self, forKey: .compactScale) ?? defaults.compactScale,
            backgroundOpacity: try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? defaults.backgroundOpacity,
            journalPath: try container.decodeIfPresent(String.self, forKey: .journalPath) ?? defaults.journalPath,
            restReminderEnabled: try container.decodeIfPresent(Bool.self, forKey: .restReminderEnabled) ?? defaults.restReminderEnabled,
            restStartMinute: try container.decodeIfPresent(Int.self, forKey: .restStartMinute) ?? defaults.restStartMinute,
            restEndMinute: try container.decodeIfPresent(Int.self, forKey: .restEndMinute) ?? defaults.restEndMinute,
            restMessage: try container.decodeIfPresent(String.self, forKey: .restMessage) ?? defaults.restMessage
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
        try container.encode(Self.normalizedColorTheme(colorTheme), forKey: .colorTheme)
        try container.encode(Self.normalizedEdgeStyle(edgeStyle), forKey: .edgeStyle)
        try container.encode(Self.clamp(compactScale, to: Self.compactScaleRange), forKey: .compactScale)
        try container.encode(Self.clamp(backgroundOpacity, to: 0.15...0.9), forKey: .backgroundOpacity)
        try container.encode(journalPath, forKey: .journalPath)
        try container.encode(restReminderEnabled, forKey: .restReminderEnabled)
        try container.encode(Self.clamp(restStartMinute, to: 0...1439), forKey: .restStartMinute)
        try container.encode(Self.clamp(restEndMinute, to: 0...1439), forKey: .restEndMinute)
        try container.encode(Self.normalizedRestMessage(restMessage), forKey: .restMessage)
    }

    mutating func sanitize() {
        focusMinutes = Self.clamp(focusMinutes, to: 1...180)
        focusPresets = Self.normalizedFocusPresets(focusPresets)
        shortBreakMinutes = Self.clamp(shortBreakMinutes, to: 1...60)
        longBreakMinutes = Self.clamp(longBreakMinutes, to: 1...90)
        theme = Self.normalizedTheme(theme)
        colorTheme = Self.normalizedColorTheme(colorTheme)
        edgeStyle = Self.normalizedEdgeStyle(edgeStyle)
        compactScale = Self.clamp(compactScale, to: Self.compactScaleRange)
        backgroundOpacity = Self.clamp(backgroundOpacity, to: 0.15...0.9)
        restStartMinute = Self.clamp(restStartMinute, to: 0...1439)
        restEndMinute = Self.clamp(restEndMinute, to: 0...1439)
        restMessage = Self.normalizedRestMessage(restMessage)
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

    private static func normalizedColorTheme(_ value: String) -> String {
        switch value.lowercased() {
        case "sage", "ocean", "lavender", "rose", "sand", "clay", "graphite", "mint": return value.lowercased()
        default: return "sage"
        }
    }

    private static func normalizedEdgeStyle(_ value: String) -> String {
        switch value.lowercased() {
        case "glass", "diffuse": return value.lowercased()
        default: return "glass"
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

    private static func normalizedRestMessage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "我是高执行力、高精力的人。现在休息，明天更清醒地行动。" : String(trimmed.prefix(60))
    }
}
