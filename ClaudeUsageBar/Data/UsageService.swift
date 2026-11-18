import Foundation

enum UsageError: Error, Equatable {
    case credentials(CredentialError)
    case unauthorized
    case httpStatus(Int, retryAfter: TimeInterval? = nil)
    case network
    case invalidResponse
}

protocol UsageFetching: Sendable {
    func fetchUsage() async throws -> UsageSnapshot
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// 리다이렉트를 따라가면 Authorization 헤더가 다른 곳으로 전달될 수 있어 차단한다.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init() {
        // 토큰과 응답이 디스크 캐시에 남지 않도록 ephemeral 세션을 쓴다.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.API.requestTimeout
        configuration.urlCache = nil
        session = URLSession(
            configuration: configuration,
            delegate: RedirectBlocker(),
            delegateQueue: nil
        )
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse
        }
        return (data, httpResponse)
    }
}

actor UsageService: UsageFetching {
    private static let unauthorizedStatus = 401
    private static let successStatuses = 200..<300

    private let credentials: any CredentialProviding
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    init(
        credentials: any CredentialProviding,
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.transport = transport
        self.now = now
    }

    func fetchUsage() async throws -> UsageSnapshot {
        let token = try await credential { try await credentials.currentToken() }
        var (data, response) = try await send(token: token)

        if response.statusCode == Self.unauthorizedStatus {
            let reloaded = try await credential { try await credentials.reloadToken() }
            // 키체인 값이 그대로면 재시도해도 같은 401이므로 호출하지 않는다.
            guard reloaded != token else { throw UsageError.unauthorized }

            (data, response) = try await send(token: reloaded)
            guard response.statusCode != Self.unauthorizedStatus else {
                throw UsageError.unauthorized
            }
        }

        guard Self.successStatuses.contains(response.statusCode) else {
            let retryAfter = Self.retryAfter(
                from: response.value(forHTTPHeaderField: Constants.API.retryAfterHeaderName),
                now: now()
            )
            throw UsageError.httpStatus(response.statusCode, retryAfter: retryAfter)
        }
        return try decode(data)
    }

    // Retry-After는 초 단위 숫자나 HTTP 날짜 형식으로 올 수 있다.
    static func retryAfter(from value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return max(seconds, 0)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Constants.API.httpDateLocaleIdentifier)
        formatter.dateFormat = Constants.API.httpDateFormat
        return formatter.date(from: value).map { max($0.timeIntervalSince(now), 0) }
    }

    private func credential(
        _ load: () async throws -> AccessToken
    ) async throws -> AccessToken {
        do {
            return try await load()
        } catch let error as CredentialError {
            throw UsageError.credentials(error)
        }
    }

    private func send(token: AccessToken) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(token: token)
        do {
            return try await transport.send(request)
        } catch let error as UsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw UsageError.network
        }
    }

    // Claude Code가 쓰는 비공식 엔드포인트다. 사용량을 소모하지 않는 이 조회만 호출한다.
    private func makeRequest(token: AccessToken) throws -> URLRequest {
        guard let url = URL(string: Constants.API.usageEndpoint) else {
            throw UsageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue(
            Constants.API.betaHeaderValue,
            forHTTPHeaderField: Constants.API.betaHeaderName
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func decode(_ data: Data) throws -> UsageSnapshot {
        do {
            return try UsageSnapshot.decode(from: data, fetchedAt: now())
        } catch {
            throw UsageError.invalidResponse
        }
    }
}
