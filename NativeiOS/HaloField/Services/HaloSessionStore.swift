import Foundation
import Security

@MainActor
final class HaloSessionStore: ObservableObject {
    @Published private(set) var activationToken: String? = nil

    private let service = "com.archangel.halofield"
    private let account = "crew-activation-token"

    init() {
        activationToken = readToken()
    }

    var isActivated: Bool {
        guard let token = activationToken else { return false }
        return !token.isEmpty
    }

    func activateValidated(token: String) async throws -> HaloActivationInfo {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 16 else {
            throw SessionError.invalidToken
        }

        let info = try await HaloAPI.shared.validateActivation(token: clean)
        try saveToken(clean)
        activationToken = clean
        return info
    }

    func deactivate() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        activationToken = nil
    }

    func handle(url: URL) async {
        guard url.scheme?.lowercased() == "halo",
              url.host?.lowercased() == "activate",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        else { return }

        _ = try? await activateValidated(token: token)
    }

    private func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { throw SessionError.invalidToken }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(base as CFDictionary)

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SessionError.keychain(status)
        }
    }

    private func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }

        return token
    }
}

enum SessionError: LocalizedError {
    case invalidToken
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "That HALO activation link is not valid."
        case .keychain: "HALO could not securely save this device activation."
        }
    }
}
