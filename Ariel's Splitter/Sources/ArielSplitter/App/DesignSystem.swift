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
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    var color: Color = .appAccent
    var isCompact: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
            .padding(.horizontal, isCompact ? 12 : 20)
            .padding(.vertical, isCompact ? 6 : 10)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                    .fill(color.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                    .fill(Color.appSurface)
            )
            .foregroundColor(.appText)
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.smallCornerRadius)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glass(color: Color = .appAccent, compact: Bool = false) -> GlassButtonStyle {
        GlassButtonStyle(color: color, isCompact: compact)
    }
    
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}