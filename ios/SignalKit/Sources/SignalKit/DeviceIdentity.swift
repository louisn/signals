import Foundation
import Security

/// A stable per-device UUID persisted in the Keychain so it survives app
/// reinstall (deliberately *not* synced to iCloud Keychain — this is a
/// physical-device identity, not something that should follow the user
/// across devices).
public enum DeviceIdentity {
    private static let service = "com.signals.deviceIdentity"
    private static let account = "device_id"

    public static func currentDeviceID() -> UUID {
        if let existing = readFromKeychain() {
            return existing
        }
        let generated = UUID()
        writeToKeychain(generated)
        return generated
    }

    /// Adopts a backend-minted device ID (from QR/deep-link provisioning),
    /// replacing the self-generated one. The batch device_id is read live at
    /// upload time, so already-queued rows simply upload under the new identity.
    public static func setCurrentDeviceID(_ id: UUID) {
        writeToKeychain(id)
    }

    private static func readFromKeychain() -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: string) else {
            return nil
        }
        return uuid
    }

    private static func writeToKeychain(_ id: UUID) {
        let data = Data(id.uuidString.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
