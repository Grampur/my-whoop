import SwiftUI

/// Supported manual workout tags. Raw value = the string stored in the DB `kind` column.
enum WorkoutType: String, CaseIterable, Identifiable {
    case golf          = "golf"
    case poker         = "poker"
    case weightlifting = "weightlifting"
    case cardio        = "cardio"
    case stairmaster   = "stairmaster"
    case swimming      = "swimming"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .golf:          return "Golf"
        case .poker:         return "Poker"
        case .weightlifting: return "Weightlifting"
        case .cardio:        return "Cardio / Walking"
        case .stairmaster:   return "Stairmaster"
        case .swimming:      return "Swimming"
        }
    }

    var icon: String {
        switch self {
        case .golf:          return "figure.golf"
        case .poker:         return "suit.spade.fill"
        case .weightlifting: return "dumbbell.fill"
        case .cardio:        return "figure.walk"
        case .stairmaster:   return "figure.stair.stepper"
        case .swimming:      return "figure.pool.swim"
        }
    }

    var color: Color {
        switch self {
        case .golf:          return Color(hex: "#4CAF50")
        case .poker:         return Color(hex: "#9C27B0")
        case .weightlifting: return Color(hex: "#FF5722")
        case .cardio:        return Color(hex: "#03A9F4")
        case .stairmaster:   return Color(hex: "#FF9800")
        case .swimming:      return Color(hex: "#00BCD4")
        }
    }

    /// Init from the raw DB string; nil if unrecognised.
    init?(kind: String?) {
        guard let k = kind else { return nil }
        self.init(rawValue: k)
    }
}
