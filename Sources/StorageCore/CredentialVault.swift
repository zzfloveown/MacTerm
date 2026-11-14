import Domain
import Foundation
import Security

/// Keychain 使用应用服务名与资源 UUID 隔离凭据。
public enum CredentialVault {
    private static func query(_ host: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.macterm.app.ssh",
         kSecAttrAccount as String: host.uuidString]
    }

    public static func store(_ value: Data, for host: UUID) throws {
        let key = query(host)
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = key
            entry[kSecValueData as String] = value
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(entry as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    public static func read(_ host: UUID) throws -> Data? {
        var key = query(host)
        key[kSecReturnData as String] = true
        key[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(key as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    public static func delete(_ host: UUID) throws {
        let status = SecItemDelete(query(host) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw MacTermError("Keychain 操作失败（\(status)）") }
    }
}
