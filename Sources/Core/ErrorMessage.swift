import Foundation

extension Error {
    /// A message suitable to show a user. Prefers our `LocalizedError`/
    /// `CustomStringConvertible` text over the verbose reflection form that
    /// `String(describing:)` produces for SDK/system errors.
    var userMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
