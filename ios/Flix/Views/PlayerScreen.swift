import SwiftData
import SwiftUI
import WebKit

/// The site, full screen, with ad blocking, rotation and progress tracking.
/// For a title it shows just the site's video player under Flix's own
/// Netflix-style controls, which drive the site's video. The site's own
/// controls are one menu item away.
struct PlayerScreen: View {
    let visit: SiteVisit
    /// Removes the screen once it has faded out.
    let onClose: () -> Void

    @EnvironmentObject private var site: SiteService
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
    /// Our own fullscreen for the site's controls: landscape, no bar.
    @State private var fullscreen = false
    /// Controls fade out on their own and come back on a tap.
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    /// Fades and zooms the whole screen in on open and out on close.
    @State private var appeared = false
    /// The loading cover hides redirects and the page rearranging itself
    /// until the video is ready.
    @State private var loading = true
    @State private var loadingLimitTask: Task<Void, Never>?
    @State private var revealTask: Task<Void, Never>?

    // Flix controls
    /// The user switched to the site's own player controls.
    @State private var siteControls = false
    @State private var videoFrame: WKFrameInfo?
    @State private var videoTime: Double = 0
    @State private var videoDuration: Double = 0
    @State private var videoPaused = false
    @State private var videoRate: Double = 1
    @State private var scrubbing: Double?
    @State private var panel: PlayerPanel?
    @State private var tracks: MediaTracks?
    @State private var locked = false
    @State private var lockArmed = false
    @State private var lockHintTask: Task<Void, Never>?
    @State private var lockPillVisible = false
    @State private var certification: String?
    @State private var genreLine: String?
    @State private var episodeNames: [String: String] = [:]
    @State private var showRating = false
    @State private var ratedShown = false
    @State private var brightness: CGFloat = 0.5
    @State private var originalBrightness: CGFloat?
    @State private var backBounce = 0
    @State private var forwardBounce = 0
    @State private var lastSave = Date.distantPast

    init(visit: SiteVisit, onClose: @escaping () -> Void) {
        self.visit = visit
        self.onClose = onClose
        // Set now so the loading cover shows the title from the first frame.
        _current = State(initialValue: visit.request)
    }

    private var landscape: Bool { verticalSizeClass == .compact }

    /// Flix's controls are on for a title shown player-only in the page.
    private var flixControls: Bool {
        current != nil && playerOnly && !siteControls && !nativeFullscreen
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
            content
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .onAppear {
            Orientation.allow(.allButUpsideDown)
            if visit.request != nil, !nativeFullscreen {
                // Netflix turns the phone sideways for video.
                Orientation.rotate(to: .landscapeRight)
            }
            if let screen = Self.screen {
                originalBrightness = screen.brightness
                brightness = screen.brightness
            }
            withAnimation(.spring(duration: 0.4, bounce: 0)) { appeared = true }
        }
        .onChange(of: landscape || fullscreen, initial: true) { showControls() }
        // The site's own control bar hides while Flix's controls are on.
        .onChange(of: flixControls, initial: true) { web.setSiteControlsHidden(flixControls) }
        // Captions move up while Flix's scrubber and buttons cover the bottom.
        .onChange(of: flixControls && controlsVisible && !loading) { _, lifted in web.setCaptionsLifted(lifted) }
        .onChange(of: scrubbing == nil) {
            if scrubbing != nil { hideControlsTask?.cancel() }
        }
        .onDisappear {
            fallbackTask?.cancel()
            countdownTask?.cancel()
            hideControlsTask?.cancel()
            loadingLimitTask?.cancel()
            revealTask?.cancel()
            lockHintTask?.cancel()
            saveNow()
            web.teardown()
            if let originalBrightness { Self.screen?.brightness = originalBrightness }
            Orientation.allow(.portrait)
        }
    }

