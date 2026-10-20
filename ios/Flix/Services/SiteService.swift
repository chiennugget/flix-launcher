import Foundation

/// The shape of domain.json in this repo.
struct SiteConfig: Codable {
    var domain: String?
    var pinned: Bool?
    var updated: String?
    var name: String?
    var mirrors: [String]?
    var paths: SitePaths?
}

/// Link templates for the site, e.g. "/movie/{id}". Placeholders: {id} (TMDB
/// id), {slug}, {title}, {year}, {season}, {episode}, {query}.
struct SitePaths: Codable, Equatable {
    var movie: String?
    var tv: String?
    var search: String?
}

/// Knows the site's current address and how to build links into it.
///
/// Reads domain.json (kept up to date by the GitHub checker) first. If the
/// address there doesn't look live, it follows redirects and "now available
/// at" banners from known mirrors itself, like check_domain.py does.
@MainActor
final class SiteService: ObservableObject {
    @Published private(set) var domain: String
    @Published private(set) var name: String
    @Published private(set) var paths: SitePaths
    @Published private(set) var updated: Date?
    @Published private(set) var status = "Finding the current address…"
    @Published private(set) var checking = false

    static let builtInMirrors = ["flixbaba.best", "flixbaba.mov", "flixbaba.com", "flixbaba.cx", "flixbabax.com"]
    private var mirrors: [String]
    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        domain = defaults.string(forKey: "site.domain") ?? "flixbaba.best"
        name = defaults.string(forKey: "site.name") ?? "flixbaba"
        mirrors = defaults.stringArray(forKey: "site.mirrors") ?? []
        updated = defaults.object(forKey: "site.updated") as? Date
        if let data = defaults.data(forKey: "site.paths"),
           let saved = try? JSONDecoder().decode(SitePaths.self, from: data) {
            paths = saved
        } else {
            paths = SitePaths(search: "/search?q={query}")
        }
    }

    // MARK: Finding the address

    func refresh() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        status = "Finding the current address…"

        let config = await fetchConfig()
        if let config { apply(config) }
        if config?.pinned == true {
            status = "Set by hand in domain.json"
            return
        }

        let resolver = DomainResolver(name: name)
        let candidate = domain
        if await resolver.check(candidate) == .live {
            status = config == nil ? "Live (couldn't reach domain.json)" : "Live, checked just now"
            return
        }

        status = "Checking mirrors…"
        var starts = [candidate]
        for m in mirrors + Self.builtInMirrors where !starts.contains(m) { starts.append(m) }
        if let found = await resolver.search(from: starts), found != candidate {
            setDomain(found)
            status = "Site moved: found \(found)"
        } else {
            // Never switch when unsure; the site may just be behind a bot check.
            status = config == nil ? "Offline: using the saved address" : "Couldn't confirm it's up; using domain.json"
        }
    }

    private func fetchConfig() async -> SiteConfig? {
        var sources: [String] = []
        if let custom = defaults.string(forKey: Keys.configURL)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            sources.append(custom)
        }
        sources += [Keys.defaultConfigURL, Keys.rawConfigURL]

        for source in sources {
            guard var components = URLComponents(string: source) else { continue }
            let bust = URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
            components.queryItems = (components.queryItems ?? []) + [bust]
            guard let url = components.url else { continue }
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            guard let result = try? await URLSession.shared.data(for: request),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let config = try? JSONDecoder().decode(SiteConfig.self, from: result.0),
                  !DomainResolver.clean(config.domain ?? "").isEmpty else { continue }
            return config
        }
        return nil
    }

    private func apply(_ config: SiteConfig) {
        if let d = config.domain { setDomain(DomainResolver.clean(d)) }
        if let n = config.name?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty {
            name = n
            defaults.set(n, forKey: "site.name")
        }
        if let m = config.mirrors {
            mirrors = m.map(DomainResolver.clean).filter { !$0.isEmpty }
            defaults.set(mirrors, forKey: "site.mirrors")
        }
        if let p = config.paths {
            paths = p
            defaults.set(try? JSONEncoder().encode(p), forKey: "site.paths")
        }
        if let u = config.updated, let date = ISO8601DateFormatter().date(from: u) {
            updated = date
            defaults.set(date, forKey: "site.updated")
        }
    }

    private func setDomain(_ d: String) {
        guard !d.isEmpty else { return }
        domain = d
        defaults.set(d, forKey: "site.domain")
    }

    // MARK: Links

    var homeURL: URL? { URL(string: "https://\(domain)/") }

    func url(path: String) -> URL? {
        if path.lowercased().hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://\(domain)" + (path.hasPrefix("/") ? path : "/" + path))
    }

    /// Best guess at a link: the template for this type, else a site search,
    /// else the home page.
    func link(for request: PlayRequest) -> URL? {
        let template = request.title.type == .movie ? paths.movie : paths.tv
        if let t = template?.trimmingCharacters(in: .whitespaces), !t.isEmpty,
           let url = url(path: Template.fill(t, request.variables)) {
            return url
        }
        return searchURL(request.title.name) ?? homeURL
    }

    func searchURL(_ text: String) -> URL? {
        guard let t = paths.search?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return url(path: Template.fill(t, ["query": text, "title": text]))
    }

    func isSiteURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain) || host.contains(name)
    }

    /// The path to remember for a title once its video plays, or nil if this
    /// is the home page or a search page.
    func learnablePath(from url: URL) -> String? {
        guard isSiteURL(url) else { return nil }
        let path = url.path
        guard !path.isEmpty, path != "/" else { return nil }
        if let search = paths.search {
            let prefix = String(search.prefix { $0 != "?" && $0 != "{" })
            if prefix.count > 1, path.hasPrefix(prefix) { return nil }
        }
        if let query = url.query, !query.isEmpty { return path + "?" + query }
        return path
    }

    /// Season and episode from a site URL, using the tv template.
    func episode(in url: URL, tmdbID: Int) -> (season: Int, episode: Int)? {
        guard let t = paths.tv?.trimmingCharacters(in: .whitespaces), !t.isEmpty,
              isSiteURL(url), let regex = Template.regex(for: t) else { return nil }
        var text = url.path
        if let query = url.query { text += "?" + query }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ name: String) -> Int? {
            let r = match.range(withName: name)
            guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
            return Int(text[range])
        }
        if let id = group("id"), id != tmdbID { return nil }
        guard let season = group("season"), let episode = group("episode") else { return nil }
        return (season, episode)
    }
}

