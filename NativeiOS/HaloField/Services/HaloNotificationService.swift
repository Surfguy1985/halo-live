import Foundation
import UserNotifications
import UIKit

@MainActor
final class HaloNotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var remoteRegistrationError: String?

    private let tokenKey = "halo.apns.device-token"

    var deviceToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    init() {
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await refreshAuthorization()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    func scheduleLocalReminder(
        id: String,
        title: String,
        body: String,
        after seconds: TimeInterval
    ) async {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(seconds, 1),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    func handleDeviceToken(_ token: String, activationToken: String?) async {
        UserDefaults.standard.set(token, forKey: tokenKey)
        remoteRegistrationError = nil
        guard let activationToken, !activationToken.isEmpty else { return }

        do {
            try await HaloAPI.shared.registerNativeDevice(
                deviceToken: token,
                activationToken: activationToken
            )
        } catch {
            remoteRegistrationError = error.localizedDescription
        }
    }

    func syncRemoteDevice(activationToken: String?) async {
        guard let token = deviceToken,
              let activationToken,
              !activationToken.isEmpty else { return }

        do {
            try await HaloAPI.shared.registerNativeDevice(
                deviceToken: token,
                activationToken: activationToken
            )
            remoteRegistrationError = nil
        } catch {
            remoteRegistrationError = error.localizedDescription
        }
    }

    func unregisterRemoteDevice(activationToken: String?) async {
        guard let token = deviceToken,
              let activationToken,
              !activationToken.isEmpty else {
            UserDefaults.standard.removeObject(forKey: tokenKey)
            return
        }

        do {
            try await HaloAPI.shared.unregisterNativeDevice(
                deviceToken: token,
                activationToken: activationToken
            )
        } catch {
            remoteRegistrationError = error.localizedDescription
        }

        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    func clearDelivered() async {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
