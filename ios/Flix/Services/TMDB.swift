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
    /// With cast, age rating and recommendations, for the title page and player.
    func movieFull(_ id: Int) async throws -> MovieDetail {
        try await get("/movie/\(id)", ["append_to_response": "credits,release_dates,recommendations"])
    }
    func showFull(_ id: Int) async throws -> ShowDetail {
        try await get("/tv/\(id)", ["append_to_response": "credits,content_ratings,recommendations"])
    }
    func season(_ id: Int, _ number: Int) async throws -> SeasonDetail { try await get("/tv/\(id)/season/\(number)") }
}

struct TMDBPage: Decodable {
    let results: [TMDBItem]

    func titles(defaultType: MediaType?) -> [Title] {
        results.compactMap { $0.asTitle(defaultType: defaultType) }
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
    let genreIds: [Int]?

    func asTitle(defaultType: MediaType?) -> Title? {
        guard let type = mediaType.flatMap(MediaType.init(rawValue:)) ?? defaultType,
              let label = title ?? name else { return nil }
        let date = releaseDate ?? firstAirDate ?? ""
        return Title(tmdbID: id, type: type, name: label, overview: overview ?? "",
                     posterPath: posterPath, backdropPath: backdropPath,
                     year: date.count >= 4 ? String(date.prefix(4)) : nil,
                     rating: voteAverage, genreIDs: genreIds, date: date.isEmpty ? nil : date)
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
    let credits: Credits?
    let releaseDates: ReleaseDates?
    let recommendations: TMDBPage?

    /// US age rating, e.g. "PG-13".
    var certification: String? {
        let us = releaseDates?.results.first { $0.iso31661 == "US" }
        return us?.releaseDates.compactMap(\.certification).first { !$0.isEmpty }
    }
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
    let credits: Credits?
    let contentRatings: ContentRatings?
    let createdBy: [Person]?
    let recommendations: TMDBPage?

    /// US age rating, e.g. "TV-MA".
    var certification: String? {
        let rating = contentRatings?.results.first { $0.iso31661 == "US" }?.rating
        return rating?.isEmpty == false ? rating : nil
    }
}

struct Person: Decodable, Hashable {
    let name: String
    let job: String?
}

struct Credits: Decodable {
    let cast: [Person]?
    let crew: [Person]?
}

struct ReleaseDates: Decodable {
    struct Country: Decodable {
        let iso31661: String
        let releaseDates: [Entry]
    }
    struct Entry: Decodable {
        let certification: String?
    }
    let results: [Country]
}

struct ContentRatings: Decodable {
    struct Entry: Decodable {
        let iso31661: String
        let rating: String?
    }
    let results: [Entry]
}

/// TMDB's genre ids (movie and TV lists combined) and the home page's categories.
enum Genres {
    static let names: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary",
        18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 10770: "TV Movie", 53: "Thriller", 10752: "War",
        37: "Western", 10759: "Action", 10762: "Kids", 10763: "News", 10764: "Reality",
        10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics",
    ]

    static func tags(_ ids: [Int]?, limit: Int = 3) -> [String] {
        var seen = Set<String>()
        return (ids ?? []).compactMap { names[$0] }.filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
}

struct HomeCategory: Identifiable, Hashable {
    let name: String
    let movie: Int?
    let tv: Int?
    var id: String { name }

    static let all: [HomeCategory] = [
        HomeCategory(name: "Action", movie: 28, tv: 10759),
        HomeCategory(name: "Animation", movie: 16, tv: 16),
        HomeCategory(name: "Comedies", movie: 35, tv: 35),
        HomeCategory(name: "Crime", movie: 80, tv: 80),
        HomeCategory(name: "Documentaries", movie: 99, tv: 99),
        HomeCategory(name: "Dramas", movie: 18, tv: 18),
        HomeCategory(name: "Family", movie: 10751, tv: 10751),
        HomeCategory(name: "Horror", movie: 27, tv: nil),
        HomeCategory(name: "Mystery", movie: 9648, tv: 9648),
        HomeCategory(name: "Reality TV", movie: nil, tv: 10764),
        HomeCategory(name: "Romance", movie: 10749, tv: nil),
        HomeCategory(name: "Sci-Fi & Fantasy", movie: 878, tv: 10765),
        HomeCategory(name: "Thrillers", movie: 53, tv: nil),
        HomeCategory(name: "Westerns", movie: 37, tv: 37),
    ]
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
