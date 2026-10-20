import Foundation

/// Movie and show info from The Movie Database (free API key).
enum TMDB {
    static var bundledKey: String {
        let key = (Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String) ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A client for the key typed in Settings, or the one built into the app.
    static func client(userKey: String) -> TMDBClient? {
        let typed = userKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typed.isEmpty ? bundledKey : typed
        guard !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return TMDBClient(apiKey: key)
    }

    static func image(_ path: String?, size: String = "w342") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

enum TMDBError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(401): return "TMDB rejected the API key. Check it in Settings."
        case .http(let code): return "TMDB returned an error (HTTP \(code))."
        }
    }
}

struct TMDBClient {
    let apiKey: String

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: "https://api.themoviedb.org/3" + path)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "language", value: "en-US"))
        // Accepts either the short v3 "API key" or the long v4 "read access token".
        let isToken = apiKey.hasPrefix("eyJ")
        if !isToken { items.append(URLQueryItem(name: "api_key", value: apiKey)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isToken { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw TMDBError.http(status) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func titles(_ path: String, _ query: [String: String] = [:], type: MediaType? = nil) async throws -> [Title] {
        let page: TMDBPage = try await get(path, query)
        return page.titles(defaultType: type)
    }

    func search(_ text: String) async throws -> [Title] {
        try await titles("/search/multi", ["query": text, "include_adult": "false"])
    }

    func movie(_ id: Int) async throws -> MovieDetail { try await get("/movie/\(id)") }
    func show(_ id: Int) async throws -> ShowDetail { try await get("/tv/\(id)") }
    func season(_ id: Int, _ number: Int) async throws -> SeasonDetail { try await get("/tv/\(id)/season/\(number)") }
}

struct TMDBPage: Decodable {
    let results: [TMDBItem]

    func titles(defaultType: MediaType?) -> [Title] {
        results.compactMap { $0.title(defaultType: defaultType) }
    }
}

struct TMDBItem: Decodable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?

    func title(defaultType: MediaType?) -> Title? {
        guard let type = mediaType.flatMap(MediaType.init(rawValue:)) ?? defaultType,
              let label = title ?? name else { return nil }
        let date = releaseDate ?? firstAirDate ?? ""
        return Title(tmdbID: id, type: type, name: label, overview: overview ?? "",
                     posterPath: posterPath, backdropPath: backdropPath,
                     year: date.count >= 4 ? String(date.prefix(4)) : nil,
                     rating: voteAverage)
    }
}

struct Genre: Decodable, Hashable {
    let id: Int
    let name: String
}

struct MovieDetail: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let voteAverage: Double?
    let genres: [Genre]?
}

struct ShowDetail: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let numberOfSeasons: Int?
    let voteAverage: Double?
    let genres: [Genre]?
    let seasons: [SeasonSummary]?
}

struct SeasonSummary: Decodable, Hashable {
    let seasonNumber: Int
    let name: String?
    let episodeCount: Int?
}

struct SeasonDetail: Decodable {
    let episodes: [Episode]
}

struct Episode: Decodable, Identifiable, Hashable {
    let id: Int
    let episodeNumber: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let runtime: Int?
}
