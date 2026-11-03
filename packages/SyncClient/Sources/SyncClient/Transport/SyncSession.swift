import Foundation

/// How many times a retryable failure is tried again, and how long between attempts.
public struct RetryPolicy: Hashable, Sendable {
    public var maxAttempts: Int
    public var initialDelay: Duration
    public var multiplier: Double

    public init(maxAttempts: Int = 3, initialDelay: Duration = .seconds(1), multiplier: Double = 2) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelay = initialDelay
        self.multiplier = multiplier
    }

    /// No waiting and one attempt: what a test wants, and what a background task with
    /// seconds left should use.
    public static let none = RetryPolicy(maxAttempts: 1, initialDelay: .zero, multiplier: 1)

    func delay(beforeAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }
        let factor = pow(multiplier, Double(attempt - 2))
        return initialDelay * factor
    }
}

/// Waiting, injected, so a retry test does not actually sleep.
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        guard duration > .zero else { return }
        try await Task.sleep(for: duration)
    }
}

/// Records what it was asked to wait for and returns immediately.
public final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Duration] = []

    public init() {}

    public var recorded: [Duration] {
        lock.withLock { waits }
    }

    public func sleep(for duration: Duration) async throws {
        lock.withLock { waits.append(duration) }
    }
}

/// An authenticated conversation with the Worker.
///
/// Attaches the device token from the Keychain as `Authorization: Bearer <token>`, and
/// retries only what is worth retrying. A `contract_violation` is never retried: the
/// request would be identical and so would the answer.
public struct SyncSession: Sendable {
    private let transport: any HTTPTransport
    private let tokens: any DeviceTokenStore
    private let policy: RetryPolicy
    private let sleeper: any Sleeper

    public init(transport: any HTTPTransport,
                tokens: any DeviceTokenStore,
                policy: RetryPolicy = RetryPolicy(),
                sleeper: any Sleeper = TaskSleeper()) {
        self.transport = transport
        self.tokens = tokens
        self.policy = policy
        self.sleeper = sleeper
    }

    /// Sends `request` with the bearer header attached, retrying transport failures and
    /// 5xx/408/429 within the policy. Returns the response whatever its status; mapping a
    /// status to a ``SyncError`` is the caller's call, because 409 is meaningful.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let authorized = try authorize(request)
        var lastFailure: SyncError?
        for attempt in 1...policy.maxAttempts {
            try await sleeper.sleep(for: policy.delay(beforeAttempt: attempt))
            do {
                let response = try await transport.send(authorized)
                guard response.isRetryable, attempt < policy.maxAttempts else { return response }
                lastFailure = response.failure()
            } catch {
                lastFailure = SyncError.transport(error)
                if attempt == policy.maxAttempts { throw lastFailure ?? SyncError.transport(error) }
            }
        }
        throw lastFailure ?? SyncError.malformedResponse("no attempt was made")
    }

    private func authorize(_ request: HTTPRequest) throws -> HTTPRequest {
        let token: String?
        do {
            token = try tokens.token()
        } catch {
            throw SyncError.unauthorized
        }
        guard let token, !token.isEmpty else { throw SyncError.unauthorized }
        return request
            .settingHeader("Authorization", "Bearer \(token)")
            .settingHeader("Accept", "application/json")
    }
}
