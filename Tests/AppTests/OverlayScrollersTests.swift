import AppKit
@testable import CrossPost
import SwiftUI
import XCTest

@MainActor
final class OverlayScrollersTests: XCTestCase {
    func testScrollViewKeepsOverlayScrollersWhenThePreferenceChanges() async throws {
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 200, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let content = ScrollView { Color.clear.frame(height: 1000).overlayScrollers() }
        window.contentView = NSHostingView(rootView: content.frame(width: 200, height: 200))
        window.orderFrontRegardless()
        let root = try XCTUnwrap(window.contentView)
        await waitUntil { Self.scrollView(in: root)?.scrollerStyle == .overlay }

        // Stand in for AppKit resetting the style when "Show scroll bars" changes.
        let scrollView = try XCTUnwrap(Self.scrollView(in: root))
        scrollView.scrollerStyle = .legacy
        NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        await waitUntil { scrollView.scrollerStyle == .overlay }
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else {
                return XCTFail("condition not met within timeout", file: file, line: line)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
}
