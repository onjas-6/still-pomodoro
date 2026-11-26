import Foundation

enum AlertTone: String, CaseIterable, Codable, Identifiable {
    case stillChime
    case feltPiano
    case kalimba
    case glass
    case wood
    case tink

    var id: Self { self }

    var displayName: String {
        switch self {
        case .stillChime: "Still chime"
        case .feltPiano: "Felt piano"
        case .kalimba: "Kalimba"
        case .glass: "Glass bell"
        case .wood: "Wood block"
        case .tink: "Soft tap"
        }
    }

    /// `nil` denotes the macOS-provided Tink sound rather than an app bundle resource.
    var resourceName: String? {
        switch self {
        case .stillChime: "StillChime"
        case .feltPiano: "StillFeltPiano"
        case .kalimba: "StillKalimba"
        case .glass: "StillGlass"
        case .wood: "StillWood"
        case .tink: nil
        }
    }

    /// Timer sounds must be bundled so notifications can play them after Still quits.
    static var timerChoices: [Self] { allCases.filter { $0.resourceName != nil } }
}