enum Template {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#/")
        return set
    }()

    static func fill(_ template: String, _ values: [String: String]) -> String {
        var out = template
        for (key, value) in values {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            out = out.replacingOccurrences(of: "{\(key)}", with: encoded)
        }
        return out
    }

    /// Turns "/tv/{id}/{season}/{episode}" into a regex with named groups.
    static func regex(for template: String) -> NSRegularExpression? {
        var pattern = "^"
        var literal = ""
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{", let close = template[i...].firstIndex(of: "}") {
                pattern += NSRegularExpression.escapedPattern(for: literal)
                literal = ""
                let key = String(template[template.index(after: i)..<close])
                switch key {
                case "id", "season", "episode": pattern += "(?<\(key)>\\d+)"
                default: pattern += "[^/?&#]*"
                }
                i = template.index(after: close)
            } else {
                literal.append(template[i])
                i = template.index(after: i)
            }
        }
        pattern += NSRegularExpression.escapedPattern(for: literal)
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

/// Swift port of check_domain.py's detection logic.
struct DomainResolver {
    enum Check: Equatable { case live, moved, unknown }

    struct Page {
        let final: String
        let status: Int
        let html: String
    }

    let name: String
    private let banner: NSRegularExpression?
    private let titleTag = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>",
                                                    options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let maxHops = 4
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    init(name: String) {
        self.name = name
        let n = NSRegularExpression.escapedPattern(for: name)
        let domain = "([a-z0-9-]*\(n)[a-z0-9-]*\\.[a-z]{2,24})"
        banner = try? NSRegularExpression(
            pattern: "now\\s+(?:available|moved)\\s+(?:at|to)\\s*(?:<[^>]*>\\s*)*" + domain,
            options: [.caseInsensitive])
    }

    static func clean(_ domain: String) -> String {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.hasPrefix("https://") { d.removeFirst(8) } else if d.hasPrefix("http://") { d.removeFirst(7) }
        if let slash = d.firstIndex(of: "/") { d = String(d[..<slash]) }
        if d.hasPrefix("www.") { d.removeFirst(4) }
        return d
    }

    func probe(_ domain: String) async -> Page? {
        guard let url = URL(string: "https://\(domain)/") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        let http = result.1 as? HTTPURLResponse
        return Page(final: Self.clean(http?.url?.host ?? domain),
                    status: http?.statusCode ?? 0,
                    html: String(decoding: result.0.prefix(400_000), as: UTF8.self))
    }

    private func firstGroup(_ regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex,
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    func looksLikeSite(_ page: Page) -> Bool {
        guard page.status == 200, let title = firstGroup(titleTag, in: page.html) else { return false }
        return title.lowercased().contains(name)
    }

    /// Where this page says the site moved to, or nil.
    func pointer(from domain: String, _ page: Page) -> String? {
        if let target = firstGroup(banner, in: page.html).map(Self.clean), target != domain {
            return target
        }
        if page.final != domain, page.final.contains(name) { return page.final }
        return nil
    }

    func check(_ domain: String) async -> Check {
        guard let page = await probe(domain) else { return .unknown }
        if pointer(from: domain, page) != nil { return .moved }
        return looksLikeSite(page) ? .live : .unknown
    }

    /// Follows redirects and banners from start until a live, unmoved site.
    func resolve(_ start: String) async -> String? {
        var seen = Set<String>()
        var domain = start
        for _ in 0..<Self.maxHops {
            guard seen.insert(domain).inserted, let page = await probe(domain) else { return nil }
            guard let next = pointer(from: domain, page) else {
                return looksLikeSite(page) ? domain : nil
            }
            domain = next
        }
        return nil
    }

    /// The address most of the starting points lead to.
    func search(from starts: [String]) async -> String? {
        var votes: [String: Int] = [:]
        var order: [String] = []
        for start in starts where !start.isEmpty {
            guard let found = await resolve(start) else { continue }
            votes[found, default: 0] += 1
            if !order.contains(found) { order.append(found) }
        }
        return order.max { (votes[$0] ?? 0) < (votes[$1] ?? 0) }
    }
}
