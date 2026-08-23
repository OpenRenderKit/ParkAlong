import SwiftUI

enum AdaptiveSurfaceKind: Equatable, Sendable {
    case liquidGlass
    case opaque
    case material
}

enum AdaptiveChromePolicy {
    static func surfaceKind(
        supportsLiquidGlass: Bool,
        reduceTransparency: Bool
    ) -> AdaptiveSurfaceKind {
        if reduceTransparency {
            return .opaque
        }
        if supportsLiquidGlass {
            return .liquidGlass
        }
        return .material
    }

    static func showsNavigationBarBackground(supportsLiquidGlass: Bool) -> Bool {
        !supportsLiquidGlass
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            content
        } else if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct AdaptiveGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.background, in: shape)
        } else if #available(iOS 26, *) {
            if isInteractive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

struct AdaptiveProminentActionModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(.borderedProminent)
        } else if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct AdaptiveGlassControlButtonModifier: ViewModifier {
    var isSelected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            if isSelected {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        } else if #available(iOS 26, *) {
            if isSelected {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

private struct AdaptiveControlDockModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.background, in: shape)
        } else if #available(iOS 26, *) {
            content
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

struct AdaptiveHighVisibilityToolbarContent<Content: ToolbarContent>: ToolbarContent {
    var content: Content

    var body: some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            content.visibilityPriority(.high)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct AdaptiveToolbarOverflowMenu<Content: View>: ToolbarContent {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            ToolbarOverflowMenu {
                content
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                content
            }
        }
        #else
        ToolbarItem(placement: .topBarTrailing) {
            content
        }
        #endif
    }
}

private struct AdaptiveToolbarMinimizationModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            content.toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct AdaptiveNavigationBarBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var supportsLiquidGlass: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if AdaptiveChromePolicy.showsNavigationBarBackground(
            supportsLiquidGlass: supportsLiquidGlass
        ), reduceTransparency {
            content
                .toolbarBackground(.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else if AdaptiveChromePolicy.showsNavigationBarBackground(
            supportsLiquidGlass: supportsLiquidGlass
        ) {
            content
                .toolbarBackground(.regularMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            content.toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct AdaptiveStatusBarColorSchemeModifier: ViewModifier {
    var colorScheme: ColorScheme?
    @Environment(\.colorScheme) private var environmentColorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            content.toolbarColorScheme(colorScheme ?? environmentColorScheme, for: .statusBar)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func adaptiveGlassSurface(cornerRadius: CGFloat, isInteractive: Bool = false) -> some View {
        modifier(AdaptiveGlassSurfaceModifier(cornerRadius: cornerRadius, isInteractive: isInteractive))
    }

    func adaptiveProminentAction() -> some View {
        modifier(AdaptiveProminentActionModifier())
    }

    func adaptiveGlassControlButton(isSelected: Bool = false) -> some View {
        modifier(AdaptiveGlassControlButtonModifier(isSelected: isSelected))
    }

    func adaptiveControlDock(cornerRadius: CGFloat) -> some View {
        modifier(AdaptiveControlDockModifier(cornerRadius: cornerRadius))
    }

    func adaptiveToolbarMinimizationBehavior() -> some View {
        modifier(AdaptiveToolbarMinimizationModifier())
    }

    func adaptiveNavigationBarBackground() -> some View {
        modifier(AdaptiveNavigationBarBackgroundModifier())
    }

    func adaptiveStatusBarColorScheme(_ colorScheme: ColorScheme? = nil) -> some View {
        modifier(AdaptiveStatusBarColorSchemeModifier(colorScheme: colorScheme))
    }
}

extension ToolbarContent {
    func adaptiveHighVisibilityPriority() -> some ToolbarContent {
        AdaptiveHighVisibilityToolbarContent(content: self)
    }
}

extension ToolbarItemPlacement {
    static var adaptiveTopBarPinnedTrailing: ToolbarItemPlacement {
        #if compiler(>=6.4)
        if #available(iOS 27, *) {
            return .topBarPinnedTrailing
        }
        #endif
        return .topBarTrailing
    }
}
