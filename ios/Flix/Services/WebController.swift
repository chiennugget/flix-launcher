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

/// Starts WebKit's helper processes at launch, so the first video opens as
/// quickly as later ones. The blank view stays around to keep them warm.
@MainActor
enum WebWarmup {
    private static var view: WKWebView?

    static func start() {
        guard view == nil else { return }
        let webView = WKWebView(frame: .zero)
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        view = webView
    }
}

struct VideoEvent {
    let kind: String
    let time: Double
    let duration: Double
    var paused = false
    var rate = 1.0
    let frame: WKFrameInfo
}

/// Caption and audio tracks of the playing video, as the page reports them.
struct MediaTracks: Decodable {
    struct Track: Decodable, Identifiable, Hashable {
        let i: Int
        let l: String
        let on: Bool
        var id: Int { i }
    }

    var text: [Track] = []
    var audio: [Track] = []
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
    /// Hides the site player's own control bar inside its frames while Flix's
    /// controls are on, so the two sets don't sit on top of each other.
    private(set) var siteControlsHidden = false
    /// The page's other scripts, kept so the hide flag's script can be swapped.
    private var baseScripts: [WKUserScript] = []

    private(set) weak var webView: WKWebView?
    var isAllowed: (URL) -> Bool = { _ in true }
    var onVideo: ((VideoEvent) -> Void)?
    var onURLChange: ((URL) -> Void)?
    /// The site's player asked to enter or leave fullscreen (only when the
    /// iPhone's own fullscreen player is turned off).
    var onFullscreen: ((_ exitOnly: Bool) -> Void)?
    /// Any tap on the page. The tap still reaches the page too.
    var onTap: (() -> Void)?
    /// The main page started loading a new address (including redirects).
    var onPageStart: (() -> Void)?
    /// The main page finished loading.
    var onPageFinish: (() -> Void)?
    /// Player-only mode found the video player and pinned it full screen.
    var onPlayerFocused: (() -> Void)?
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
        let focusSetup = "window.__flixFocusDefault = \(playerOnly); window.__flixPlayerParam = '\(playerParam)';\n"
        baseScripts = [
            WKUserScript(source: Scripts.video, injectionTime: .atDocumentEnd, forMainFrameOnly: false),
            // Before the page's own scripts, so players pick up the replaced fullscreen calls.
            WKUserScript(source: "window.__flixNativeFullscreen = \(nativeFullscreen);\n" + Scripts.fullscreen,
                         injectionTime: .atDocumentStart, forMainFrameOnly: false),
            WKUserScript(source: focusSetup + Scripts.focus, injectionTime: .atDocumentEnd, forMainFrameOnly: true),
        ]
        installScripts(in: content)
        content.add(WeakScriptHandler(self), name: "flix")
        content.add(WeakScriptHandler(self), name: "flixPage")
        if let rules { content.add(rules) }

        let webView = EdgeToEdgeWebView(frame: .zero, configuration: config)
        // SwiftUI already places the view inside or over the safe area as each
        // layout needs. Letting WebKit inset the page again shifted it toward the
        // notch side in landscape, leaving uneven black bars around the video.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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

    /// Hides (true) or shows the site player's own controls, now in every
    /// frame and in frames that load later.
    func setSiteControlsHidden(_ hidden: Bool) {
        guard hidden != siteControlsHidden else { return }
        siteControlsHidden = hidden
        if let content = webView?.configuration.userContentController { installScripts(in: content) }
        webView?.evaluateJavaScript("window.__flixHideControls && window.__flixHideControls(\(hidden))",
                                    in: nil, in: .page, completionHandler: nil)
    }

    /// The hide flag goes first, so each frame's video script reads it on load.
    private func installScripts(in content: WKUserContentController) {
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(source: "window.__flixHideSiteControls = \(siteControlsHidden);",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: false))
        baseScripts.forEach(content.addUserScript)
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

