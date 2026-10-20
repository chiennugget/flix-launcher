import SwiftUI

/// Opens the site in the player screen: a title, or a raw URL (nil = home page).
struct SiteVisit: Identifiable {
    let id = UUID()
    var request: PlayRequest?
    var url: URL?
}

struct RowEntry: Identifiable {
    let title: Title
    var caption: String?
    var fraction: Double?

    var id: String { title.key }
}

struct PosterImage: View {
    let path: String?
    let name: String
    var size = "w342"

    var body: some View {
        AsyncImage(url: TMDB.image(path, size: size)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.card
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(Theme.accent).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

struct PosterCard: View {
    let entry: RowEntry
    /// Fixed width for horizontal rows; nil fills a grid cell.
    var width: CGFloat? = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { PosterImage(path: entry.title.posterPath, name: entry.title.name) }
                .overlay(alignment: .bottom) {
                    if let f = entry.fraction, f > 0 {
                        ProgressBar(fraction: f).padding(.horizontal, 6).padding(.bottom, 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let caption = entry.caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

struct TitleRow: View {
    let name: String
    let entries: [RowEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.title) {
                            PosterCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct PosterGrid: View {
    let entries: [RowEntry]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 14) {
            ForEach(entries) { entry in
                NavigationLink(value: entry.title) {
                    PosterCard(entry: entry, width: nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

struct KeyMissingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Add a TMDB key for posters and search", systemImage: "key.fill").font(.headline)
            Text("It's free: sign up at themoviedb.org, open Settings → API, and paste the key into this app's Settings tab. Until then you can still open the site with the globe button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }
}

struct HeroView: View {
    let title: Title

    var body: some View {
        NavigationLink(value: title) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { PosterImage(path: title.backdropPath, name: title.name, size: "w780") }
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.name).font(.title.bold()).lineLimit(2)
                        Text([title.type == .movie ? "Movie" : "Series", title.year].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .clipped()
        }
        .buttonStyle(.plain)
    }
}
