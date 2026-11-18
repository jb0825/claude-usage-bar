import Foundation
import Security

struct AccessToken: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let value: String

    // 문자열 보간이나 디버거 출력으로 토큰이 새지 않도록 막는다.
    var description: String { "token=<redacted>" }
    var debugDescription: String { description }
}

struct StoredCredential: Equatable, Sendable {
    let accessToken: AccessToken
    let expiresAt: Date?

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }

    static func parse(_ data: Data) throws -> StoredCredential {
        guard let file = try? JSONDecoder().decode(CredentialFile.self, from: data),
              let token = file.claudeAiOauth?.accessToken,
              !token.isEmpty
        else {
            throw CredentialError.malformed
        }

        let expiresAt = file.claudeAiOauth?.expiresAt.map {
            Date(timeIntervalSince1970: $0 * Constants.Time.secondsPerMilli)
        }
        return StoredCredential(accessToken: AccessToken(value: token), expiresAt: expiresAt)
    }
}

private struct CredentialFile: Decodable {
    struct OAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?

        private enum CodingKeys: String, CodingKey {
            case accessToken
            case expiresAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try? container.decodeIfPresent(String.self, forKey: .accessToken)
            expiresAt = try? container.decodeIfPresent(Double.self, forKey: .expiresAt)
        }
    }

    let claudeAiOauth: OAuth?
}

enum CredentialError: Error, Equatable {
    case notFound
    case malformed
    case expired
    case keychain(OSStatus)
}

protocol CredentialProviding: Sendable {
    func currentToken() async throws -> AccessToken
    func reloadToken() async throws -> AccessToken
}

protocol KeychainReading: Sendable {
    func readCredentialData() throws -> Data
}

// Claude Code가 소유한 항목이므로 읽기만 한다. 토큰 갱신은 refresh token이 교체되어
// Claude Code가 로그아웃될 수 있어 직접 수행하지 않는다.
struct SystemKeychainReader: KeychainReading {
    func readCredentialData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw CredentialError.malformed }
            return data
        case errSecItemNotFound:
            throw CredentialError.notFound
        default:
            throw CredentialError.keychain(status)
        }
    }
}

actor CredentialStore: CredentialProviding {
    private let keychain: any KeychainReading
    private let now: @Sendable () -> Date
    private var cached: StoredCredential?

    init(
        keychain: any KeychainReading = SystemKeychainReader(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.now = now
    }

    func currentToken() throws -> AccessToken {
        if let cached, !cached.isExpired(at: now()) {
            return cached.accessToken
        }
        return try reloadToken()
    }

    // 만료된 토큰은 Claude Code가 갱신했을 수 있으므로 키체인을 다시 확인하고,
    // 그래도 만료 상태면 실패할 요청을 보내지 않는다.
    func reloadToken() throws -> AccessToken {
        cached = nil
        let credential = try StoredCredential.parse(keychain.readCredentialData())
        guard !credential.isExpired(at: now()) else {
            throw CredentialError.expired
        }
        cached = credential
        return credential.accessToken
    }
}
