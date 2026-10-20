import UIKit
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
final class WebController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    UIGestureRecognizerDelegate {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var blocked = 0
    /// Highest "Player N" the page itself offers, 0 if none were found.
    @Published private(set) var detectedPlayers = 0

    /// Shrinks the page to just its video player.
    private(set) var playerOnly = false

    private(set) weak var webView: WKWebView?
    var isAllowed: (URL) -> Bool = { _ in true }
    var onVideo: ((VideoEvent) -> Void)?
    var onURLChange: ((URL) -> Void)?
    /// The site's player asked to enter or leave fullscreen (only when the
    /// iPhone's own fullscreen player is turned off).
    var onFullscreen: ((_ exitOnly: Bool) -> Void)?
    /// Any tap on the page. The tap still reaches the page too.
    var onTap: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []

    var currentURL: URL? { webView?.url }

    func makeWebView(startURL: URL, rules: WKContentRuleList?, playerOnly: Bool, playerParam: String,
                     nativeFullscreen: Bool) -> WKWebView {
        self.playerOnly = playerOnly
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
        // Before the page's own scripts, so players pick up the replaced fullscreen calls.
        content.addUserScript(WKUserScript(
            source: "window.__flixNativeFullscreen = \(nativeFullscreen);\n" + Scripts.fullscreen,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let focusSetup = "window.__flixFocusDefault = \(playerOnly); window.__flixPlayerParam = '\(playerParam)';\n"
        content.addUserScript(WKUserScript(source: focusSetup + Scripts.focus, injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true))
        content.add(WeakScriptHandler(self), name: "flix")
        content.add(WeakScriptHandler(self), name: "flixPage")
        if let rules { content.add(rules) }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        let tap = UITapGestureRecognizer(target: self, action: #selector(pageTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        webView.addGestureRecognizer(tap)

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

    @objc private func pageTapped() {
        onTap?()
    }

    /// Watch taps alongside the page's own gestures, never instead of them.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func load(_ url: URL) {
        detectedPlayers = 0
        webView?.load(URLRequest(url: url))
    }

    func setPlayerOnly(_ on: Bool) {
        playerOnly = on
        applyPlayerOnly()
    }

    private func applyPlayerOnly() {
        webView?.evaluateJavaScript("window.__flixSetFocus && window.__flixSetFocus(\(playerOnly))",
                                    in: nil, in: .page, completionHandler: nil)
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyPlayerOnly()
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
        if message.name == "flixPage" {
            guard let body = message.body as? [String: Any] else { return }
            switch body["type"] as? String {
            case "players":
                if let count = (body["count"] as? NSNumber)?.intValue { detectedPlayers = count }
            case "fullscreen":
                onFullscreen?(body["mode"] as? String == "exit")
            default:
                break
            }
            return
        }
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
        // Keep video in the page (with the player's own controls and
        // captions) rather than the iPhone's fullscreen player.
        if (window.__flixNativeFullscreen !== true) {
          v.setAttribute('playsinline', '');
          v.setAttribute('webkit-playsinline', '');
        }
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
      // Inside player embeds only: start the video, or press the player's
      // own big play button if the video isn't there yet.
      var pokes = 0;
      var playButtons = '.jw-display-icon-display, .jw-icon-display, .vjs-big-play-button, ' +
        '.plyr__control--overlaid, .play-button, .play-btn, .playbtn, #play-button, ' +
        '[aria-label="Play"], [title="Play"]';
      function poke() {
        if (window === window.top || pokes++ > 10) return;
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) {
          var v = videos[i];
          if (!v.__flixStarted && v.paused && v.readyState >= 1) {
            v.__flixStarted = true;
            var p = v.play();
            if (p && p.catch) p.catch(function () {});
            return;
          }
          if (v.__flixStarted || !v.paused) return;
        }
        var button = document.querySelector(playButtons);
        if (button && !button.__flixClicked && button.offsetParent !== null) {
          button.__flixClicked = true;
          button.click();
        }
        setTimeout(poke, 1500);
      }
      scan();
      new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
      setTimeout(poke, 1200);
    })();
    """#

    /// Every frame, at document start. Unless the iPhone's own fullscreen
    /// player is wanted, replaces the fullscreen calls players make with a
    /// message to the app, which rotates and hides its bar instead. The
    /// site's player stays on screen with its own controls (captions etc.).
    static let fullscreen = #"""
    (function () {
      if (window.__flixFullscreenHooked || window.__flixNativeFullscreen === true) return;
      window.__flixFullscreenHooked = true;
      // The page never really goes fullscreen, so a player's own state
      // stays "not fullscreen" and its button keeps asking to enter: enter
      // toggles, exit always leaves.
      function ask(mode) {
        try { window.webkit.messageHandlers.flixPage.postMessage({ type: 'fullscreen', mode: mode }); } catch (e) {}
      }
      function enter() { ask('toggle'); return Promise.resolve(); }
      function exit() { ask('exit'); return Promise.resolve(); }
      var el = Element.prototype;
      el.requestFullscreen = enter;
      el.webkitRequestFullscreen = enter;
      el.webkitRequestFullScreen = enter;
      var video = HTMLVideoElement.prototype;
      video.webkitEnterFullscreen = function () { ask('toggle'); };
      video.webkitEnterFullScreen = video.webkitEnterFullscreen;
      document.exitFullscreen = exit;
      document.webkitExitFullscreen = exit;
      document.webkitCancelFullScreen = exit;
      var play = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () {
        if (this.tagName === 'VIDEO') {
          this.setAttribute('playsinline', '');
          this.setAttribute('webkit-playsinline', '');
        }
        return play.apply(this, arguments);
      };
    })();
    """#

    /// Main frame only. In player-only mode, pins the page's biggest player
    /// (iframe or video) to fill the screen and hides the rest. Also reports
    /// how many "Player N" choices the page offers.
    static let focus = #"""
    (function () {
      if (window.__flixFocusInstalled) return;
      window.__flixFocusInstalled = true;
      var on = window.__flixFocusDefault !== false;
      var param = window.__flixPlayerParam || 'p';
      var css = [
        'html.__flix_focus, html.__flix_focus body { overflow: hidden !important; background: #000 !important; }',
        'html.__flix_focus body > *:not(.__flix_keep) { visibility: hidden !important; }',
        'html.__flix_focus .__flix_keep { visibility: visible !important; transform: none !important; ' +
          'filter: none !important; perspective: none !important; contain: none !important; ' +
          'will-change: auto !important; opacity: 1 !important; z-index: 2147483647 !important; }',
        'html.__flix_focus .__flix_player { position: fixed !important; top: 0 !important; left: 0 !important; ' +
          'right: 0 !important; bottom: 0 !important; width: 100vw !important; height: 100vh !important; ' +
          'max-width: none !important; max-height: none !important; min-width: 0 !important; ' +
          'min-height: 0 !important; margin: 0 !important; padding: 0 !important; border: 0 !important; ' +
          'background: #000 !important; }'
      ].join('\n');

      function post(msg) {
        try { window.webkit.messageHandlers.flixPage.postMessage(msg); } catch (e) {}
      }
      function ensureStyle() {
        if (document.getElementById('__flix_focus_style') || !document.head) return;
        var style = document.createElement('style');
        style.id = '__flix_focus_style';
        style.textContent = css;
        document.head.appendChild(style);
      }
      function score(el) {
        var src = (el.getAttribute('src') || el.currentSrc || '').toLowerCase();
        if (/youtube|youtu\.be|vimeo/.test(src)) return 0;
        var r = el.getBoundingClientRect();
        if (r.width < 200 || r.height < 110) return 0;
        var s = r.width * r.height;
        var allow = (el.getAttribute('allow') || '') + (el.hasAttribute('allowfullscreen') ? ' fullscreen' : '');
        if (/fullscreen|autoplay/.test(allow)) s *= 3;
        if (/embed|player|stream|play|vid/.test(src)) s *= 2;
        return s;
      }
      function pick() {
        var best = null, bestScore = 0;
        var els = document.querySelectorAll('iframe, video');
        for (var i = 0; i < els.length; i++) {
          var s = score(els[i]);
          if (s > bestScore) { best = els[i]; bestScore = s; }
        }
        return best;
      }
      function clear() {
        var marked = document.querySelectorAll('.__flix_player, .__flix_keep');
        for (var i = 0; i < marked.length; i++) marked[i].classList.remove('__flix_player', '__flix_keep');
      }
      function countPlayers() {
        var max = 0;
        var els = document.querySelectorAll('a[href], button, [role="button"], li, option');
        var hrefRe = new RegExp('[?&]' + param + '=(\\d{1,2})(?:&|$)');
        for (var i = 0; i < els.length; i++) {
          var el = els[i], n = 0;
          var text = (el.textContent || '').trim();
          var m = text.length < 24 && /^(?:player|server|source)\s*#?\s*(\d{1,2})$/i.exec(text);
          if (m) n = parseInt(m[1], 10);
          if (!n && el.tagName === 'A') {
            var h = hrefRe.exec(el.getAttribute('href') || '');
            if (h) n = parseInt(h[1], 10);
          }
          if (n > max) max = n;
        }
        return max;
      }
      var lastCount = -1;
      function apply() {
        var root = document.documentElement;
        if (!root) return;
        var count = countPlayers();
        if (count !== lastCount) { lastCount = count; post({ type: 'players', count: count }); }
        if (!on) { root.classList.remove('__flix_focus'); return; }
        ensureStyle();
        var best = pick();
        if (!best) { root.classList.remove('__flix_focus'); return; }
        if (!best.classList.contains('__flix_player')) {
          clear();
          best.classList.add('__flix_player', '__flix_keep');
          for (var p = best.parentElement; p && p !== document.body && p !== root; p = p.parentElement) {
            p.classList.add('__flix_keep');
          }
        }
        root.classList.add('__flix_focus');
      }
      var pending = null;
      function schedule() {
        if (pending) return;
        pending = setTimeout(function () { pending = null; apply(); }, 250);
      }
      window.__flixSetFocus = function (value) { on = !!value; apply(); };
      apply();
      new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
      var ticks = 0;
      var timer = setInterval(function () { apply(); if (++ticks > 30) clearInterval(timer); }, 1000);
    })();
    """#
}
