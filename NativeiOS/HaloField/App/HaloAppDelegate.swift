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
        let categories = [
            "message", "mention", "gps_request", "assignment", "rework",
            "change_order", "scope_approved", "po_received", "flag_decision",
            "urgent_dispatch", "field_update"
        ].map {
            UNNotificationCategory(identifier: $0, actions: [open], intentIdentifiers: [], options: [])
        }
        center.setNotificationCategories(Set(categories))
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
            let route = [
                "unitId": unitID,
                "channel": channel,
                "category": category,
                "gpsSession": gpsSession
            ]
            UserDefaults.standard.set(route, forKey: "halo.pending.push-route")
            NotificationCenter.default.post(name: .haloOpenComms, object: route)
        } else if !unitID.isEmpty {
            NotificationCenter.default.post(name: .haloOpenJob, object: unitID)
        } else {
            let route = ["category": category]
            UserDefaults.standard.set(route, forKey: "halo.pending.push-route")
            NotificationCenter.default.post(name: .haloOpenComms, object: route)
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
