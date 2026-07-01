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
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
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
                    if !pushed { NSCursor.pointingHand.push(); pushed = true }
                } else if pushed {
                    NSCursor.pop(); pushed = false
                }
            }
            .onDisappear {
                if pushed { NSCursor.pop(); pushed = false }
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

/// A soft left-to-right sheen that sweeps across a placeholder while content
/// loads, so a loading avatar/image/row reads as "loading" rather than "broken".
/// Respects Reduce Motion (falls back to a static fill).
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.primary.opacity(0.08), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .scaleEffect(x: 0.4, anchor: .leading)
                        .offset(x: phase * 260)
                        .blendMode(.plusLighter))
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 2
                    }
                }
        }
    }
}

extension View {
    /// Animated loading sheen for placeholder surfaces.
    func shimmering() -> some View { modifier(Shimmer()) }

    /// The neutral fill used under a shimmer for skeleton placeholders.
    func skeletonFill(_ corner: CGFloat = 6) -> some View {
        clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// A circular avatar with the shared placeholder + ring, used everywhere an
/// account image appears so sizing and the hairline ring stay consistent.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat
    var ring = true

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(Color.primary.opacity(0.06)).shimmering()
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if ring { Circle().strokeBorder(Theme.avatarRing, lineWidth: 0.5) }
        }
    }
}

/// A placeholder post row shown while a feed's first page loads — an avatar,
/// two name lines, and body lines, all shimmering. Reads as content arriving
/// rather than an empty pane behind a lone spinner.
struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.gutter) {
            Circle().fill(Color.primary.opacity(0.06)).frame(width: Theme.avatar, height: Theme.avatar)
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
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, Theme.rowPaddingV)
        .shimmering()
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(maxWidth: width == .infinity ? .infinity : nil)
            .frame(width: width == .infinity ? nil : width, height: height)
    }
}

/// A relative ("2m", "1h") timestamp in the shared meta styling.
func relativeTimestamp(_ date: Date) -> some View {
    Text(date, format: .relative(presentation: .numeric))
        .font(Theme.meta).foregroundStyle(.tertiary).fixedSize()
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
func listLoadFooter(loading: Bool, loadError: String?, isEmpty: Bool,
                    emptyText: String, emptyImage: String,
                    retry: @escaping () -> Void) -> some View {
    if loading {
        ProgressView().controlSize(.small)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
    } else if let loadError, isEmpty {
        ErrorStateView(message: loadError, fills: false, retry: retry)
    } else if isEmpty {
        EmptyStateView(text: emptyText, systemImage: emptyImage, fills: false)
    }
}
