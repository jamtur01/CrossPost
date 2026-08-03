import AppKit
import SwiftUI

struct MotionVisibilityState: Equatable {
    let rowIsVisible: Bool
    let windowIsVisible: Bool
    let windowIsOccluded: Bool
    let windowIsMinimized: Bool
    let applicationIsActive: Bool

    static let unavailable = MotionVisibilityState(
        rowIsVisible: false,
        windowIsVisible: false,
        windowIsOccluded: true,
        windowIsMinimized: false,
        applicationIsActive: false
    )

    var allowsMotion: Bool {
        rowIsVisible && windowIsVisible && !windowIsOccluded
            && !windowIsMinimized && applicationIsActive
    }
}

struct MotionVisibilityObserver: NSViewRepresentable {
    let onChange: (MotionVisibilityState) -> Void

    func makeNSView(context: Context) -> MotionVisibilityObserverNSView {
        MotionVisibilityObserverNSView(onChange: onChange)
    }

    func updateNSView(_ nsView: MotionVisibilityObserverNSView, context: Context) {
        nsView.update(onChange: onChange)
    }

    static func dismantleNSView(
        _ nsView: MotionVisibilityObserverNSView,
        coordinator: ()
    ) {
        nsView.stopObserving()
    }
}

final class MotionVisibilityObserverNSView: NSView {
    private var onChange: (MotionVisibilityState) -> Void
    private weak var observedWindow: NSWindow?
    private weak var observedClipView: NSClipView?
    private var observers: [NSObjectProtocol] = []
    private var lastState: MotionVisibilityState?

    init(onChange: @escaping (MotionVisibilityState) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshObservations()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshObservations()
    }

    override func layout() {
        super.layout()
        publishCurrentState()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(onChange: @escaping (MotionVisibilityState) -> Void) {
        self.onChange = onChange
        refreshObservations()
    }

    func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        observedWindow = nil
        observedClipView = nil
        lastState = nil
    }

    deinit { stopObserving() }

    private func refreshObservations() {
        let currentWindow = window
        let currentClipView = enclosingScrollView?.contentView
        if currentWindow === observedWindow, currentClipView === observedClipView {
            publishCurrentState()
            return
        }

        stopObserving()
        observedWindow = currentWindow
        observedClipView = currentClipView
        guard let currentWindow else {
            publish(.unavailable)
            return
        }

        observeWindow(currentWindow)
        if let currentClipView {
            currentClipView.postsBoundsChangedNotifications = true
            addObserver(name: NSView.boundsDidChangeNotification, object: currentClipView)
        }
        publishCurrentState()
    }

    private func observeWindow(_ window: NSWindow) {
        let windowNotifications: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification
        ]
        for name in windowNotifications {
            addObserver(name: name, object: window)
        }

        let applicationNotifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification
        ]
        for name in applicationNotifications {
            addObserver(name: name, object: NSApp)
        }
    }

    private func addObserver(name: Notification.Name, object: AnyObject) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { [weak self] notification in
            if notification.name == NSWindow.willCloseNotification {
                self?.publish(.unavailable)
            } else {
                self?.publishCurrentState()
            }
        }
        observers.append(observer)
    }

    private func publishCurrentState() {
        guard let window = observedWindow else {
            publish(.unavailable)
            return
        }
        let rowIsVisible = !isHiddenOrHasHiddenAncestor
            && !bounds.isEmpty && !visibleRect.isEmpty
        publish(
            MotionVisibilityState(
                rowIsVisible: rowIsVisible,
                windowIsVisible: window.isVisible,
                windowIsOccluded: !window.occlusionState.contains(.visible),
                windowIsMinimized: window.isMiniaturized,
                applicationIsActive: NSApp.isActive
            )
        )
    }

    private func publish(_ state: MotionVisibilityState) {
        guard state != lastState else { return }
        lastState = state
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastState == state else { return }
            self.onChange(state)
        }
    }
}
