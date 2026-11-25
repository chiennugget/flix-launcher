import SwiftData
import SwiftUI

/// Profile tab: Continue Watching, My List, then titles you've liked.
struct MyFlixView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ratings: RatingStore
    @Environment(\.zoomNamespace) private var zoom
    @AppStorage(Keys.profileName) private var profileName = "You"
    @State private var showSettings = false
    @State private var path = NavigationPath()

    @Query(filter: #Predicate<LibraryItem> { $0.inHistory == true },
           sort: \LibraryItem.lastWatchedAt, order: .reverse)
    private var history: [LibraryItem]

    @Query(filter: #Predicate<LibraryItem> { $0.inWatchlist == true },
           sort: \LibraryItem.watchlistAddedAt, order: .reverse)
    private var watchlist: [LibraryItem]

    @Query private var allItems: [LibraryItem]

    private var liked: [LibraryItem] {
        let keys = ratings.likedKeys
        return allItems.filter { keys.contains($0.key) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        Color.clear.frame(height: 40)
                        profile
                        if !history.isEmpty {
                            ContinueRow(items: Array(history.prefix(20)))
                        }
                        myList
                        if !liked.isEmpty {
                            likedRow
                        }
                        Color.clear.frame(height: 90)
                    }
                }
                .scrollIndicators(.hidden)
                header
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { _ in MyListGrid() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var header: some View {
        HStack {
            Text("My Flix").font(.system(size: 26, weight: .heavy))
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 21, weight: .medium))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.6)).ignoresSafeArea(edges: .top)
        }
    }

    private var profile: some View {
        VStack(spacing: 10) {
            AvatarView().frame(width: 74, height: 74)
            Text(Profile.name(profileName))
                .font(.system(size: 21, weight: .heavy))
                .lineLimit(1)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private var myList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("My List").font(.system(size: 18, weight: .bold))
                Spacer()
                if !watchlist.isEmpty {
                    Button("See All") { path.append("mylist") }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.7))
                }
            }
            .padding(.horizontal, 16)
            if watchlist.isEmpty {
                Text("Tap + My List on any title to save it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 7) {
                        ForEach(watchlist) { item in
                            PosterButton(title: item.asTitle, sourceID: "me-list-\(item.key)",
                                         rank: HomeModel.todayRanks[item.key])
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var likedRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            RowHeader(name: "TV Shows & Movies You've Liked")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(liked) { item in
                        let id = "me-liked-\(item.key)"
                        VStack(spacing: 7) {
                            Button {
                                router.open(item.asTitle, from: id)
                            } label: {
                                Color.clear
                                    .frame(width: 150, height: 84)
                                    .overlay { PosterImage(path: item.backdropPath ?? item.posterPath, name: item.name, size: "w300") }
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .zoomSource(id, in: zoom)
                            }
                            .buttonStyle(PressableStyle())
                            ShareLink(item: URL(string: "https://www.themoviedb.org/\(item.typeRaw)/\(item.tmdbID)")!) {
                                Label("Share", systemImage: "paperplane")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .frame(width: 150, height: 30)
                                    .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Everything in My List, as a grid. Long-press a poster to remove it.
struct MyListGrid: View {
    @EnvironmentObject private var router: Router
    @Environment(\.zoomNamespace) private var zoom

    @Query(filter: #Predicate<LibraryItem> { $0.inWatchlist == true },
           sort: \LibraryItem.watchlistAddedAt, order: .reverse)
    private var watchlist: [LibraryItem]

    var body: some View {
        ScrollView {
            if watchlist.isEmpty {
                Text("Your list is empty.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 80)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(watchlist) { item in
                    PosterButton(title: item.asTitle, sourceID: "grid-\(item.key)", width: nil)
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation { item.inWatchlist = false }
                            } label: {
                                Label("Remove from My List", systemImage: "minus.circle")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Color.clear.frame(height: 100)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.inline)
    }
}
