import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, new, search, me

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .new: return "New & Hot"
        case .search: return "Search"
        case .me: return "My Flix"
        }
    }
}

enum LaunchPhase {
    case logo, avatar, done
}

/// Four tabs under a floating glass tab bar. Title pages open over
/// everything, zooming out of the tapped poster on iOS 18.
struct RootView: View {
    @EnvironmentObject private var router: Router
    @State private var tab: AppTab = .home
    @State private var opened: Set<AppTab> = [.home]
    @State private var launch: LaunchPhase = .logo
    @Namespace private var zoom
    @Namespace private var launchSpace

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            tabs
                .playerCover($router.visit)
            TabBar(tab: $tab, showAvatar: launch == .done, space: launchSpace) { picked in
                opened.insert(picked)
                withAnimation(.easeInOut(duration: 0.22)) { tab = picked }
            }
            .opacity(launch == .logo ? 0 : 1)
            // Stays at the bottom behind the keyboard instead of riding up
            // over Search's results.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.zoomNamespace, zoom)
        .overlay {
            if launch != .done {
                LaunchView(phase: launch, space: launchSpace)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(item: $router.detail) { route in
            DetailContainer(route: route)
                .zoomTransition(route.sourceID, in: zoom)
        }
        .task { await runLaunch() }
    }

    private var tabs: some View {
        ZStack {
            page(.home) { HomeView() }
            page(.new) { NewHotView() }
            page(.search) { SearchView() }
            page(.me) { MyFlixView() }
        }
    }

    /// Tabs stay alive once opened, so their scroll positions survive switching.
    @ViewBuilder
    private func page<Content: View>(_ t: AppTab, @ViewBuilder content: () -> Content) -> some View {
        if opened.contains(t) {
            content()
                .opacity(tab == t ? 1 : 0)
                .scaleEffect(tab == t ? 1 : 0.985)
                .allowsHitTesting(tab == t)
                .accessibilityHidden(tab != t)
        }
    }

    private func runLaunch() async {
        guard launch == .logo else { return }
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation(.spring(duration: 0.4, bounce: 0.35)) { launch = .avatar }
        try? await Task.sleep(for: .seconds(0.85))
        withAnimation(.spring(duration: 0.6, bounce: 0.12)) { launch = .done }
    }
}

struct TabBar: View {
    @Binding var tab: AppTab
    let showAvatar: Bool
    let space: Namespace.ID
    let select: (AppTab) -> Void
    @Namespace private var lens

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                Button {
                    select(t)
                } label: {
                    VStack(spacing: 3) {
                        icon(t)
                        Text(t.label).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if tab == t {
                            Capsule()
                                .fill(.white.opacity(0.1))
                                .padding(.vertical, 5)
                                .matchedGeometryEffect(id: "lens", in: lens)
                        }
                    }
                    .foregroundStyle(tab == t ? Color.white : Color(white: 0.56))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .accessibilityLabel(t.label)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: tab)
        .padding(.horizontal, 6)
        .frame(height: 62)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.35)))
        }
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func icon(_ t: AppTab) -> some View {
        switch t {
        case .home:
            Image(systemName: tab == .home ? "house.fill" : "house").font(.system(size: 20))
        case .new:
            Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 19))
        case .search:
            Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .medium))
        case .me:
            ZStack {
                if showAvatar {
                    AvatarView()
                        .matchedGeometryEffect(id: "avatar", in: space)
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: tab == .me ? 1.5 : 0))
                        .opacity(tab == .me ? 1 : 0.75)
                } else {
                    Color.clear
                }
            }
            .frame(width: 24, height: 24)
        }
    }
}

/// FLIX letters wipe in, the logo dims away, then the profile picture pops
/// up and flies into the tab bar.
struct LaunchView: View {
    let phase: LaunchPhase
    let space: Namespace.ID

    @State private var revealed = [false, false, false, false]
    @State private var logoGone = false
    @State private var spin = false
    private let letters = ["F", "L", "I", "X"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if phase == .logo {
                HStack(spacing: 1) {
                    ForEach(0..<4, id: \.self) { i in
                        Text(letters[i])
                            .clipShape(TopReveal(progress: revealed[i] ? 1 : 0))
                    }
                }
                .font(.system(size: 112, weight: .heavy))
                .fontWidth(.compressed)
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.3), radius: 24)
                .scaleEffect(logoGone ? 1.06 : 0.97)
                .opacity(logoGone ? 0 : 1)
                .brightness(logoGone ? -0.4 : 0)
            }
            if phase == .avatar {
                VStack(spacing: 34) {
                    AvatarView()
                        .matchedGeometryEffect(id: "avatar", in: space)
                        .frame(width: 96, height: 96)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true }
                        }
                }
                .offset(y: -20)
            }
        }
        .onAppear {
            for i in 0..<4 {
                withAnimation(.easeInOut(duration: 0.2).delay(0.08 + Double(i) * 0.095)) { revealed[i] = true }
            }
            withAnimation(.easeIn(duration: 0.3).delay(1.15)) { logoGone = true }
        }
        .accessibilityLabel("Flix")
    }
}

/// Reveals a shape from the top down as progress goes 0 → 1.
struct TopReveal: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 4, y: rect.minY - 4, width: rect.width + 8, height: (rect.height + 8) * progress))
    }
}

/// Title pages and My Flix hide the navigation bar, which also turns off
/// UIKit's swipe-back. This turns it back on for pushed pages.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}

/// A title page with its own navigation, so "More Like This" can push more pages.
struct DetailContainer: View {
    let route: Router.DetailRoute
    @State private var path: [Title] = []

    var body: some View {
        NavigationStack(path: $path) {
            TitleDetailView(title: route.title, isRoot: true)
                .navigationDestination(for: Title.self) { TitleDetailView(title: $0, isRoot: false) }
        }
        // The zoom transition's swipe-to-dismiss would otherwise beat the
        // back swipe on pushed pages and close the whole stack.
        .interactiveDismissDisabled(!path.isEmpty)
    }
}
