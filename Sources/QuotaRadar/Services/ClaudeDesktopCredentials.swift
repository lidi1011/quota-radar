import Foundation
import Security
import LocalAuthentication
import SQLite3
import CommonCrypto
import CryptoKit

// Only the two authentication/routing cookies are read. No cookie or decrypted
// secret is persisted by QuotaRadar, passed through a shell, or logged.
struct ClaudeDesktopCredentials: Sendable {
    let sessionKey: String
    let organization: String
    let fingerprint: String
}

struct ClaudeDesktopCookieReader: Sendable {
    var root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude")

    private struct Cookie {
        let name: String
        let host: String
        let encrypted: Data
    }

    private func cookies() throws -> (Int, [Cookie]) {
        let candidates = [root.appendingPathComponent("Cookies"), root.appendingPathComponent("Network/Cookies")]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ProviderError.missingCredentials("未找到 Claude 桌面端登录数据，请先在 Claude 桌面端登录")
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw ProviderError.dataUnavailable("无法读取 Claude 桌面端 Cookie 数据库")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else {
            throw ProviderError.dataUnavailable("Claude 登录数据正忙，请稍后刷新")
        }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &statement, nil) == SQLITE_OK else {
            throw ProviderError.dataUnavailable("不支持的 Claude Cookie 数据库格式")
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            sqlite3_finalize(statement)
            throw ProviderError.dataUnavailable("无法识别 Claude Cookie 版本")
        }
        let version = Int(sqlite3_column_int(statement, 0))
        sqlite3_finalize(statement)
        let sql = "SELECT name, host_key, encrypted_value, expires_utc FROM cookies WHERE host_key IN ('.claude.ai','claude.ai') AND name IN ('sessionKey','lastActiveOrg') AND path='/'"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ProviderError.dataUnavailable("不支持的 Claude Cookie 字段")
        }
        defer { sqlite3_finalize(statement) }
        var result: [Cookie] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            let expiry = Double(sqlite3_column_int64(statement, 3)) / 1_000_000 - 11_644_473_600
            if sqlite3_column_int64(statement, 3) == 0 || expiry > Date().timeIntervalSince1970 {
                if let name = sqlite3_column_text(statement, 0), let host = sqlite3_column_text(statement, 1),
                   let bytes = sqlite3_column_blob(statement, 2) {
                    result.append(Cookie(name: String(cString: name), host: String(cString: host),
                                         encrypted: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))))
                }
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE, result.count == 2, Set(result.map(\.name)).count == 2 else {
            throw ProviderError.missingCredentials("Claude 桌面端未登录、登录已过期或账号信息不唯一，请重新登录后刷新")
        }
        return (version, result.sorted { $0.name < $1.name })
    }

    private func fingerprint(_ cookies: [Cookie]) -> String {
        var data = Data()
        for cookie in cookies {
            data.append(Data((cookie.name + "\0" + cookie.host + "\0").utf8))
            data.append(cookie.encrypted)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func currentFingerprint() throws -> String { fingerprint(try cookies().1) }

    func read(allowInteraction: Bool) throws -> ClaudeDesktopCredentials {
        let (version, cookies) = try cookies()
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Claude Safe Storage",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let password = item as? Data else {
            throw ProviderError.missingCredentials("无法访问 Claude 登录钥匙串；请手动刷新并允许访问 Claude Safe Storage")
        }
        let key = try Self.deriveKey(password: password)
        var values: [String: String] = [:]
        for cookie in cookies {
            values[cookie.name] = try Self.decrypt(cookie.encrypted, key: key, host: cookie.host, version: version)
        }
        guard let session = values["sessionKey"], !session.isEmpty,
              session.utf8.allSatisfy({ $0 > 32 && $0 < 127 && $0 != 59 }),
              let organization = values["lastActiveOrg"], UUID(uuidString: organization) != nil else {
            throw ProviderError.missingCredentials("Claude 桌面端账号信息无效，请重新登录")
        }
        return ClaudeDesktopCredentials(sessionKey: session, organization: organization, fingerprint: fingerprint(cookies))
    }

    static func deriveKey(password: Data) throws -> Data {
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let status = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.bindMemory(to: Int8.self).baseAddress,
                                password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                                1003, &key, key.count)
        }
        guard status == kCCSuccess else { throw ProviderError.dataUnavailable("无法解密 Claude 登录数据") }
        return Data(key)
    }

    static func decrypt(_ encrypted: Data, key: Data, host: String, version: Int) throws -> String {
        guard encrypted.starts(with: Data("v10".utf8)), key.count == 16 else {
            throw ProviderError.dataUnavailable("暂不支持此版本的 Claude Cookie 加密格式")
        }
        let ciphertext = Data(encrypted.dropFirst(3))
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var count = 0
        let capacity = output.count
        let iv = [UInt8](repeating: 0x20, count: 16)
        let status = key.withUnsafeBytes { keyBytes in
            ciphertext.withUnsafeBytes { bytes in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv, bytes.baseAddress, ciphertext.count,
                        &output, capacity, &count)
            }
        }
        guard status == kCCSuccess else { throw ProviderError.dataUnavailable("Claude 登录数据解密失败") }
        var plaintext = Data(output.prefix(count))
        // Chromium schema 24 binds each value to its host with a SHA-256 prefix.
        if version >= 24 {
            let digest = Data(SHA256.hash(data: Data(host.utf8)))
            guard plaintext.starts(with: digest) else { throw ProviderError.dataUnavailable("Claude Cookie 域名校验失败") }
            plaintext = Data(plaintext.dropFirst(32))
        }
        guard let value = String(data: plaintext, encoding: .utf8) else {
            throw ProviderError.dataUnavailable("Claude Cookie 内容格式无效")
        }
        return value
    }
}
