import Foundation
import Testing
@testable import ClaudeUsageBar

struct UsageServiceTests {
    private let okay: Result<(Int, Data), URLError> = .success((200, TestData.usageJSON))
    private let unauthorized: Result<(Int, Data), URLError> = .success((401, Data()))

    @Test func sendsExpectedRequest() async throws {
        let transport = FakeTransport(responses: [okay])
        let service = makeService(transport: transport)

        let snapshot = try await service.fetchUsage()

        let request = try #require(await transport.requests.first)
        #expect(snapshot.session.usedPercent == 21)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-a")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func retriesOnceWithReloadedTokenAfter401() async throws {
        let transport = FakeTransport(responses: [unauthorized, okay])
        let credentials = FakeCredentials(current: "fixture-a", reloaded: "fixture-b")
        let service = makeService(transport: transport, credentials: credentials)

        _ = try await service.fetchUsage()

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-b")
        #expect(await credentials.reloadCount == 1)
    }

    @Test func secondUnauthorizedStops() async {
        let transport = FakeTransport(responses: [unauthorized, unauthorized])
        let credentials = FakeCredentials(current: "fixture-a", reloaded: "fixture-b")
        let service = makeService(transport: transport, credentials: credentials)

        await #expect(throws: UsageError.unauthorized) {
            try await service.fetchUsage()
        }
        #expect(await transport.requests.count == 2)
        #expect(await credentials.reloadCount == 1)
    }

    @Test func unchangedTokenIsNotRetried() async {
        let transport = FakeTransport(responses: [unauthorized])
        let credentials = FakeCredentials(current: "fixture-a", reloaded: "fixture-a")
        let service = makeService(transport: transport, credentials: credentials)

        await #expect(throws: UsageError.unauthorized) {
            try await service.fetchUsage()
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func serverErrorMapsToStatus() async {
        let service = makeService(transport: FakeTransport(responses: [.success((503, Data()))]))

        await #expect(throws: UsageError.httpStatus(503)) {
            try await service.fetchUsage()
        }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let transport = FakeTransport(
            responses: [.success((429, Data()))],
            headerFields: ["Retry-After": "120"]
        )
        let service = makeService(transport: transport)

        await #expect(throws: UsageError.httpStatus(429, retryAfter: 120)) {
            try await service.fetchUsage()
        }
    }

    @Test(arguments: [
        ("90", 90.0),
        (" 15 ", 15.0),
        ("-5", 0.0),
        ("Thu, 01 Jan 1970 00:02:00 GMT", 60.0),
    ])
    func parsesRetryAfter(value: String, expected: Double) {
        let now = Date(timeIntervalSince1970: 60)

        #expect(UsageService.retryAfter(from: value, now: now) == expected)
    }

    @Test(arguments: [nil, "", "soon"] as [String?])
    func invalidRetryAfterIsIgnored(value: String?) {
        #expect(UsageService.retryAfter(from: value, now: Date()) == nil)
    }

    @Test func transportErrorMapsToNetwork() async {
        let service = makeService(
            transport: FakeTransport(responses: [.failure(URLError(.timedOut))])
        )

        await #expect(throws: UsageError.network) {
            try await service.fetchUsage()
        }
    }

    @Test func cancelledRequestStaysCancelled() async {
        let service = makeService(
            transport: FakeTransport(responses: [.failure(URLError(.cancelled))])
        )

        await #expect(throws: CancellationError.self) {
            try await service.fetchUsage()
        }
    }

    @Test func invalidBodyMapsToInvalidResponse() async {
        let service = makeService(
            transport: FakeTransport(responses: [.success((200, Data("[]".utf8)))])
        )

        await #expect(throws: UsageError.invalidResponse) {
            try await service.fetchUsage()
        }
    }

    private func makeService(
        transport: FakeTransport,
        credentials: FakeCredentials = FakeCredentials(current: "fixture-a", reloaded: "fixture-b")
    ) -> UsageService {
        UsageService(credentials: credentials, transport: transport)
    }
}
