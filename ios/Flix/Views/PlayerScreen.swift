import SwiftData
import SwiftUI
import WebKit

/// The site, full screen, with ad blocking, rotation and progress tracking.
/// For a title it shows just the site's video player, with the site's other
/// players one tap away.
struct PlayerScreen: View {
    let visit: SiteVisit

    @EnvironmentObject private var site: SiteService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var web = WebController()
    @AppStorage("playerOnly") private var playerOnly = true
    @AppStorage(Keys.autoplayNext) private var autoplayNext = true
    @AppStorage(Keys.nativeFullscreen) private var nativeFullscreen = false
    @AppStorage(Keys.tmdbKey) private var tmdbKey = ""

    @State private var startURL: URL?
    @State private var rules: WKContentRuleList?
    @State private var current: PlayRequest?
    @State private var resumedKey: String?
    @State private var toast: String?
    @State private var started = false
    @State private var player = 1
    @State private var sawVideo = false
    @State private var suggestedPlayer: Int?
    @State private var fallbackTask: Task<Void, Never>?
    @State private var seasons: [SeasonSummary] = []
    @State private var upNext: PlayRequest?
    @State private var countdown = 0
    @State private var countdownTask: Task<Void, Never>?
    @State private var promptedKey: String?
    @State private var showEpisodes = false
    /// Our own fullscreen: landscape, no bar, the site's player and its controls.
    @State private var fullscreen = false

