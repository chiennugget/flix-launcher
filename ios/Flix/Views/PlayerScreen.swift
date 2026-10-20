import SwiftData
import SwiftUI
import WebKit

/// The site, full screen, with ad blocking, rotation and progress tracking.
struct PlayerScreen: View {
    let visit: SiteVisit

    @EnvironmentObject private var site: SiteService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var web = WebController()

    @State private var startURL: URL?
    @State private var rules: WKContentRuleList?
    @State private var current: PlayRequest?
    @State private var resumedKey: String?
    @State private var toast: String?
    @State private var started = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                Color.black
                if let startURL {
                    BrowserView(controller: web, startURL: startURL, rules: rules)
                } else if started {
                    Text("Couldn't build a link to the site.").foregroundStyle(.secondary)
                } else {
                    ProgressView().tint(.white)
                }
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .onAppear { Orientation.allow(.allButUpsideDown) }
        .onDisappear {
            web.teardown()
            Orientation.allow(.portrait)
        }
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close")
            Button { web.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!web.canGoBack)
            Button { web.webView?.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!web.canGoForward)
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
            Menu {
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
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
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

        if let request = current {
            Library.markWatched(request, progress: Library.existingProgress(key: request.progressKey, in: context),
                                in: context)
        }
        startURL = visit.url ?? link(for: current)
        started = true
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

    // MARK: Playback events

    private func handle(_ event: VideoEvent) {
        guard let request = current else { return }
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
                    show("Resumed at \(Format.time(progress.position))")
                }
            }
        } else {
            progress.position = event.kind == "ended" ? event.duration : event.time
            progress.duration = event.duration
            progress.updatedAt = .now
        }

        // The first time something plays, remember the page it played on.
        if progress.sitePath == nil, let url = web.currentURL, let path = site.learnablePath(from: url) {
            progress.sitePath = path
        }
        Library.markWatched(request, progress: progress, in: context)
    }

    /// Follows in-site episode changes when an episode link template is set.
    private func urlChanged(_ url: URL) {
        guard let request = current, request.title.type == .tv,
              let found = site.episode(in: url, tmdbID: request.title.tmdbID),
              found.season != request.season || found.episode != request.episode else { return }
        let next = PlayRequest(title: request.title, season: found.season, episode: found.episode)
        current = next
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

private struct BrowserView: UIViewRepresentable {
    let controller: WebController
    let startURL: URL
    let rules: WKContentRuleList?

    func makeUIView(context: Context) -> WKWebView {
        controller.makeWebView(startURL: startURL, rules: rules)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
