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
    static let accent = Color(red: 0.22, green: 0.44, blue: 0.72)
    static let accentSoft = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.22, blue: 0.32, alpha: 1)
            : UIColor(red: 0.88, green: 0.92, blue: 0.97, alpha: 1)
    })
    static let travelBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1)
            : UIColor(red: 0.93, green: 0.96, blue: 0.95, alpha: 1)
    })
    static let travelSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.16, blue: 0.18, alpha: 1)
            : UIColor(red: 0.98, green: 0.99, blue: 0.98, alpha: 0.92)
    })
    static let travelElevatedSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.19, blue: 0.21, alpha: 1)
            : UIColor(red: 0.88, green: 0.93, blue: 0.92, alpha: 1)
    })
    static let travelAccent = Color(red: 0.18, green: 0.44, blue: 0.41)
    static let travelAccentSoft = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.23, blue: 0.22, alpha: 1)
            : UIColor(red: 0.82, green: 0.90, blue: 0.88, alpha: 1)
    })
    static let travelBorder = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.72, green: 0.82, blue: 0.80, alpha: 0.12)
            : UIColor(red: 0.18, green: 0.44, blue: 0.41, alpha: 0.16)
    })
    static let mealLoggedBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.26, blue: 0.19, alpha: 1)
            : UIColor(red: 0.88, green: 0.94, blue: 0.87, alpha: 1)
    })
    static let sunriseAccent = Color(red: 0.84, green: 0.58, blue: 0.22)
    static let sleepAccent = Color(red: 0.40, green: 0.50, blue: 0.84)
    static let wakeAccent = Color(red: 0.88, green: 0.64, blue: 0.24)
    static let showerAccent = Color(red: 0.28, green: 0.60, blue: 0.76)
    static let bowelAccent = Color(red: 0.56, green: 0.44, blue: 0.30)
    static let sexualAccent = Color(red: 0.78, green: 0.40, blue: 0.52)
    static let warning = Color(red: 0.80, green: 0.28, blue: 0.26)
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
