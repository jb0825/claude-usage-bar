import Foundation
import Testing
@testable import ClaudeUsageBar

struct CredentialStoreTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let validExpiry = 2_000_000.0
    private let pastExpiry = 500_000.0

    @Test func parsesTokenAndMillisecondExpiry() throws {
        let data = TestData.credentialJSON(token: "fixture-a", expiresAtMilliseconds: validExpiry)

        let credential = try StoredCredential.parse(data)

        #expect(credential.accessToken.value == "fixture-a")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test func malformedCredentialThrows() {
        #expect(throws: CredentialError.malformed) {
            try StoredCredential.parse(Data(#"{ "claudeAiOauth": {} }"#.utf8))
        }
    }

    @Test func tokenDescriptionIsRedacted() {
        let token = AccessToken(value: "fixture-secret")

        #expect(!"\(token)".contains("fixture-secret"))
        #expect(!String(reflecting: token).contains("fixture-secret"))
    }

    @Test func cachesTokenInMemory() async throws {
        let keychain = FakeKeychain(results: [.success(credential("fixture-a", validExpiry))])
        let store = makeStore(keychain)

        _ = try await store.currentToken()
        let token = try await store.currentToken()

        #expect(token.value == "fixture-a")
        #expect(keychain.readCount == 1)
    }

    @Test func reloadReadsKeychainAgain() async throws {
        let keychain = FakeKeychain(results: [
            .success(credential("fixture-a", validExpiry)),
            .success(credential("fixture-b", validExpiry)),
        ])
        let store = makeStore(keychain)

        _ = try await store.currentToken()
        let token = try await store.reloadToken()

        #expect(token.value == "fixture-b")
        #expect(keychain.readCount == 2)
    }

    @Test func expiredKeychainValueThrows() async {
        let keychain = FakeKeychain(results: [.success(credential("fixture-a", pastExpiry))])
        let store = makeStore(keychain)

        await #expect(throws: CredentialError.expired) {
            try await store.currentToken()
        }
    }

    @Test func keychainFailurePropagates() async {
        let keychain = FakeKeychain(results: [.failure(.notFound)])
        let store = makeStore(keychain)

        await #expect(throws: CredentialError.notFound) {
            try await store.currentToken()
        }
    }

    private func makeStore(_ keychain: FakeKeychain) -> CredentialStore {
        let now = now
        return CredentialStore(keychain: keychain, now: { now })
    }

    private func credential(_ token: String, _ expiry: Double) -> Data {
        TestData.credentialJSON(token: token, expiresAtMilliseconds: expiry)
    }
}
