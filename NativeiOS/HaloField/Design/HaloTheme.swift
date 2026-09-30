import SwiftUI

enum HaloTheme {
    static let ink = Color(red: 8/255, green: 13/255, blue: 26/255)
    static let paper = Color(red: 246/255, green: 247/255, blue: 244/255)
    static let lime = Color(red: 180/255, green: 1, blue: 68/255)
    static let gold = Color(red: 227/255, green: 184/255, blue: 92/255)
    static let muted = Color.black.opacity(0.52)
    static let hairline = Color.black.opacity(0.08)

    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18
    static let horizontal: CGFloat = 20
}

struct HaloCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: HaloTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HaloTheme.cardRadius, style: .continuous)
                    .stroke(HaloTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }
}

extension View {
    func haloCard() -> some View { modifier(HaloCardModifier()) }
}