    /// Drives the video in the frame that reported it: toggle, seek, skip,
    /// rate, text (caption track, -1 for off) or audio.
    func command(_ name: String, _ arg: Double = 0, in frame: WKFrameInfo) {
        webView?.evaluateJavaScript("window.__flixCmd && window.__flixCmd('\(name)', \(arg))",
                                    in: frame, in: .page, completionHandler: nil)
    }

    func tracks(in frame: WKFrameInfo) async -> MediaTracks {
        guard let webView else { return MediaTracks() }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.__flixCmd ? window.__flixCmd('tracks', 0) : ''",
                                       in: frame, in: .page) { result in
                if case .success(let value) = result, let text = value as? String,
                   let data = text.data(using: .utf8),
                   let tracks = try? JSONDecoder().decode(MediaTracks.self, from: data) {
                    continuation.resume(returning: tracks)
                } else {
                    continuation.resume(returning: MediaTracks())
                }
            }
        }
    }

    func teardown() {
        observations = []
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        // The callbacks capture the player screen, which owns this controller.
        onVideo = nil
        onURLChange = nil
        onFullscreen = nil
        onTap = nil
        onPageStart = nil
        onPageFinish = nil
        onPlayerFocused = nil
        onReload = nil
    }

    /// The page is starting over (reload, or WebKit restarted it).
    var onReload: (() -> Void)?

    /// Reloads the page, so the player can reset its video state first.
    func reload() {
        onReload?()
        detectedPlayers = 0
        if webView?.url != nil { webView?.reload() } else if let url = lastURL { webView?.load(URLRequest(url: url)) }
    }

    private var lastURL: URL?

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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url { lastURL = url }
        onPageStart?()
    }

    /// iOS can end the web process while the app is in the background (or it
    /// can crash), which leaves a blank black page. Load it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyPlayerOnly()
        onPageFinish?()
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
            case "focused":
                onPlayerFocused?()
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
        let paused = (body["p"] as? NSNumber)?.boolValue ?? false
        let rate = (body["r"] as? NSNumber)?.doubleValue ?? 1
        onVideo?(VideoEvent(kind: kind, time: time, duration: duration, paused: paused,
                            rate: rate.isFinite && rate > 0 ? rate : 1, frame: message.frameInfo))
    }
}

