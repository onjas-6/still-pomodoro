// Created 2026-09-15 · gpt-6-astra · Codex
import SwiftUI

struct Palette {
    let background: Color
    let ink: Color
    let secondary: Color
    let accent: Color
    let wash: Color
    let progress: Color

    static func resolved(theme: String, scheme: ColorScheme, colorTheme: String = "sage") -> Palette {
        let choice = ColorTheme.all.first { $0.id == colorTheme } ?? ColorTheme.all[0]
        return theme == "dark" || (theme != "light" && scheme == .dark) ? choice.dark : choice.light
    }

    static func colors(_ background: UInt32, _ ink: UInt32, _ secondary: UInt32, _ accent: UInt32, _ wash: UInt32) -> Palette {
        Palette(background: Color(hex: background), ink: Color(hex: ink), secondary: Color(hex: secondary),
                accent: Color(hex: accent), wash: Color(hex: wash), progress: Color(hex: accent))
    }
}

struct ColorTheme: Identifiable {
    let id: String
    let name: String
    let swatch: UInt32
    let light: Palette
    let dark: Palette

    static let all: [ColorTheme] = [
        ColorTheme(id: "sage", name: "Sage", swatch: 0x8DA18B,
                   light: .colors(0xF1F4EC, 0x34483D, 0x6A7E70, 0x738D72, 0xDCE8D8),
                   dark: .colors(0x242D26, 0xEBF1E7, 0xA6B5A0, 0xB7CCAD, 0x435440)),
        ColorTheme(id: "ocean", name: "Ocean", swatch: 0x7EA9C2,
                   light: .colors(0xF0F5F8, 0x28495E, 0x627F91, 0x5D91AF, 0xD9E8F1),
                   dark: .colors(0x172B37, 0xE0F0F8, 0x97B5C8, 0x98CBE1, 0x294858)),
        ColorTheme(id: "lavender", name: "Lavender", swatch: 0xAD98C7,
                   light: .colors(0xF5F1FA, 0x4E4163, 0x887997, 0x9B84B6, 0xE6DCF1),
                   dark: .colors(0x2B2536, 0xF0E9FA, 0xBDB0CE, 0xC6ACDF, 0x494056)),
        ColorTheme(id: "rose", name: "Rose", swatch: 0xC298A8,
                   light: .colors(0xF8F0F3, 0x633F4D, 0x997685, 0xB17C92, 0xF0DBE3),
                   dark: .colors(0x34252C, 0xFAE7EE, 0xCEABB8, 0xE0A8BF, 0x59414A)),
        ColorTheme(id: "sand", name: "Sand", swatch: 0xBAA77D,
                   light: .colors(0xF7F3E9, 0x594F3A, 0x91846A, 0xA58F5C, 0xEDE3CA),
                   dark: .colors(0x2E2A20, 0xF4EDD8, 0xC2B699, 0xD9C58F, 0x4D4531)),
        ColorTheme(id: "clay", name: "Clay", swatch: 0xC49C82,
                   light: .colors(0xF9F0E9, 0x624638, 0x9E7E6D, 0xB8866B, 0xF0DCCF),
                   dark: .colors(0x35271F, 0xF8EADC, 0xD1AF96, 0xDFA681, 0x594131)),
        ColorTheme(id: "graphite", name: "Graphite", swatch: 0x8E9BA6,
                   light: .colors(0xF3F4F4, 0x3D444A, 0x7C858D, 0x798792, 0xE0E4E7),
                   dark: .colors(0x272B30, 0xEBEFF3, 0xA9B3BF, 0xBECBD6, 0x434B55)),
        ColorTheme(id: "mint", name: "Mint", swatch: 0x85B6A4,
                   light: .colors(0xEFF7F4, 0x2E514B, 0x648C81, 0x63A18B, 0xD8ECE4),
                   dark: .colors(0x20312B, 0xE3F5EC, 0x9DBFAE, 0x96CFB5, 0x365447))
    ]
}
