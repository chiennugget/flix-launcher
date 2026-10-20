import WebKit

/// Compiles the bundled ad blocklist once and shares it with every web view.
@MainActor
final class AdBlocker {
    static let shared = AdBlocker()
    private var task: Task<WKContentRuleList?, Never>?

    func rules() async -> WKContentRuleList? {
        if task == nil {
            task = Task { await Self.compile() }
        }
        return await task?.value
    }

    private static func compile() async -> WKContentRuleList? {
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "flix-blocklist", encodedContentRuleList: json
            ) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }
}

struct VideoEvent {
    let kind: String
    let time: Double
    let duration: Double
    let frame: WKFrameInfo
}

/// Owns the site's web view: blocks pop-ups and off-site redirects, and
/// relays video playback events from every frame.
@MainActor
final class WebController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var blocked = 0

    private(set) weak var webView: WKWebView?
    var isAllowed: (URL) -> Bool = { _ in true }
    var onVideo: ((VideoEvent) -> Void)?
    var onURLChange: ((URL) -> Void)?
    private var observations: [NSKeyValueObservation] = []

    var currentURL: URL? { webView?.url }

    func makeWebView(startURL: URL, rules: WKContentRuleList?) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = true

        let content = config.userContentController
        content.addUserScript(WKUserScript(source: Scripts.video, injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: false))
        content.add(WeakScriptHandler(self), name: "flix")
        if let rules { content.add(rules) }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    if let url = view.url { self?.onURLChange?(url) }
                }
            },
        ]

        self.webView = webView
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func seek(to seconds: Double, in frame: WKFrameInfo) {
        webView?.evaluateJavaScript("window.__flixSeek && window.__flixSeek(\(seconds))",
                                    in: frame, in: .page, completionHandler: nil)
    }

    func teardown() {
        observations = []
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: Navigation rules

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
        // App Store links, intent:// and other app-launching redirects.
        guard scheme == "http" || scheme == "https" else {
            blocked += 1
            return .cancel
        }
        // Embedded players live on other domains; only the page itself is fenced in.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame || isAllowed(url) { return .allow }
        blocked += 1
        return .cancel
    }

    /// window.open and target=_blank: pop-ups are dropped, same-site links open in place.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, isAllowed(url), navigationAction.navigationType == .linkActivated {
            webView.load(navigationAction.request)
        } else {
            blocked += 1
        }
        return nil
    }

    // MARK: Video events

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let kind = body["type"] as? String,
              let time = (body["t"] as? NSNumber)?.doubleValue,
              let duration = (body["d"] as? NSNumber)?.doubleValue,
              time.isFinite, duration.isFinite, duration > 0 else { return }
        onVideo?(VideoEvent(kind: kind, time: time, duration: duration, frame: message.frameInfo))
    }
}

/// Breaks the retain cycle between WKUserContentController and its handler.
@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

enum Scripts {
    /// Injected into every frame, including cross-site player embeds. Reports
    /// playback of real videos (over a minute, so short ad clips are ignored)
    /// and exposes __flixSeek for resuming.
    static let video = #"""
    (function () {
      if (window.__flixHooked) return;
      window.__flixHooked = true;
      function post(msg) {
        try { window.webkit.messageHandlers.flix.postMessage(msg); } catch (e) {}
      }
      var hooked = new WeakSet();
      function hook(v) {
        if (hooked.has(v)) return;
        hooked.add(v);
        var last = 0;
        function report(kind) {
          if (!isFinite(v.duration) || v.duration < 60) return;
          post({ type: kind, t: v.currentTime, d: v.duration });
        }
        v.addEventListener('loadedmetadata', function () { report('ready'); });
        v.addEventListener('durationchange', function () { report('ready'); });
        v.addEventListener('timeupdate', function () {
          var now = Date.now();
          if (now - last > 5000) { last = now; report('progress'); }
        });
        v.addEventListener('pause', function () { report('progress'); });
        v.addEventListener('ended', function () { report('ended'); });
        if (v.readyState >= 1) report('ready');
      }
      function scan() {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) hook(videos[i]);
      }
      window.__flixSeek = function (t) {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) {
          var v = videos[i];
          if (isFinite(v.duration) && v.duration >= 60 && t < v.duration - 10) v.currentTime = t;
        }
      };
      scan();
      new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """#
}
