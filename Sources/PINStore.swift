import Foundation
import Security
import CryptoKit

enum PINStore {
    private static let service = "com.personal.calculatorvault.pin"
    private static let account = "primary-v1"
    private struct Record: Codable { let salt: Data; let digest: Data }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func exists() throws -> Bool { try readData() != nil }
    static func create(_ pin: String) throws {
        var item = query
        item[kSecValueData as String] = try encodedRecord(for: pin)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw PINError.keychain(status) }
    }
    static func replace(_ pin: String) throws {
        let update = [kSecValueData as String: try encodedRecord(for: pin)]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess else { throw PINError.keychain(status) }
    }
    private static func encodedRecord(for pin: String) throws -> Data {
        guard (4...12).contains(pin.count), pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw PINError.invalid
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PINError.keychain(status) }
        let salt = Data(bytes)
        let record = Record(salt: salt, digest: hash(pin, salt: salt))
        return try JSONEncoder().encode(record)
    }
    static func matches(_ candidate: String) throws -> Bool {
        guard let data = try readData() else { return false }
        let record = try JSONDecoder().decode(Record.self, from: data)
        let digest = hash(candidate, salt: record.salt)
        guard digest.count == record.digest.count else { return false }
        return zip(digest, record.digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private static func hash(_ pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
    private static func readData() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PINError.keychain(status) }
        guard let data = result as? Data else { throw PINError.invalid }
        return data
    }
    enum PINError: LocalizedError {
        case invalid, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .invalid: return "PIN 必须是 4–12 位数字，或 Keychain 数据不可读取。"
            case .keychain(let status):
                return "Keychain 错误 \(status)：\(SecCopyErrorMessageString(status, nil) as String? ?? "未知错误")"
            }
        }
    }
}
