import SwiftUI
import UIKit

/// Exact palette sampled from HALO's approved 84-screen Figma library.
/// Scope this palette to the new marketplace: existing field-operation screens
/// retain their original dark HaloTheme until their separate designs are ported.
enum HaloMarketplaceDesign {
    static let pearl = Color(red: 247/255, green: 249/255, blue: 252/255)
    static let ink = Color(red: 20/255, green: 32/255, blue: 49/255)
    static let midnight = Color(red: 21/255, green: 35/255, blue: 56/255)
    static let slate = Color(red: 101/255, green: 116/255, blue: 137/255)
    static let steelBlue = Color(red: 65/255, green: 106/255, blue: 154/255)
    static let earningGreen = Color(red: 24/255, green: 125/255, blue: 102/255)
    static let mapCanvas = Color(red: 232/255, green: 238/255, blue: 233/255)
    static let border = Color(red: 227/255, green: 233/255, blue: 240/255)
    static let white = Color.white

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Inter is the Figma source font. Apple's native system font is used
        // until the licensed Inter weights are installed in the iOS target.
        .system(size: size, weight: weight, design: .default)
    }
}

/// The Figma screens use the ORIGINAL HALO silver wing, not a drawn proxy.
/// Its exact PNG bytes are committed in HALOWing.imageset from the approved
/// branded-design artifact; no temporary Figma URL or substitute is used.
struct HaloMarketplaceWing: View {
    var body: some View {
        Group {
            if UIImage(named: "HALOWing") != nil {
                Image("HALOWing")
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: 35, height: 20)
        .accessibilityLabel("HALO")
    }
}

struct HaloMarketplacePill: View {
    let title: String
    var selected: Bool = false

    var body: some View {
        Text(title)
            .font(HaloMarketplaceDesign.font(12, weight: .semibold))
            .foregroundStyle(selected ? .white : HaloMarketplaceDesign.ink)
            .padding(.horizontal, 15)
            .frame(minHeight: 36)
            .background(
                selected ? HaloMarketplaceDesign.midnight : .white,
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(
                    selected ? Color.clear : HaloMarketplaceDesign.border,
                    lineWidth: 1
                )
            }
    }
}

struct HaloMarketplacePrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(HaloMarketplaceDesign.font(15, weight: .semibold))
                Image(systemName: "arrow.right")
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(minHeight: 54)
            .background(
                enabled ? HaloMarketplaceDesign.midnight : HaloMarketplaceDesign.slate,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}