    private static var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
    }

    private var content: some View {
        VStack(spacing: 0) {
            if !flixControls && !landscape && !fullscreen { topBar }
            webArea
        }
        .ignoresSafeArea(.container, edges: flixControls ? .all : [])
        .overlay(alignment: .topLeading) {
            if !flixControls && (landscape || fullscreen) {
                floatingControls
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    // No tap gesture on the bar itself: with a simultaneous
                    // TapGesture here, the bar's Buttons stopped responding
                    // in the iOS 27 simulator (its Menus still opened).
            }
        }
        .overlay {
            if flixControls { flixOverlay }
        }
        .overlay(alignment: .bottom) { notices }
        .background(Color.black.ignoresSafeArea())
    }

    private var webArea: some View {
        ZStack {
            Color.black
            if let startURL {
                BrowserView(controller: web, startURL: startURL, rules: rules,
                            playerOnly: playerOnly && current != nil, playerParam: site.playerParam,
                            nativeFullscreen: nativeFullscreen)
            } else if started {
                Text("Couldn't build a link to the site.").foregroundStyle(.secondary)
            }
            if loading {
                loadingCover
                    .transition(.opacity)
            }
        }
    }

    // MARK: Loading cover

    private var loadingCover: some View {
        ZStack {
            // The artwork is an overlay so its fill size never sizes the cover.
            // (Inside the ZStack it made the cover taller than a landscape
            // screen, pushing the close button half off the top.)
            Color.black
                .overlay {
                    if let path = current?.title.backdropPath ?? current?.title.posterPath {
                        AsyncImage(url: TMDB.image(path, size: "w1280")) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.black
                            }
                        }
                        .blur(radius: 24)
                        .opacity(0.45)
                    }
                }
                .clipped()
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 8) {
                if let current {
                    Text(current.title.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let episode = current.episodeLabel {
                        Text(episode)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(.top, 14)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            // Only when no bar above already offers a close button (opening the
            // site itself showed two X's, one under the other).
            if flixControls || landscape || fullscreen {
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 14)
                .padding(.top, 10)
                .accessibilityLabel("Close")
            }
        }
    }

    /// Shows the cover for a new page. It lifts once the video is ready, or
    /// after 8 seconds so the site's own play button can be tapped.
    private func beginLoading() {
        revealTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { loading = true }
        loadingLimitTask?.cancel()
        loadingLimitTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            revealPage()
        }
    }

    /// Lifts the cover after a short pause, unless another page starts loading first.
    private func revealSoon(after seconds: Double) {
        guard loading else { return }
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            revealPage()
        }
    }

    private func revealPage() {
        revealTask?.cancel()
        loadingLimitTask?.cancel()
        guard loading else { return }
        withAnimation(.easeInOut(duration: 0.45)) { loading = false }
        showControls(for: 3.2)
        scheduleRatingBadge()
    }

    // MARK: Flix controls

    @ViewBuilder
    private var flixOverlay: some View {
        ZStack {
            if locked {
                lockLayer
            } else {
                controlsLayer
                    .opacity(controlsVisible && panel == nil && !loading ? 1 : 0)
                    .allowsHitTesting(controlsVisible && panel == nil && !loading)
                if showRating && !controlsVisible && panel == nil {
                    ratingBadge
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if let panel {
                panelView(panel)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .animation(.spring(duration: 0.4, bounce: 0.05), value: panel)
    }

    private var controlsLayer: some View {
        ZStack {
            // A light dim through the middle keeps the white play/skip
            // buttons readable over bright scenes.
            LinearGradient(stops: [.init(color: .black.opacity(0.65), location: 0),
                                   .init(color: .black.opacity(0.3), location: 0.28),
                                   .init(color: .black.opacity(0.3), location: 0.6),
                                   .init(color: .black.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { hideControls() }
            VStack(spacing: 0) {
                controlsTopRow
                Spacer(minLength: 0)
                controlsCenterRow
                Spacer(minLength: 0)
                PlayerScrubber(time: videoTime, duration: videoDuration, scrubbing: $scrubbing) { seek(to: $0) }
                controlsBottomRow
                    .padding(.top, landscape ? 8 : 14)
            }
            .padding(.horizontal, landscape ? 20 : 16)
            .padding(.top, landscape ? 12 : 8)
            .padding(.bottom, landscape ? 10 : 18)
            if landscape {
                BrightnessSlider(value: $brightness) {
                    Self.screen?.brightness = brightness
                    showControls()
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)
                .offset(y: -18)
            }
        }
        .foregroundStyle(.white)
    }

    private var controlsTopRow: some View {
        HStack(spacing: 20) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 22, weight: .semibold))
            }
            .accessibilityLabel("Close")
            Text(titleLine)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            if current != nil, playerCount > 1 { playerMenu }
            Button {
                lock()
            } label: {
                Image(systemName: "lock.open").font(.system(size: 19, weight: .medium))
            }
            .accessibilityLabel("Lock screen")
            moreMenu
        }
        .frame(height: 44)
    }

    private var controlsCenterRow: some View {
        HStack(spacing: landscape ? 100 : 56) {
            Button {
                backBounce += 1
                skip(-10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 36, weight: .regular))
                    .symbolEffect(.bounce.down, value: backBounce)
                    .frame(width: 60, height: 60)
            }
            .accessibilityLabel("Back 10 seconds")
            Button {
                togglePlay()
            } label: {
                Image(systemName: videoPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 50))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
            }
            .accessibilityLabel(videoPaused ? "Play" : "Pause")
            Button {
                forwardBounce += 1
                skip(10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 36, weight: .regular))
                    .symbolEffect(.bounce.down, value: forwardBounce)
                    .frame(width: 60, height: 60)
            }
            .accessibilityLabel("Forward 10 seconds")
        }
        .buttonStyle(PressableStyle(scale: 0.88))
    }

    private var controlsBottomRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            bottomButton("gauge.with.dots.needle.33percent", "Speed (\(SpeedPanel.label(videoRate))x)") { open(.speed) }
            if current?.title.type == .tv {
                Spacer(minLength: 0)
                bottomButton("rectangle.stack", "Episodes") { open(.episodes) }
            }
            Spacer(minLength: 0)
            bottomButton("captions.bubble", "Audio & Subtitles") { open(.audio) }
            if let next = current?.next(in: seasons) {
                Spacer(minLength: 0)
                bottomButton("forward.end", "Next Episode") { go(to: next) }
            }
            Spacer(minLength: 0)
        }
    }

    private func bottomButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 19))
                if landscape {
                    Text(label).font(.system(size: 13.5, weight: .semibold)).fixedSize()
                }
            }
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    private var titleLine: String {
        guard let current else { return site.domain }
        guard let s = current.season, let e = current.episode else { return current.title.name }
        if let name = episodeNames["\(s):\(e)"], !name.isEmpty {
            return "S\(s):E\(e) “\(name)”"
        }
        return "\(current.title.name) · S\(s):E\(e)"
    }

    private var ratingBadge: some View {
        HStack(spacing: 10) {
            Text("RATED").font(.system(size: 15, weight: .bold))
            if let certification { RatingBadge(text: certification) }
            if let genreLine {
                Text(genreLine).font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.9))
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(width: 3)
        }
        .foregroundStyle(.white)
        .padding(.leading, 30)
        .padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func scheduleRatingBadge() {
        guard flixControls, !ratedShown, certification != nil || genreLine != nil else { return }
        ratedShown = true
        Task {
            try? await Task.sleep(for: .seconds(3.6))
            withAnimation(.easeOut(duration: 0.4)) { showRating = true }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeIn(duration: 0.4)) { showRating = false }
        }
    }

    private var lockLayer: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { flashLockPill() }
            if lockPillVisible {
                Button {
                    unlockTapped()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: lockArmed ? "lock.open.fill" : "lock.fill")
                            .contentTransition(.symbolEffect(.replace))
                        Text(lockArmed ? "Tap again to unlock" : "Screen Locked")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.bottom, 34)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func panelView(_ p: PlayerPanel) -> some View {
        switch p {
        case .speed:
            SpeedPanel(rate: videoRate) { rate in
                setRate(rate)
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    closePanel()
                }
            } onClose: {
                closePanel()
            }
        case .audio:
            AudioSubtitlesPanel(tracks: tracks) { index in
                send("text", Double(index))
                if let t = tracks {
                    tracks = MediaTracks(text: t.text.map { .init(i: $0.i, l: $0.l, on: $0.i == index) }, audio: t.audio)
                }
            } onAudio: { index in
                send("audio", Double(index))
                if let t = tracks {
                    tracks = MediaTracks(text: t.text, audio: t.audio.map { .init(i: $0.i, l: $0.l, on: $0.i == index) })
                }
            } onSiteControls: {
                closePanel()
                withAnimation { siteControls = true }
                show("Showing the site's controls")
            } onClose: {
                closePanel()
            }
        case .episodes:
            if let request = current {
                EpisodesPanel(title: request.title, seasons: seasons, playing: request) { picked in
                    closePanel()
                    go(to: picked)
                } onClose: {
                    closePanel()
                }
                .transition(.opacity)
            }
        }
    }

    private func open(_ p: PlayerPanel) {
        hideControlsTask?.cancel()
        if p == .audio {
            tracks = nil
            Task {
                if let frame = videoFrame {
                    let found = await web.tracks(in: frame)
                    tracks = found
                } else {
                    tracks = MediaTracks()
                }
            }
        }
        panel = p
    }

    private func closePanel() {
        panel = nil
        showControls()
    }

    // MARK: Driving the video

    private func send(_ name: String, _ arg: Double = 0) {
        guard let frame = videoFrame else {
            show("The video hasn't started yet")
            return
        }
        web.command(name, arg, in: frame)
    }

    private func togglePlay() {
        send("toggle")
        withAnimation(.easeOut(duration: 0.15)) { videoPaused.toggle() }
        showControls()
    }

    private func skip(_ seconds: Double) {
        send("skip", seconds)
        videoTime = min(max(0, videoTime + seconds), max(videoDuration - 1, 0))
        showControls()
    }

    private func seek(to seconds: Double) {
        send("seek", seconds)
        videoTime = seconds
        scrubbing = nil
        showControls()
    }

    private func setRate(_ rate: Double) {
        send("rate", rate)
        videoRate = rate
    }

    private func lock() {
        hideControlsTask?.cancel()
        withAnimation { locked = true }
        flashLockPill()
    }

    private func flashLockPill() {
        withAnimation(.spring(duration: 0.35)) { lockPillVisible = true }
        lockHintTask?.cancel()
        lockHintTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                lockPillVisible = false
                lockArmed = false
            }
        }
    }

    private func unlockTapped() {
        if lockArmed {
            lockHintTask?.cancel()
            withAnimation {
                locked = false
                lockArmed = false
                lockPillVisible = false
            }
            showControls()
        } else {
            flashLockPill()
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { lockArmed = true }
        }
    }

    // MARK: Site-controls layout (no title, full page, or the site's own controls)

    private var topBar: some View {
        HStack(spacing: 18) {
            closeButton
            Button { web.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!web.canGoBack)
                .accessibilityLabel("Back")
            Button { web.reload() } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("Reload")
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
            if current?.title.type == .tv, let next = current?.next(in: seasons) {
                Button { go(to: next) } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next episode, \(next.episodeLabel ?? "")")
            }
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
            if current?.title.type == .tv, let next = current?.next(in: seasons) {
                Button { go(to: next) } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next episode, \(next.episodeLabel ?? "")")
            }
            fullscreenButton
            if current != nil, playerOnly, siteControls, !nativeFullscreen {
                Button {
                    withAnimation { siteControls = false }
                    showControls()
                } label: {
                    Text("Flix controls").font(.footnote.weight(.bold))
                }
            }
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

    private var fullscreenButton: some View {
        Button {
            setFullscreen(!fullscreen)
        } label: {
            Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .accessibilityLabel(fullscreen ? "Exit full screen" : "Full screen")
    }

    /// Shows the controls, then fades them after a few seconds unless paused.
    private func showControls(for seconds: Double = 4) {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible = true }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, !(flixControls && videoPaused), scrubbing == nil, panel == nil else { return }
            withAnimation(.easeIn(duration: 0.3)) { controlsVisible = false }
        }
    }

    private func hideControls() {
        hideControlsTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { controlsVisible = false }
    }

    private func toggleControls() {
        if locked {
            flashLockPill()
        } else if controlsVisible {
            hideControls()
        } else {
            showControls()
        }
    }

    private func setFullscreen(_ on: Bool) {
        guard on != fullscreen else { return }
        withAnimation { fullscreen = on }
        Orientation.rotate(to: on ? .landscapeRight : .portrait)
    }

    private var closeButton: some View {
        Button { close() } label: { Image(systemName: "xmark") }
            .accessibilityLabel("Close")
    }

    /// Fades out (back to portrait first), then removes the screen.
    private func close() {
        web.webView?.pauseAllMediaPlayback(completionHandler: nil)
        Orientation.allow(.portrait)
        withAnimation(.easeIn(duration: 0.25)) {
            appeared = false
        } completion: {
            onClose()
        }
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
            if current != nil, playerOnly, !nativeFullscreen {
                Button {
                    withAnimation { siteControls.toggle() }
                    showControls()
                } label: {
                    if siteControls {
                        Label("Use Flix controls", systemImage: "slider.horizontal.below.rectangle")
                    } else {
                        Label("Use the site's controls", systemImage: "hand.tap")
                    }
                }
            }
            if current != nil {
                Button {
                    playerOnly.toggle()
                    web.setPlayerOnly(playerOnly)
                    revealPage()
                } label: {
                    if playerOnly {
                        Label("Show full page", systemImage: "rectangle.expand.vertical")
                    } else {
                        Label("Player only", systemImage: "play.rectangle.fill")
                    }
                }
            }
            Button {
                web.reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
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
            Image(systemName: flixControls ? "ellipsis" : "ellipsis.circle")
                .font(.system(size: flixControls ? 20 : 17, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if let upNext {
            upNextButton(upNext)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
                .padding(.bottom, flixControls && controlsVisible ? 92 : 28)
        } else if let next = suggestedPlayer {
            fallbackBanner(next)
        } else if let toast {
            Text(toast)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .padding(.bottom, flixControls && controlsVisible ? 100 : 24)
                .transition(.opacity)
        }
    }

    private func fallbackBanner(_ next: Int) -> some View {
        HStack(spacing: 12) {
            Text("Not playing?").font(.footnote.weight(.semibold))
            Button {
                switchPlayer(to: next)
            } label: {
                // Fixed size: the bordered style otherwise truncated it to "Try Play…".
                Text("Try Player \(next)").fixedSize()
            }
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
        .environment(\.colorScheme, .dark)
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Netflix's white "Next Episode" button, filling up as the countdown runs.
    private func upNextButton(_ next: PlayRequest) -> some View {
        HStack(spacing: 10) {
            Button {
                playNext()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Next Episode")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Color.white
                            Color(white: 0.8)
                                .frame(width: geo.size.width * CGFloat(10 - countdown) / 10)
                                .animation(.linear(duration: 1), value: countdown)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Play next episode, \(next.episodeLabel ?? ""), in \(countdown) seconds")
            Button {
                cancelUpNext()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("Cancel autoplay")
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
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
        web.onFullscreen = { exitOnly in
            // With Flix's controls the screen is already full; the site's
            // fullscreen button just turns the phone.
            if flixControls {
                Orientation.rotate(to: landscape ? .portrait : .landscapeRight)
            } else {
                setFullscreen(exitOnly ? false : !fullscreen)
            }
        }
        web.onTap = { toggleControls() }
        web.onReload = {
            resetVideoState()
            if current != nil { beginLoading() }
        }
        web.onPageStart = { revealTask?.cancel() }
        web.onPageFinish = {
            // Without player-only mode there's no player to wait for: show the
            // page once it has loaded and isn't redirecting again.
            if current == nil || !web.playerOnly { revealSoon(after: 0.6) }
        }
        web.onPlayerFocused = { revealSoon(after: 1.2) }

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
        if url != nil { beginLoading() } else { loading = false }
        startURL = url
        started = true

        // Episode counts (so autoplay knows what comes next), the age rating
        // and the current episode's name.
        guard let request = current, let client = TMDB.client(userKey: tmdbKey) else { return }
        switch request.title.type {
        case .tv:
            if let show = try? await client.showFull(request.title.tmdbID) {
                let all = show.seasons ?? []
                let regular = all.filter { $0.seasonNumber > 0 }
                seasons = regular.isEmpty ? all : regular
                certification = show.certification
                genreLine = show.genres?.prefix(3).map(\.name).joined(separator: ", ")
            }
            if let s = request.season { await loadEpisodeNames(season: s) }
        case .movie:
            if let movie = try? await client.movieFull(request.title.tmdbID) {
                certification = movie.certification
                genreLine = movie.genres?.prefix(3).map(\.name).joined(separator: ", ")
            }
        }
    }

    private func loadEpisodeNames(season: Int) async {
        guard let request = current, episodeNames["\(season):1"] == nil,
              let client = TMDB.client(userKey: tmdbKey),
              let episodes = try? await client.season(request.title.tmdbID, season).episodes else { return }
        for ep in episodes {
            episodeNames["\(ep.seasonNumber):\(ep.episodeNumber)"] = ep.name ?? ""
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
        resetVideoState()
        beginLoading()
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

    /// A new page or player is loading: forget the old video, and let the
    /// saved position be applied again once the new one is ready. (Without
    /// this, switching players started over at 0:00 and then overwrote the
    /// saved position.)
    private func resetVideoState() {
        videoFrame = nil
        videoTime = 0
        videoDuration = 0
        videoRate = 1
        scrubbing = nil
        resumedKey = nil
    }

    // MARK: Autoplay next episode

    private func startUpNext(after request: PlayRequest) {
        guard autoplayNext, promptedKey != request.progressKey,
              let next = request.next(in: seasons) else { return }
        promptedKey = request.progressKey
        countdownTask?.cancel()
        countdown = 10
        withAnimation(.spring(duration: 0.4)) { upNext = next }
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
        if let s = request.season { Task { await loadEpisodeNames(season: s) } }
        guard let link = link(for: request) else { return }
        resetVideoState()
        beginLoading()
        web.load(site.url(link, player: player))
        armFallback()
    }

    private func cancelUpNext() {
        countdownTask?.cancel()
        withAnimation { upNext = nil }
    }

    // MARK: Playback events

    private func handle(_ event: VideoEvent) {
        revealSoon(after: 0.3)
        videoFrame = event.frame
        videoDuration = event.duration
        if scrubbing == nil { videoTime = event.time }
        if event.paused != videoPaused {
            withAnimation(.easeOut(duration: 0.15)) { videoPaused = event.paused }
        }
        videoRate = event.rate
        guard let request = current else { return }

        if !sawVideo {
            sawVideo = true
            fallbackTask?.cancel()
            withAnimation { suggestedPlayer = nil }
            PlayerPrefs.set(player, for: request.title.key)
        }
        // Ticks only feed the scrubber; progress is saved from the slower events.
        if event.kind == "tick" { return }
        let progress = Library.progress(for: request, in: context)

        if event.kind == "ready" {
            // Only resume a video about as long as the saved one, so a long ad
            // doesn't swallow the resume.
            let similar = progress.duration <= 0
                || abs(event.duration - progress.duration) < max(120, progress.duration * 0.1)
            if resumedKey != request.progressKey, similar {
                resumedKey = request.progressKey
                if progress.position > 30, progress.position < event.duration - 60, !progress.isFinished {
                    web.seek(to: progress.position, in: event.frame)
                    videoTime = progress.position
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
        // SwiftData only autosaves on its own schedule (or when the app goes to
        // the background), so a crash or a kill mid-film lost the resume point.
        if event.kind != "progress" || Date.now.timeIntervalSince(lastSave) > 30 { saveNow() }
    }

    private func saveNow() {
        lastSave = .now
        try? context.save()
    }

    /// Tracks the site's own player buttons and in-site episode changes.
    private func urlChanged(_ url: URL) {
        if let n = site.player(in: url), n != player {
            player = n
            resetVideoState()
            armFallback()
        }
        guard let request = current, request.title.type == .tv,
              let found = site.episode(in: url, tmdbID: request.title.tmdbID),
              found.season != request.season || found.episode != request.episode else { return }
        let next = PlayRequest(title: request.title, season: found.season, episode: found.episode)
        current = next
        cancelUpNext()
        resetVideoState()
        armFallback()
        Task { await loadEpisodeNames(season: found.season) }
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
