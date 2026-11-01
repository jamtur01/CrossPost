import AppKit
import SwiftUI

extension View {
    /// Draws the enclosing scroll view's scrollers in the overlay style whatever the
    /// "Show scroll bars" setting, so rows run to the column edge and the scroller floats
    /// over them while scrolling instead of reserving a blank track. SwiftUI has no option
    /// for the style, so a probe inside the content reaches the backing `NSScrollView`.
    /// Apply to a view inside the `ScrollView`, such as its stack.
    func overlayScrollers() -> some View {
        background(OverlayScrollerProbe())
    }
}

private struct OverlayScrollerProbe: NSViewRepresentable {
    func makeNSView(context _: Context) -> OverlayScrollerProbeView {
        OverlayScrollerProbeView()
    }

    func updateNSView(_: OverlayScrollerProbeView, context _: Context) {}
}

final class OverlayScrollerProbeView: NSView {
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyOverlayStyle()
        guard observer == nil else { return }
        // Changing "Show scroll bars" can put the scroll view back on the system style,
        // so apply ours again after AppKit has handled the change.
        observer = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.applyOverlayStyle() }
        }
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    private func applyOverlayStyle() {
        guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
        scrollView.scrollerStyle = .overlay
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
