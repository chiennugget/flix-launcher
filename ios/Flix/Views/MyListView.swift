import SwiftData
import SwiftUI

struct MyListView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<LibraryItem> { $0.inWatchlist == true },
           sort: \LibraryItem.watchlistAddedAt, order: .reverse)
    private var watchlist: [LibraryItem]

    @Query(filter: #Predicate<LibraryItem> { $0.inHistory == true },
           sort: \LibraryItem.lastWatchedAt, order: .reverse)
    private var history: [LibraryItem]

    var body: some View {
        NavigationStack {
            List {
                Section("My List") {
                    if watchlist.isEmpty {
                        Text("Tap “My List” on any title to save it here.").foregroundStyle(.secondary)
                    }
                    ForEach(watchlist) { item in
                        NavigationLink(value: item.asTitle) {
                            LibraryRow(item: item, caption: item.year)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { item.inWatchlist = false }
                        }
                    }
                }
                Section("Recently Watched") {
                    if history.isEmpty {
                        Text("Things you play show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(history) { item in
                        NavigationLink(value: item.asTitle) {
                            LibraryRow(item: item, caption: item.resumeLabel)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { item.inHistory = false }
                        }
                    }
                }
            }
            .navigationTitle("My List")
            .navigationDestination(for: Title.self) { TitleDetailView(title: $0) }
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let caption: String?

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 50, height: 75)
                .overlay { PosterImage(path: item.posterPath, name: item.name, size: "w185") }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline).lineLimit(2)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                if item.inHistory, item.resumeFraction > 0, item.resumeFraction < 0.95 {
                    ProgressBar(fraction: item.resumeFraction).frame(maxWidth: 140)
                }
            }
        }
    }
}
