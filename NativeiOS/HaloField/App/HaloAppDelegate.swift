import UIKit

extension Notification.Name {
    static let haloAPNSDeviceToken = Notification.Name("halo.apns.device-token")
    static let haloAPNSRegistrationFailed = Notification.Name("halo.apns.registration-failed")
}

final class HaloAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .haloAPNSDeviceToken, object: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .haloAPNSRegistrationFailed,
            object: error.localizedDescription
        )
    }
}
