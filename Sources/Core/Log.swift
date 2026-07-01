import Foundation
import os

/// Thin wrapper over `os.Logger` so the paths that otherwise fail silently
/// (background feed refreshes, the live-stream reconnect loop) leave a trace in
/// Console/`log stream` without surfacing anything to the user. Categorized so
/// they can be filtered. Log context (feed kind, target) `.public`; interpolate
/// error text with default privacy, since a server message can echo user content.
enum Log {
    private static let subsystem = "net.kartar.crosspost"

    static let feed = Logger(subsystem: subsystem, category: "feed")
    static let posting = Logger(subsystem: subsystem, category: "posting")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
