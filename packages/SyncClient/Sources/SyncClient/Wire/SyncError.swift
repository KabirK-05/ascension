import Foundation

/// One field the Worker refused, as `edge/src/http/ingest.ts` reports it.
public struct ContractIssue: Codable, Hashable, Sendable {
    /// A dotted path into the request body, e.g. `rollups.3.training.sessionPlanned`.
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Everything that can go wrong on the wire.
///
/// ``contractViolation`` is the one case that must never be swallowed or retried: the
/// Worker only answers it when a field name or an enum value in this app no longer matches
/// `edge/src/contract.ts`, which means the two halves of the contract have diverged. It
/// carries the full issue list so the divergence is fixable from the error alone.
public enum SyncError: Error, Hashable, Sendable {
    /// The app and the Worker disagree about the contract. Fix the field, don't retry.
    case contractViolation(issues: [ContractIssue], hint: String?)
    /// The batch exceeded the Worker's cap. The pusher chunks below it, so this is a bug.
    case batchTooLarge(limit: Int, sent: Int)
    /// Two rollups for the same date in one batch; the Worker rejects the whole batch.
    case duplicateDates([String])
    /// No device token in the Keychain, or the Worker rejected the one presented.
    case unauthorized
    /// A document `PUT` lost the `If-Match` race more times than the retry budget allows.
    case conflictUnresolved(key: SyncDocumentKey, attempts: Int)
    /// A status this client has no handling for, with the Worker's `error` slug when it
    /// sent one. The body is deliberately not carried: it can hold health data.
    case unexpectedStatus(Int, error: String?)
    /// The response was not the shape the contract declares.
    case malformedResponse(String)
    /// A mutation could not be applied, so the drain stopped rather than skipping it.
    case mutationApplyFailed(id: String, reason: String)
    /// `URLSession` or the transport failed. Equatable by description, since `any Error`
    /// is not.
    case transport(String)

    public static func transport(_ error: any Error) -> SyncError {
        .transport(String(describing: error))
    }
}

extension SyncError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .contractViolation(let issues, let hint):
            let detail = issues.map { "  \($0.path): \($0.message)" }.joined(separator: "\n")
            let lead = "contract_violation — this app and edge/src/contract.ts have diverged"
            return [lead, hint.map { "  hint: \($0)" }, detail.isEmpty ? nil : detail]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .batchTooLarge(let limit, let sent):
            return "batch_too_large — sent \(sent) rollups, the Worker caps a batch at \(limit)"
        case .duplicateDates(let dates):
            return "duplicate_dates — one batch carried the same date twice: \(dates.joined(separator: ", "))"
        case .unauthorized:
            return "unauthorized — the device token is missing or the Worker rejected it"
        case .conflictUnresolved(let key, let attempts):
            return "conflict_unresolved — \(key.rawValue) still lost the If-Match race "
                + "after \(attempts) attempts"
        case .unexpectedStatus(let status, let error):
            return "unexpected_status \(status)\(error.map { " (\($0))" } ?? "")"
        case .malformedResponse(let detail):
            return "malformed_response — \(detail)"
        case .mutationApplyFailed(let id, let reason):
            return "mutation_apply_failed — \(id) could not be applied: \(reason)"
        case .transport(let detail):
            return "transport — \(detail)"
        }
    }
}

extension SyncError {
    /// True for the one case that means the contract itself is broken. The caller surfaces
    /// these rather than logging and moving on.
    public var isContractDivergence: Bool {
        switch self {
        case .contractViolation, .batchTooLarge, .duplicateDates, .malformedResponse:
            return true
        default:
            return false
        }
    }
}
