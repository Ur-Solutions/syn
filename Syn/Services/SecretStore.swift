import Foundation
import Security

struct SecretAvailability: Equatable, Sendable {
    var isAvailable: Bool
    var source: String

    var displayText: String {
        isAvailable ? "Available (\(source))" : "Missing"
    }
}

enum SecretStore {
    static func readAnthropicKey() -> String? {
        readKeychain(service: "Syn", account: "anthropic-api-key")
            ?? readHem(secret: "global/anthropic-api-key", key: nil)
    }

    static func readOpenAIKey() -> String? {
        readKeychain(service: "Syn", account: "openai-api-key")
            ?? readHem(secret: "project/atlas/openai-key", key: nil)
    }

    static func anthropicKeyAvailability() -> SecretAvailability {
        availability(account: "anthropic-api-key", hemSecret: "global/anthropic-api-key")
    }

    static func openAIKeyAvailability() -> SecretAvailability {
        availability(account: "openai-api-key", hemSecret: "project/atlas/openai-key")
    }

    @discardableResult
    static func save(value: String, account: String, service: String = "Syn") -> OSStatus {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil)
    }

    @discardableResult
    static func delete(account: String, service: String = "Syn") -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }

    static func readForFixture(service: String, account: String) -> String? {
        readKeychain(service: service, account: account)
    }

    private static func availability(account: String, hemSecret: String) -> SecretAvailability {
        if readKeychain(service: "Syn", account: account) != nil {
            return SecretAvailability(isAvailable: true, source: "Keychain")
        }

        if readHem(secret: hemSecret, key: nil) != nil {
            return SecretAvailability(isAvailable: true, source: "hem")
        }

        return SecretAvailability(isAvailable: false, source: "Missing")
    }

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func readHem(secret: String, key: String?) -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/Users/trmd/.valhall/system-daemons/bin/hem") else {
            return nil
        }

        var arguments = ["get", secret]
        if let key {
            arguments.append(key)
        }

        guard let result = try? run(executable: "/Users/trmd/.valhall/system-daemons/bin/hem", arguments: arguments),
              result.status == 0 else {
            return nil
        }

        let value = parseHemValue(result.output)
        return value.isEmpty || value.contains("pending_request_id") ? nil : value
    }

    private static func parseHemValue(_ output: String) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard var value = lines.last else {
            return ""
        }

        if let tabRange = value.range(of: "\t") {
            value = String(value[tabRange.upperBound...])
        }

        if let equalsRange = value.range(of: "=") {
            value = String(value[equalsRange.upperBound...])
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
