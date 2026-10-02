import Foundation

enum HaloBuildStamp {
    // Human-visible native release fingerprint. Keep this distinct from the
    // App Store marketing/build version so stale simulator/Xcode builds are obvious.
    static let revision = "NATIVE-LIVE-STABILITY-R7"
}
