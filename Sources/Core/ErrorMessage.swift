import Foundation
import ATProtoKit

extension Error {
    /// A message suitable to show a user. Prefers our `LocalizedError`/
    /// `CustomStringConvertible` text, then a readable mapping for ATProtoKit's
    /// errors (which lack `LocalizedError` and otherwise bridge to the opaque
    /// "ATProtoKit.ATAPIError error 0"), and only then the system description.
    var userMessage: String {
        if let described = (self as? LocalizedError)?.errorDescription {
            return described
        }
        if let atproto = atProtoUserMessage(for: self) {
            return atproto
        }
        return localizedDescription
    }
}

/// Human-readable text for ATProtoKit errors, which don't conform to `LocalizedError`
/// and otherwise bridge to the opaque "ATProtoKit.ATAPIError error 0". The server's
/// own message lives in the `ATHTTPResponseError` payload; the payload-less 5xx cases
/// and rate limits we phrase ourselves.
private func atProtoUserMessage(for error: any Error) -> String? {
    switch error {
    case let ATAPIError.badRequest(payload),
         let ATAPIError.forbidden(payload),
         let ATAPIError.notFound(payload),
         let ATAPIError.methodNotAllowed(payload),
         let ATAPIError.payloadTooLarge(payload),
         let ATAPIError.upgradeRequired(payload),
         let ATAPIError.internalServerError(payload),
         let ATAPIError.methodNotImplemented(payload):
        return serverMessage(payload)
    case let ATAPIError.unauthorized(payload, _):
        return serverMessage(payload)
    case let ATAPIError.tooManyRequests(payload, retryAfter):
        if let retryAfter {
            return "Rate limited by the server. Try again in \(Int(retryAfter.rounded()))s."
        }
        return serverMessage(payload)
    case ATAPIError.badGateway, ATAPIError.serviceUnavailable, ATAPIError.gatewayTimeout:
        return "The server is temporarily unavailable. Please try again."
    case let ATAPIError.unknown(message, _, _, _):
        return message?.nilIfBlank ?? "An unexpected server error occurred."
    case ATProtoBluesky.ATBlueskyError.imageTooLarge:
        return "That image is too large to upload."
    case let ATProtoBluesky.ATProtoBlueskyError.recordNotFound(message),
         let ATProtoBluesky.ATProtoBlueskyError.invalidReplyReference(message),
         let ATProtoBluesky.ATProtoBlueskyError.emptyReplaceArray(message):
        return message.nilIfBlank ?? "Couldn't reach the server. Please try again."
    case ATProtocolConfiguration.ATProtocolConfigurationError.tokensExpired,
         ATProtocolConfiguration.ATProtocolConfigurationError.noSessionToken:
        return "Your session expired. Reconnect the account in Settings."
    case is ATProtoError:
        // Any other ATProtoKit error: a clean generic line beats leaking the
        // Swift type/reflection or the "error 0" bridge string to the user.
        return "Couldn't reach the server. Please try again."
    default:
        return nil
    }
}

private func serverMessage(_ payload: APIClientService.ATHTTPResponseError) -> String {
    payload.message.nilIfBlank ?? payload.error.nilIfBlank ?? "The server rejected the request."
}
