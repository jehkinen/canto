import Foundation
import Security

/// The OpenAI API key in the login keychain.
enum KeychainStore {
    private static let service = "io.github.jehkinen.canto"
    private static let account = "openai-api-key"

    /// A keychain entry that looks like it holds an OpenAI key, saved by some other app or tool.
    struct FoundItem: Identifiable, Hashable {
        let id: Data
        let title: String
        let account: String
    }

    /// Checks for the item without reading its secret, so no keychain prompt appears.
    static func hasAPIKey() -> Bool {
        var query = baseQuery(service: service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadAPIKey() -> String? {
        read(service: service)
    }

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(baseQuery(service: service) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(service: service)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Canto OpenAI API key"
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    /// Generic passwords whose service, account or label mentions OpenAI. Only attributes are
    /// read, so the search itself never asks for keychain access.
    static func findOpenAIKeyItems() -> [FoundItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnPersistentRef as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { attributes in
            let itemService = attributes[kSecAttrService as String] as? String ?? ""
            let itemAccount = attributes[kSecAttrAccount as String] as? String ?? ""
            let label = attributes[kSecAttrLabel as String] as? String ?? ""
            guard itemService != service, let reference = attributes[kSecValuePersistentRef as String] as? Data else { return nil }
            let text = [itemService, itemAccount, label].joined(separator: " ").lowercased()
            guard text.contains("openai") || text.contains("open ai") || text.contains("chatgpt") else { return nil }
            return FoundItem(id: reference, title: label.isEmpty ? itemService : label, account: itemAccount)
        }
    }

    /// Reads the secret of a found item. macOS asks the user to allow access to it.
    static func readSecret(of item: FoundItem) -> String? {
        let query: [String: Any] = [
            kSecValuePersistentRef as String: item.id,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func read(service: String) -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
