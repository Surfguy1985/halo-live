import UIKit
import UserNotifications

extension Notification.Name {
    static let haloAPNSDeviceToken = Notification.Name("halo.apns.device-token")
    static let haloAPNSRegistrationFailed = Notification.Name("halo.apns.registration-failed")
    static let haloOpenJob = Notification.Name("halo.push.open-job")
    static let haloOpenComms = Notification.Name("halo.push.open-comms")
}

final class HaloAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: "HALO_OPEN", title: "Open in HALO", options: [.foreground])
        let message = UNNotificationCategory(identifier: "message", actions: [open], intentIdentifiers: [], options: [])
        let mention = UNNotificationCategory(identifier: "mention", actions: [open], intentIdentifiers: [], options: [])
        let gps = UNNotificationCategory(identifier: "gps_request", actions: [open], intentIdentifiers: [], options: [])
        center.setNotificationCategories([message, mention, gps])
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .haloAPNSDeviceToken, object: token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let halo = info["halo"] as? [String: Any]
        let unitID = (halo?["unitId"] as? String) ?? ""
        let channel = (halo?["channel"] as? String) ?? ""
        let category = (halo?["category"] as? String) ?? ""
        let deepLink = (halo?["deepLink"] as? String) ?? ""
        let gpsSession = URLComponents(string: deepLink)?
            .queryItems?
            .first(where: { $0.name == "gpsSession" })?
            .value ?? ""

        if category == "message" || category == "mention" || category == "gps_request" || !channel.isEmpty {
            NotificationCenter.default.post(
                name: .haloOpenComms,
                object: [
                    "unitId": unitID,
                    "channel": channel,
                    "category": category,
                    "gpsSession": gpsSession
                ]
            )
        } else if !unitID.isEmpty {
            NotificationCenter.default.post(name: .haloOpenJob, object: unitID)
        } else {
            NotificationCenter.default.post(name: .haloOpenComms, object: ["category": category])
        }
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
