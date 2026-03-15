import SwiftUI

enum AppTheme {
    static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
            : UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1)
    })
    static let cardBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 0.94)
            : UIColor(white: 1.0, alpha: 0.9)
    })
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.18, blue: 0.22, alpha: 1)
            : UIColor(white: 1.0, alpha: 0.84)
    })
    static let elevatedSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.21, blue: 0.25, alpha: 1)
            : UIColor(white: 1.0, alpha: 0.76)
    })
    static let mutedFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.08)
            : UIColor(white: 0.0, alpha: 0.05)
    })
    static let primaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            : UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
    })
    static let secondaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.66, green: 0.68, blue: 0.73, alpha: 1)
            : UIColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
    })
    static let accent = Color(red: 0.20, green: 0.45, blue: 0.76)
    static let accentSoft = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.24, blue: 0.34, alpha: 1)
            : UIColor(red: 0.86, green: 0.91, blue: 0.97, alpha: 1)
    })
    static let mealLoggedBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.28, blue: 0.20, alpha: 1)
            : UIColor(red: 0.85, green: 0.93, blue: 0.84, alpha: 1)
    })
    static let sunriseAccent = Color(red: 0.86, green: 0.56, blue: 0.16)
    static let sleepAccent = Color(red: 0.45, green: 0.54, blue: 0.88)
    static let wakeAccent = Color(red: 0.90, green: 0.66, blue: 0.26)
    static let showerAccent = Color(red: 0.30, green: 0.63, blue: 0.80)
    static let warning = Color(red: 0.83, green: 0.30, blue: 0.28)
    static let border = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.08)
            : UIColor(white: 0.0, alpha: 0.06)
    })
    static let shadow = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.0, alpha: 0.3)
            : UIColor(white: 0.0, alpha: 0.07)
    })
    static let actionFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.28, blue: 0.38, alpha: 1)
            : UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
    })
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow, radius: 6, x: 0, y: 2)
    }
}

extension View {
    func appCardStyle() -> some View {
        modifier(CardModifier())
    }

    func sectionStyle() -> some View {
        self.padding(.vertical, 4)
    }
}