/// A web view that never reports a safe area, so WebKit lays the page out
/// over its whole frame and the player's letterboxing stays centred.
private final class EdgeToEdgeWebView: WKWebView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
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
    /// playback of real videos (over a minute, so short ad clips are ignored),
    /// with a quick "tick" for the app's scrubber, and exposes __flixSeek for
    /// resuming and __flixCmd for the app's own controls.
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
        var lastTick = 0;
        function report(kind) {
          if (!isFinite(v.duration) || v.duration < 60) return;
          post({ type: kind, t: v.currentTime, d: v.duration, p: v.paused ? 1 : 0, r: v.playbackRate || 1 });
        }
        function tick(force) {
          var now = Date.now();
          if (!force && now - lastTick < 500) return;
          lastTick = now;
          report('tick');
        }
        v.__flixTick = tick;
        v.addEventListener('loadedmetadata', function () { report('ready'); });
        v.addEventListener('durationchange', function () { report('ready'); });
        v.addEventListener('timeupdate', function () {
          tick(false);
          var now = Date.now();
          if (now - last > 5000) { last = now; report('progress'); }
        });
        v.addEventListener('play', function () { tick(true); });
        v.addEventListener('pause', function () { report('progress'); tick(true); });
        v.addEventListener('ratechange', function () { tick(true); });
        v.addEventListener('seeked', function () { tick(true); });
        v.addEventListener('ended', function () { report('ended'); });
        if (v.readyState >= 1) report('ready');
      }
      function scan() {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) hook(videos[i]);
      }
      function mainVideo() {
        var videos = document.getElementsByTagName('video'), best = null;
        for (var i = 0; i < videos.length; i++) {
          var v = videos[i];
          if (isFinite(v.duration) && v.duration >= 60 && (!best || v.duration > best.duration)) best = v;
        }
        return best;
      }
      function isText(t) { return t.kind === 'subtitles' || t.kind === 'captions'; }
      function trackList(v) {
        var out = { text: [], audio: [] };
        var tt = v.textTracks || [];
        for (var i = 0; i < tt.length; i++) {
          if (isText(tt[i])) {
            out.text.push({ i: i, l: tt[i].label || tt[i].language || ('Subtitles ' + (i + 1)), on: tt[i].mode === 'showing' });
          }
        }
        var at = v.audioTracks;
        if (at) {
          for (var j = 0; j < at.length; j++) {
            out.audio.push({ i: j, l: at[j].label || at[j].language || ('Audio ' + (j + 1)), on: !!at[j].enabled });
          }
        }
        return out;
      }
      window.__flixCmd = function (cmd, arg) {
        var v = mainVideo();
        if (!v) return '';
        if (cmd === 'tracks') return JSON.stringify(trackList(v));
        if (cmd === 'toggle') {
          if (v.paused) { var p = v.play(); if (p && p.catch) p.catch(function () {}); } else { v.pause(); }
        } else if (cmd === 'seek') {
          v.currentTime = Math.max(0, Math.min(v.duration - 1, arg));
        } else if (cmd === 'skip') {
          v.currentTime = Math.max(0, Math.min(v.duration - 1, v.currentTime + arg));
        } else if (cmd === 'rate') {
          v.playbackRate = arg;
        } else if (cmd === 'text') {
          var tt = v.textTracks || [];
          for (var k = 0; k < tt.length; k++) { if (isText(tt[k])) tt[k].mode = (k === arg) ? 'showing' : 'disabled'; }
        } else if (cmd === 'audio') {
          var at = v.audioTracks;
          if (at) { for (var j = 0; j < at.length; j++) at[j].enabled = (j === arg); }
        }
        if (v.__flixTick) v.__flixTick(true);
        return '';
      };
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
      // While Flix's own controls are on, hide the site player's control bar,
      // title, big play button and menus (captions and error messages stay).
      // Hidden by visibility, not display, so poke() can still press play.
      var hideCSS = [
        '.jw-controls', '.jw-controlbar', '.jw-title', '.jw-center', '.jw-bigplay', '.jw-display',
        '.jw-gradient', '.jw-upnext', '.jw-menu', '.jw-settings-menu', '.jw-nextup-container',
        '.vjs-control-bar', '.vjs-big-play-button', '.vjs-title-bar', '.vjs-menu',
        '.plyr__controls', '.plyr__control--overlaid', '.plyr__menu',
        '.media-control', '.dplayer-controller', '.dplayer-controller-mask', '.dplayer-bar-wrap',
        '.art-bottom', '.art-layer-top', '.mejs__controls', '.fluid_controls_container',
        // The embed wrapper's own title bar ("Show · S01 E01") over the player.
        '#vs-bar', '#vs-title'
      ].join(',') + ' { visibility: hidden !important; opacity: 0 !important; pointer-events: none !important; }' +
        ' video::-webkit-media-controls, video::-webkit-media-controls-start-playback-button' +
        ' { display: none !important; }';
      function applyHide(on) {
        var style = document.getElementById('flix-hide-controls');
        if (on && !style) {
          style = document.createElement('style');
          style.id = 'flix-hide-controls';
          style.textContent = hideCSS;
          (document.head || document.documentElement).appendChild(style);
        } else if (!on && style) {
          style.remove();
        }
      }
      // Frames are on other sites, so the setting travels down by postMessage.
      window.__flixHideControls = function (on) {
        window.__flixHideSiteControls = on;
        applyHide(on);
        for (var i = 0; i < window.frames.length; i++) {
          try { window.frames[i].postMessage({ __flixControls: on ? 'hide' : 'show' }, '*'); } catch (e) {}
        }
      };
      window.addEventListener('message', function (e) {
        var d = e.data;
        if (d && (d.__flixControls === 'hide' || d.__flixControls === 'show')) {
          window.__flixHideControls(d.__flixControls === 'hide');
        }
      });
      if (window.__flixHideSiteControls === true) applyHide(true);
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
      var reportedFocus = false;
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
        if (!reportedFocus) { reportedFocus = true; post({ type: 'focused' }); }
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
