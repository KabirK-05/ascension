import Foundation

/// The encoder and decoder every request and response goes through.
///
/// Keys are sorted so the same rollup always produces the same bytes: a golden fixture can
/// then be diffed against `edge/src/contract.ts`, and a retry is byte-identical to the
/// attempt it replaces.
public enum SyncCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Pretty, for the golden fixtures the contract check reads.
    public static func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func encode(_ value: some Encodable) throws -> Data {
        do {
            return try encoder().encode(value)
        } catch {
            throw SyncError.malformedResponse("could not encode a request body: \(error)")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw SyncError.malformedResponse("expected \(type), got: \(error)")
        }
    }
}

/// The `error` slug and its detail, which every non-2xx body from `edge/src/http/respond.ts`
/// carries. Decoded leniently: an unexpected failure mode must still surface its status.
struct ProblemBody: Decodable {
    var error: String?
    var hint: String?
    var issues: [ContractIssue]?
    var limit: Int?
    var received: Int?
    var dates: [String]?
}

extension HTTPResponse {
    /// The failure this response represents, mapped onto ``SyncError``.
    func failure() -> SyncError {
        let problem = try? SyncCoding.decoder().decode(ProblemBody.self, from: body)
        switch (status, problem?.error) {
        case (401, _), (403, _):
            return .unauthorized
        case (400, "contract_violation"):
            return .contractViolation(issues: problem?.issues ?? [], hint: problem?.hint)
        case (400, "duplicate_dates"):
            return .duplicateDates(problem?.dates ?? [])
        case (413, _):
            return .batchTooLarge(limit: problem?.limit ?? 0, sent: problem?.received ?? 0)
        default:
            return .unexpectedStatus(status, error: problem?.error)
        }
    }
}
