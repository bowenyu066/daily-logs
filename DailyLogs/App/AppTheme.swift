import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.97, green: 0.95, blue: 0.92)
    static let cardBackground = Color.white.opacity(0.9)
    static let primaryText = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let secondaryText = Color(red: 0.42, green: 0.42, blue: 0.45)
    static let accent = Color(red: 0.20, green: 0.45, blue: 0.76)
    static let accentSoft = Color(red: 0.86, green: 0.91, blue: 0.97)
    static let warning = Color(red: 0.79, green: 0.23, blue: 0.20)
    static let border = Color.black.opacity(0.06)
    static let shadow = Color.black.opacity(0.07)
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 18, x: 0, y: 12)
    }
}

extension View {
    func appCardStyle() -> some View {
        modifier(CardModifier())
    }
}
