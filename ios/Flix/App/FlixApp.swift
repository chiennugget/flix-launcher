import AVFoundation
import SwiftData
import SwiftUI

@main
struct FlixApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var site = SiteService()
    @StateObject private var ratings = RatingStore()
    @StateObject private var router = Router()

    init() {
        // Bigger image cache so poster rows don't re-download on every scroll.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 400 << 20)
        // Plays sound with the silent switch on and keeps picture-in-picture going.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(site)
                .environmentObject(ratings)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    WebWarmup.start()
                    _ = await AdBlocker.shared.rules()
                    await site.refresh()
                }
        }
        .modelContainer(for: [LibraryItem.self, WatchProgress.self])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return Self.orientations
    }
}

/// Portrait in the app's menus, free rotation while the site is open.
@MainActor
enum Orientation {
    static func allow(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientations = mask
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if mask == .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }

    /// Turns the screen now, e.g. to landscape when a video goes fullscreen.
    static func rotate(to mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

enum Theme {
    /// Netflix-style red, for progress bars, badges and the logo.
    static let accent = Color(red: 0.898, green: 0.035, blue: 0.078)
    /// Title page and panel background.
    static let card = Color(white: 0.094)
    /// Buttons and pills on dark backgrounds.
    static let raised = Color(white: 0.17)
    /// Age-rating badge.
    static let ratingBadge = Color(red: 0.898, green: 0.314, blue: 0.102)
}

/// Opens title pages and the player from anywhere (rows, Search, My Flix).
@MainActor
final class Router: ObservableObject {
    struct DetailRoute: Identifiable {
        let id = UUID()
        let title: Title
        /// The tapped poster, so iOS 18 can zoom the page out of it.
        let sourceID: String
    }

    @Published var detail: DetailRoute?
    @Published var visit: SiteVisit?

    func open(_ title: Title, from sourceID: String) {
        detail = DetailRoute(title: title, sourceID: sourceID)
    }

    func play(_ request: PlayRequest) {
        visit = SiteVisit(request: request)
    }
}

enum Keys {
    static let tmdbKey = "tmdbKey"
    static let configURL = "configURL"
    static let autoplayNext = "autoplayNext"
    static let nativeFullscreen = "nativeFullscreen"
    /// Subtitle language picked for players that remember it themselves (vidcore.io).
    static let siteSubtitleLanguage = "siteSubtitleLanguage"
    static let profileName = "profileName"
    static let defaultConfigURL = "https://chiennugget.github.io/flix-launcher/domain.json"
    static let rawConfigURL = "https://raw.githubusercontent.com/chiennugget/flix-launcher/main/domain.json"
}

enum Profile {
    /// The profile name to show: "You" when Settings' field is blank, so
    /// Home never reads "Continue Watching for ".
    static func name(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }
}

enum Format {
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func remaining(_ seconds: Double) -> String {
        let m = max(1, Int(seconds / 60))
        return m >= 60 ? "\(m / 60)h \(m % 60)m left" : "\(m)m left"
    }
}
