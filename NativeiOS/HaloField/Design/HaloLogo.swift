import SwiftUI

struct HaloLogo: View {
    var height: CGFloat = 27
    private let logoURL = URL(string: "https://s3.amazonaws.com/webflow-prod-assets/6a8cb07e4b37c072a5e8f4ab/6a8cea388d371caeffbe91a4_halo-platform-logo.png")

    var body: some View {
        AsyncImage(url: logoURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            default:
                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill")
                    Text("HALO").font(HaloType.display(height * 0.72, weight: .bold))
                }.foregroundStyle(.white)
            }
        }
        .frame(width: height * 4, height: height)
        .accessibilityLabel("HALO Operations")
    }
}