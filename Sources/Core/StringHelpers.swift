import Foundation

extension String {
    /// The string, or nil when it's empty or only whitespace. Used to omit blank
    /// optional fields (alt text, content warnings, report notes) and to fall back
    /// past blank server messages.
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

/// An account's display name when present and non-blank, else its handle — the one
/// fallback used everywhere an author/actor name is shown, on both platforms.
func displayOrHandle(_ displayName: String?, _ handle: String) -> String {
    displayName?.nilIfBlank ?? handle
}
