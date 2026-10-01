import SwiftUI

enum HaloTheme {
    static let navy = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let ink = Color(red: 0.043, green: 0.051, blue: 0.071)
    static let lime = Color(red: 185/255, green: 1, blue: 102/255)
    static let limePressed = Color(red: 197/255, green: 1, blue: 128/255)
    static let actionBlue = Color(red: 23/255, green: 105/255, blue: 1)
    static let fieldBackground = Color(red: 7/255, green: 16/255, blue: 29/255)
    static let fieldChrome = Color(red: 9/255, green: 20/255, blue: 29/255)
    static let fieldCard = Color(red: 11/255, green: 24/255, blue: 34/255)
    static let fieldBorder = Color(red: 23/255, green: 51/255, blue: 71/255)
    static let fieldLive = Color(red: 53/255, green: 233/255, blue: 138/255)
    static let paper = Color(red: 0.957, green: 0.957, blue: 0.941)
    static let card = Color.white
    static let text = Color(red: 0.043, green: 0.051, blue: 0.071)
    static let secondaryText = Color(red: 102/255, green: 112/255, blue: 133/255)
    static let softBorder = Color(red: 224/255, green: 229/255, blue: 232/255)
    static let success = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let warning = Color(red: 1, green: 159/255, blue: 10/255)
    static let danger = Color(red: 1, green: 59/255, blue: 48/255)
    static let cardRadius: CGFloat = 20
    static let heroRadius: CGFloat = 24
    static let controlRadius: CGFloat = 14
    static let horizontal: CGFloat = 20
}

enum HaloType {
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func card(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum HaloMotion {
    static func animation(reduceMotion: Bool, duration: Double = 0.32) -> Animation? {
        reduceMotion ? nil : .snappy(duration: duration)
    }
}

struct HaloLightCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(HaloTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: HaloTheme.cardRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: HaloTheme.cardRadius, style: .continuous).stroke(HaloTheme.softBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.035), radius: 18, y: 8)
    }
}
struct HaloDarkCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HaloTheme.heroRadius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .background(HaloTheme.fieldCard.opacity(0.76), in: shape)
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.11), HaloTheme.fieldBorder.opacity(0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
    }
}

struct HaloPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.18),
                value: configuration.isPressed
            )
    }
}

extension View {
    func haloCard() -> some View { modifier(HaloLightCardModifier()) }
    func haloDarkCard() -> some View { modifier(HaloDarkCardModifier()) }
}