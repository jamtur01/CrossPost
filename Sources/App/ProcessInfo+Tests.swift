import Foundation

extension ProcessInfo {
    /// True inside the XCTest host, which launches the full app UI. Anything
    /// that would touch the user's real data or the network checks this first.
    nonisolated var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
