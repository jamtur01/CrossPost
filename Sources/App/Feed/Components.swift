import SwiftUI

/// A centered icon + message, used for empty and error states across the app so
/// they stay consistent. `fills` centers it in a full pane; otherwise it sits at
/// its natural height (for use inside a scrolling list).
struct EmptyStateView: View {
    let text: String
    var systemImage = "tray"
    var fills = true
    /// When set, a "Try Again" button is shown — used for error states.
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil)
        .padding(fills ? 16 : 0)
        .padding(.vertical, fills ? 0 : 40)
    }
}

/// A failed-fetch state with a retry button, in the shared visual language.
struct ErrorStateView: View {
    let message: String
    var fills = true
    let retry: () -> Void

    var body: some View {
        EmptyStateView(text: message, systemImage: "exclamationmark.triangle",
                       fills: fills, retry: retry)
    }
}

/// A subtle fill that appears on hover, for clickable list rows so they read as
/// interactive like the timeline rows do.
private struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? Theme.hoverFill : .clear)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

/// Shows the pointing-hand cursor while hovering a clickable element, popping it
/// back even if the view disappears mid-hover (navigating away / a refresh that
/// removes the element) — a bare `onHover` push/pop leaves the cursor stuck then.
private struct PointingHandCursor: ViewModifier {
    var enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, enabled {
                    if !pushed {
                        NSCursor.pointingHand.push(); pushed = true
                    }
                } else if pushed {
                    NSCursor.pop(); pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop(); pushed = false
                }
            }
    }
}

extension View {
    /// Pointing-hand cursor on hover, balanced across view teardown. `enabled` gates
    /// it (e.g. only when there's an image to open).
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}

/// A static highlight over placeholder content. Loading views must not install
/// perpetual animations: one unresolved image would otherwise drive the entire
/// window's SwiftUI layout and AppKit tracking-area passes continuously.
private struct LoadingSheen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.06), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipped()
    }
}

extension View {
    /// Static loading highlight for placeholder surfaces.
    func loadingSheen() -> some View {
        modifier(LoadingSheen())
    }
}

/// A circular avatar with the shared placeholder + ring, used everywhere an
/// account image appears so sizing and the hairline ring stay consistent.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat
    var ring = true

    var body: some View {
        CachedAsyncImage(
            url: url,
            representation: .avatar,
            targetSize: CGSize(width: size * 2, height: size * 2)
        ) { phase in
            avatarContent(phase)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if ring {
                Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func avatarContent(_ phase: CachedAsyncImagePhase) -> some View {
        switch phase {
        case let .success(image):
            image.resizable().scaledToFill()
        case .loading:
            Circle().fill(Color.primary.opacity(0.06)).loadingSheen()
        case .failure:
            Circle().fill(Color.primary.opacity(0.06))
                .overlay { Image(systemName: "person.crop.circle.badge.exclamationmark") }
        case .unavailable:
            Circle().fill(Color.primary.opacity(0.06))
        }
    }
}

/// A placeholder post row shown while a feed's first page loads — an avatar,
/// two name lines, and body lines with a static highlight. Reads as content
/// arriving rather than an empty pane behind a lone spinner.
struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.gutter) {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: Theme.timelineAvatar, height: Theme.timelineAvatar)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    bar(width: 120, height: 11)
                    bar(width: 70, height: 11)
                }
                bar(width: .infinity, height: 10)
                bar(width: .infinity, height: 10)
                bar(width: 180, height: 10)
            }
        }
        .padding(.horizontal, Theme.timelineRowPaddingH)
        .padding(.vertical, Theme.timelineRowPaddingV)
        .loadingSheen()
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(maxWidth: width == .infinity ? .infinity : nil)
            .frame(width: width == .infinity ? nil : width, height: height)
    }
}

private struct RelativeTimestampNowKey: EnvironmentKey {
    static let defaultValue = Date()
}

extension EnvironmentValues {
    var relativeTimestampNow: Date {
        get { self[RelativeTimestampNowKey.self] }
        set { self[RelativeTimestampNowKey.self] = newValue }
    }
}

@MainActor
private enum RelativeTimestampFormat {
    static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    static func string(for date: Date, relativeTo now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        let magnitude = abs(interval)
        let direction = interval < 0 ? -1 : 1
        var components = DateComponents()

        if magnitude < 60 {
            components.minute = 0
        } else if magnitude < 3600 {
            components.minute = direction * Int(magnitude / 60)
        } else if magnitude < 86400 {
            components.hour = direction * Int(magnitude / 3600)
        } else {
            components.day = direction * Int(magnitude / 86400)
        }

        return formatter.localizedString(from: components)
    }
}

private struct RelativeTimestampView: View {
    let date: Date
    let font: Font
    @Environment(\.relativeTimestampNow) private var now

    var body: some View {
        Text(RelativeTimestampFormat.string(for: date, relativeTo: now))
            .font(font).foregroundStyle(.tertiary).fixedSize()
    }
}

/// A minute-, hour-, or day-bucketed relative timestamp driven by MainView's
/// shared clock so long-lived rows stay current without creating row timers.
func relativeTimestamp(_ date: Date, font: Font = Theme.meta) -> some View {
    RelativeTimestampView(date: date, font: font)
}

/// An unread-count pill in the system style: red, bold white text, circular for a
/// single digit and capsule for more, capped at "99+". Matches the dock badge.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(.red))
        }
    }
}

extension View {
    /// A `.bar`-material strip with a hairline `Divider` on one edge — the shared
    /// look of every column header/footer. Padding stays at the call site since it
    /// genuinely varies per header.
    func barSurface(divider edge: Alignment = .bottom) -> some View {
        background(.bar).overlay(alignment: edge) { Divider() }
    }
}

/// The trailing state row inside a loading list: a spinner while loading, a
/// retryable error when the load failed with nothing to show, or an empty-state
/// once loaded and still empty. Shared by the account and saved-post lists, which
/// present these three states identically. (Thread/profile keep their own, since
/// they show errors alongside already-visible content.)
@ViewBuilder
func listLoadFooter(
    loading: Bool,
    loadError: String?,
    isEmpty: Bool,
    emptyState: (text: String, image: String),
    retry: @escaping () -> Void
) -> some View {
    if loading {
        ProgressView().controlSize(.small)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    } else if let loadError, isEmpty {
        ErrorStateView(message: loadError, fills: false, retry: retry)
    } else if isEmpty {
        EmptyStateView(text: emptyState.text, systemImage: emptyState.image, fills: false)
    }
}
