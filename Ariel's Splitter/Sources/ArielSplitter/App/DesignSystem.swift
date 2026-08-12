import SwiftUI

// MARK: - Colors
extension Color {
    // Accent colors - use system accent
    static let appPrimary = Color.accentColor
    static let appAccent = Color.accentColor
    static let appAccentSecondary = Color.blue
    
    // Semantic colors that adapt to light/dark mode automatically
    static let appBackground = Color(NSColor.windowBackgroundColor)
    static let appSurface = Color(NSColor.controlBackgroundColor)
    static let appSurfaceLight = Color(NSColor.secondarySystemFill)
    static let appText = Color(NSColor.labelColor)
    static let appTextSecondary = Color(NSColor.secondaryLabelColor)
    static let appTextTertiary = Color(NSColor.tertiaryLabelColor)
    static let appSuccess = Color.green
    static let appWarning = Color.orange
    static let appBorder = Color(NSColor.separatorColor)
    static let appDivider = Color(NSColor.separatorColor)
    
    // Light mode variants - same semantic colors
    static let appBackgroundLight = Color(NSColor.windowBackgroundColor)
    static let appSurfaceLight_mode = Color(NSColor.controlBackgroundColor)
    static let appSurfaceLightLight = Color(NSColor.secondarySystemFill)
    static let appTextLight = Color(NSColor.labelColor)
    static let appTextSecondaryLight = Color(NSColor.secondaryLabelColor)
    static let appBorderLight = Color(NSColor.separatorColor)
    static let appDividerLight = Color(NSColor.separatorColor)
}

// MARK: - App Style
enum AppStyle {
    static let cornerRadius: CGFloat = 8
    static let smallCornerRadius: CGFloat = 6
    static let largeCornerRadius: CGFloat = 12
    
    static let spacing: CGFloat = 16
    static let smallSpacing: CGFloat = 8
    static let largeSpacing: CGFloat = 20
    
    static let standardPadding: CGFloat = 20
    static let smallPadding: CGFloat = 12
    
    static let shadowRadius: CGFloat = 4
    static let shadowOpacity: Double = 0.1
    
    static let titleFontSize: CGFloat = 17
    static let headingFontSize: CGFloat = 14
    static let bodyFontSize: CGFloat = 13
    static let captionFontSize: CGFloat = 11
}

// MARK: - View Modifiers
struct SurfaceCard: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(Color.appSurface)
            .cornerRadius(AppStyle.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius)
                    .stroke(Color.appBorder.opacity(0.5), lineWidth: 0.5)
            )
    }
}

extension View {
    func surfaceCard() -> some View {
        modifier(SurfaceCard())
    }

    /// Show a specific cursor while the pointer is over this view.
    ///
    /// SwiftUI's `.pointerStyle` is macOS 15+, and this app targets macOS 14,
    /// so the cursor is set through AppKit instead.
    ///
    /// Note this is for text and resize affordances only. macOS deliberately
    /// keeps the standard arrow over push buttons — the pointing hand is a web
    /// convention, and using it here would look foreign on the platform.
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { isInside in
            if isInside {
                cursor.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - Button Styles
//
// macOS signals that a control is interactive by highlighting it under the
// pointer, not by swapping the cursor: push buttons keep the standard arrow.
// (The pointing hand is a web convention and looks foreign here — it is used
// only for genuine hyperlinks, see LinkButtonStyle.) Each style below therefore
// tracks hover and brightens on it.

struct GlassButtonStyle: ButtonStyle {
    var color: Color = .appAccent
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, color: color, isCompact: isCompact)
    }

    // A ButtonStyle cannot hold @State, so hover lives in a nested view.
    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let isCompact: Bool
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                .padding(.horizontal, isCompact ? 12 : 20)
                .padding(.vertical, isCompact ? 6 : 10)
                .background(
                    RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                        .fill(color.opacity(configuration.isPressed ? 0.8 : 1.0))
                )
                .foregroundColor(.white)
                .brightness(isHovering && isEnabled && !configuration.isPressed ? 0.08 : 0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        private var isActive: Bool { isHovering && isEnabled }

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                        .fill(configuration.isPressed ? Color.appSurfaceLight
                                                      : (isActive ? Color.appSurfaceLight.opacity(0.6)
                                                                  : Color.appSurface))
                )
                .foregroundColor(.appText)
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                        .stroke(isActive ? Color.appAccent.opacity(0.5) : Color.appBorder,
                                lineWidth: isActive ? 1 : 0.5)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }
}

/// Text rendered as a hyperlink: underlines on hover and shows the pointing
/// hand, which *is* the native cursor for links (unlike push buttons).
struct LinkButtonStyle: ButtonStyle {
    var color: Color = .appAccent

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, color: color)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundColor(color.opacity(configuration.isPressed ? 0.6 : 1.0))
                .underline(isHovering && isEnabled)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .cursor(isEnabled ? .pointingHand : .arrow)
        }
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glass(color: Color = .appAccent, compact: Bool = false) -> GlassButtonStyle {
        GlassButtonStyle(color: color, isCompact: compact)
    }

    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }

    /// For text that reads as a hyperlink rather than a push button.
    static func link(color: Color = .appAccent) -> LinkButtonStyle {
        LinkButtonStyle(color: color)
    }
}

/// Hover highlight for bare icon controls (toolbar gears, mute/solo, clear).
///
/// These use `.plain`, so they get no styling of their own and would otherwise
/// give no feedback at all until clicked.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = AppStyle.smallCornerRadius
    var padding: CGFloat = 4
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovering && isEnabled ? Color.appSurfaceLight.opacity(0.8) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = AppStyle.smallCornerRadius, padding: CGFloat = 4) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, padding: padding))
    }
}