import SwiftUI

/// How a month's standing looks. Gathered in one place because the same
/// judgement is drawn three times — on the panel, in the settings window and in
/// the menu bar — and three copies of a ternary are three chances for them to
/// drift apart and say different things about the same month.
extension Budget.Level {
    var systemImage: String {
        switch self {
        case .fine, .approaching: "chart.pie"
        case .over: "exclamationmark.triangle.fill"
        }
    }

    /// Orange rather than red: the limit is soft and the correction still
    /// happened. Red is for something that failed.
    var tint: Color {
        switch self {
        case .fine: .primary
        case .approaching: .secondary
        case .over: .orange
        }
    }
}
