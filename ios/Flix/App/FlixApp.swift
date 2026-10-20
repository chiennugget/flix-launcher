import AVFoundation
import SwiftData
import SwiftUI

@main
struct FlixApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var site = SiteService()

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
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
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
}

enum Theme {
    static let accent = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let card = Color(white: 0.11)
}

enum Keys {
    static let tmdbKey = "tmdbKey"
    static let configURL = "configURL"
    static let defaultConfigURL = "https://chiennugget.github.io/flix-launcher/domain.json"
    static let rawConfigURL = "https://raw.githubusercontent.com/chiennugget/flix-launcher/main/domain.json"
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
