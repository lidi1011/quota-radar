import Foundation

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func snapshot(force: Bool) async throws -> ProviderSnapshot
}

enum ProviderError: LocalizedError, Sendable {
    case dataUnavailable(String)
    case commandFailed(String)
    case missingCredentials(String)

    var errorDescription: String? {
        switch self {
        case .dataUnavailable(let message), .commandFailed(let message), .missingCredentials(let message):
            message
        }
    }
}