    private var landscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            if !landscape && !fullscreen { topBar }
            ZStack(alignment: .bottom) {
                Color.black
                if let startURL {
                    BrowserView(controller: web, startURL: startURL, rules: rules,
                                playerOnly: playerOnly && current != nil, playerParam: site.playerParam,
                                nativeFullscreen: nativeFullscreen)
                } else if started {
                    Text("Couldn't build a link to the site.").foregroundStyle(.secondary)
                } else {
                    ProgressView().tint(.white)
                }
                if let upNext {
                    upNextCard(upNext)
                } else if let next = suggestedPlayer {
                    fallbackBanner(next)
                } else if let toast {
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if landscape || fullscreen { floatingControls }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .sheet(isPresented: $showEpisodes) {
            if let request = current {
                EpisodePicker(title: request.title, seasons: seasons, playing: request) { picked in
                    showEpisodes = false
                    go(to: picked)
                }
            }
        }
        .onAppear { Orientation.allow(.allButUpsideDown) }
        .onDisappear {
            fallbackTask?.cancel()
            countdownTask?.cancel()
            web.teardown()
            Orientation.allow(.portrait)
        }
    }

    // MARK: Controls

    private var topBar: some View {
        HStack(spacing: 18) {
            closeButton
            Button { web.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!web.canGoBack)
            Button { web.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
            Text(current?.displayName ?? site.domain)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if web.blocked > 0 {
                Label("\(web.blocked)", systemImage: "shield.lefthalf.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(web.blocked) pop-ups blocked")
            }
            if current != nil { playerMenu }
            if current?.title.type == .tv { episodeButtons }
            fullscreenButton
            moreMenu
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    /// Landscape: small buttons over the video instead of a bar.
    private var floatingControls: some View {
        HStack(spacing: 16) {
            closeButton
            if current != nil { playerMenu }
            if current?.title.type == .tv { episodeButtons }
            fullscreenButton
            moreMenu
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.leading, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var episodeButtons: some View {
        Button { showEpisodes = true } label: { Image(systemName: "list.bullet.rectangle") }
            .accessibilityLabel("Episodes")
        if let next = current?.next(in: seasons) {
            Button { go(to: next) } label: { Image(systemName: "forward.end.fill") }
                .accessibilityLabel("Next episode, \(next.episodeLabel ?? "")")
        }
    }

    private var fullscreenButton: some View {
        Button {
            setFullscreen(!fullscreen)
        } label: {
            Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityLabel(fullscreen ? "Exit full screen" : "Full screen")
    }

    private func setFullscreen(_ on: Bool) {
        guard on != fullscreen else { return }
        withAnimation { fullscreen = on }
        Orientation.rotate(to: on ? .landscapeRight : .portrait)
    }

    private var closeButton: some View {
        Button { dismiss() } label: { Image(systemName: "xmark") }
            .accessibilityLabel("Close")
    }

    private var playerCount: Int {
        web.detectedPlayers >= 2 ? web.detectedPlayers : site.playerCount
    }

    private var playerMenu: some View {
        Menu {
            ForEach(1...max(playerCount, player), id: \.self) { n in
                Button {
                    switchPlayer(to: n)
                } label: {
                    if n == player {
                        Label("Player \(n)", systemImage: "checkmark")
                    } else {
                        Text("Player \(n)")
                    }
                }
            }
        } label: {
            Label("P\(player)", systemImage: "play.rectangle")
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.bold))
        }
        .accessibilityLabel("Player \(player)")
    }

    private var moreMenu: some View {
        Menu {
            if current != nil {
                Button {
                    playerOnly.toggle()
                    web.setPlayerOnly(playerOnly)
                } label: {
                    if playerOnly {
                        Label("Show full page", systemImage: "rectangle.expand.vertical")
                    } else {
                        Label("Player only", systemImage: "play.rectangle.fill")
                    }
                }
            }
            Button {
                openInBrave()
            } label: {
                Label("Open in Brave", systemImage: "arrow.up.forward.app")
            }
            Button {
                UIPasteboard.general.url = web.currentURL
            } label: {
                Label("Copy link", systemImage: "link")
            }
            if current != nil {
                Button(role: .destructive) {
                    forgetLink()
                } label: {
                    Label("Forget saved page for this", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func fallbackBanner(_ next: Int) -> some View {
        HStack(spacing: 12) {
            Text("Not playing?").font(.footnote.weight(.semibold))
            Button("Try Player \(next)") { switchPlayer(to: next) }
                .font(.footnote.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Button {
                withAnimation { suggestedPlayer = nil }
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold))
            }
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func upNextCard(_ next: PlayRequest) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up next · \(next.episodeLabel ?? "")").font(.footnote.weight(.bold))
                Text("Playing in \(countdown)s").font(.caption).foregroundStyle(.secondary)
            }
            Button("Play now") { playNext() }
                .font(.footnote.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Button {
                cancelUpNext()
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold))
            }
            .accessibilityLabel("Cancel autoplay")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Setup

    private func start() async {
        guard !started else { return }
        current = visit.request
        rules = await AdBlocker.shared.rules()

        let site = self.site
        web.isAllowed = { url in site.isSiteURL(url) }
        web.onVideo = { event in handle(event) }
        web.onURLChange = { url in urlChanged(url) }
        web.onFullscreen = { exitOnly in setFullscreen(exitOnly ? false : !fullscreen) }

        if let request = current {
            Library.markWatched(request, progress: Library.existingProgress(key: request.progressKey, in: context),
                                in: context)
        }
        var url = visit.url ?? link(for: current)
        if let request = current, let link = url {
            // Start on the player that last worked for this title.
            player = PlayerPrefs.player(for: request.title.key) ?? site.player(in: link) ?? 1
            url = site.url(link, player: player)
            armFallback()
        }
        startURL = url
        started = true

        // Episode counts, so autoplay knows what comes next.
        if let request = current, request.title.type == .tv, let client = TMDB.client(userKey: tmdbKey) {
            let all = (try? await client.show(request.title.tmdbID).seasons) ?? []
            let regular = all.filter { $0.seasonNumber > 0 }
            seasons = regular.isEmpty ? all : regular
        }
    }

    /// Remembered page first, then domain.json's template, then a site search.
    private func link(for request: PlayRequest?) -> URL? {
        guard let request else { return site.homeURL }
        if let path = Library.existingProgress(key: request.progressKey, in: context)?.sitePath,
           let url = site.url(path: path) {
            return url
        }
        return site.link(for: request)
    }

    // MARK: Players

    private func switchPlayer(to n: Int) {
        guard let url = web.currentURL ?? startURL else { return }
        player = n
        withAnimation { suggestedPlayer = nil }
        web.load(site.url(url, player: n))
        armFallback()
    }

    /// If nothing plays within 15 seconds, offer the next player.
    private func armFallback() {
        fallbackTask?.cancel()
        sawVideo = false
        suggestedPlayer = nil
        fallbackTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, !sawVideo else { return }
            let next = player + 1
            if next <= playerCount {
                withAnimation { suggestedPlayer = next }
            }
        }
    }

    // MARK: Autoplay next episode

    private func startUpNext(after request: PlayRequest) {
        guard autoplayNext, promptedKey != request.progressKey,
              let next = request.next(in: seasons) else { return }
        promptedKey = request.progressKey
        countdownTask?.cancel()
        countdown = 10
        withAnimation { upNext = next }
        countdownTask = Task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                countdown -= 1
            }
            playNext()
        }
    }

    private func playNext() {
        guard let next = upNext else { return }
        go(to: next)
    }

    /// Switches to another episode on the current player.
    private func go(to request: PlayRequest) {
        countdownTask?.cancel()
        withAnimation { upNext = nil }
        current = request
        Library.markWatched(request, progress: Library.existingProgress(key: request.progressKey, in: context),
                            in: context)
        guard let link = link(for: request) else { return }
        web.load(site.url(link, player: player))
        armFallback()
    }

    private func cancelUpNext() {
        countdownTask?.cancel()
        withAnimation { upNext = nil }
    }

    // MARK: Playback events

    private func handle(_ event: VideoEvent) {
        guard let request = current else { return }
        let progress = Library.progress(for: request, in: context)

        if !sawVideo {
            sawVideo = true
            fallbackTask?.cancel()
            withAnimation { suggestedPlayer = nil }
            PlayerPrefs.set(player, for: request.title.key)
        }

        if event.kind == "ready" {
            // Only resume a video about as long as the saved one, so a long ad
            // doesn't swallow the resume.
            let similar = progress.duration <= 0
                || abs(event.duration - progress.duration) < max(120, progress.duration * 0.1)
            if resumedKey != request.progressKey, similar {
                resumedKey = request.progressKey
                if progress.position > 30, progress.position < event.duration - 60, !progress.isFinished {
                    web.seek(to: progress.position, in: event.frame)
                    show("Resumed at \(Format.time(progress.position))")
                }
            }
        } else {
            progress.position = event.kind == "ended" ? event.duration : event.time
            progress.duration = event.duration
            progress.updatedAt = .now
            // Into the last 15 seconds (or the credits ran out): offer the next
            // one. Under 10 minutes is more likely an ad than an episode.
            if event.duration >= 600, event.kind == "ended" || event.duration - event.time <= 15 {
                startUpNext(after: request)
            }
        }

        // The first time something plays, remember the page it played on.
        if progress.sitePath == nil, let url = web.currentURL, let path = site.learnablePath(from: url) {
            progress.sitePath = path
        }
        Library.markWatched(request, progress: progress, in: context)
    }

    /// Tracks the site's own player buttons and in-site episode changes.
    private func urlChanged(_ url: URL) {
        if let n = site.player(in: url), n != player {
            player = n
            armFallback()
        }
        guard let request = current, request.title.type == .tv,
              let found = site.episode(in: url, tmdbID: request.title.tmdbID),
              found.season != request.season || found.episode != request.episode else { return }
        let next = PlayRequest(title: request.title, season: found.season, episode: found.episode)
        current = next
        armFallback()
        Library.markWatched(next, progress: Library.existingProgress(key: next.progressKey, in: context), in: context)
    }

    // MARK: Menu actions

    private func openInBrave() {
        guard let url = web.currentURL ?? startURL,
              let brave = URL(string: "brave://open-url?url=" + url.absoluteString) else { return }
        UIApplication.shared.open(brave)
    }

    private func forgetLink() {
        guard let request = current,
              let progress = Library.existingProgress(key: request.progressKey, in: context) else { return }
        progress.sitePath = nil
        show("Saved page forgotten")
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

/// The player number that last worked, per title.
enum PlayerPrefs {
    private static func key(_ titleKey: String) -> String { "player.\(titleKey)" }

    static func player(for titleKey: String) -> Int? {
        let n = UserDefaults.standard.integer(forKey: key(titleKey))
        return n > 0 ? n : nil
    }

    static func set(_ player: Int, for titleKey: String) {
        UserDefaults.standard.set(player, forKey: key(titleKey))
    }
}

private struct BrowserView: UIViewRepresentable {
    let controller: WebController
    let startURL: URL
    let rules: WKContentRuleList?
    let playerOnly: Bool
    let playerParam: String
    let nativeFullscreen: Bool

    func makeUIView(context: Context) -> WKWebView {
        controller.makeWebView(startURL: startURL, rules: rules, playerOnly: playerOnly, playerParam: playerParam,
                               nativeFullscreen: nativeFullscreen)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
