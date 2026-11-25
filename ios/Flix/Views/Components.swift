import CoreImage
import SwiftData
import SwiftUI
import UIKit

/// Opens the site in the player screen: a title, or a raw URL (nil = home page).
struct SiteVisit: Identifiable {
    let id = UUID()
    var request: PlayRequest?
    var url: URL?
}

struct PosterImage: View {
    let path: String?
    let name: String
    var size = "w342"

    var body: some View {
        AsyncImage(url: TMDB.image(path, size: size), transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.12)
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
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.3))
                Rectangle().fill(Theme.accent).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// The red "TOP 10" corner tag.
struct Top10Badge: View {
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            Text("TOP").font(.system(size: 6.5 * scale, weight: .heavy)).kerning(0.3)
            Text("10").font(.system(size: 12 * scale, weight: .black)).kerning(-0.5)
        }
        .foregroundStyle(.white)
        .frame(width: 20 * scale, height: 27 * scale)
        .background(Theme.accent, in: UnevenRoundedRectangle(bottomLeadingRadius: 2))
        .accessibilityLabel("Top 10")
    }
}

/// Age rating, e.g. "TV-MA", in the orange Netflix-style box.
struct RatingBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(height: 17)
            .background(Theme.ratingBadge, in: RoundedRectangle(cornerRadius: 2))
    }
}

/// Scales down a little while pressed, like Netflix's tiles and buttons.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// Netflix's white "Play" and grey/glass secondary buttons.
struct FilledButton: View {
    let title: String
    let systemImage: String
    var white = true
    var height: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .foregroundStyle(white ? .black : .white)
                .background {
                    if white {
                        RoundedRectangle(cornerRadius: 7).fill(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 7).fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
                    }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}

struct PosterTile: View {
    let title: Title
    var rank: Int?
    /// Fixed width for rows; nil fills a grid cell.
    var width: CGFloat? = 110

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { PosterImage(path: title.posterPath, name: title.name) }
            .overlay(alignment: .topTrailing) {
                if let rank, rank <= 10 { Top10Badge() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .frame(width: width)
            .contentShape(Rectangle())
    }
}

/// A poster that opens its title page, zooming out of the poster on iOS 18.
struct PosterButton: View {
    let title: Title
    let sourceID: String
    var rank: Int?
    var width: CGFloat? = 110

    @EnvironmentObject private var router: Router
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        Button {
            router.open(title, from: sourceID)
        } label: {
            PosterTile(title: title, rank: rank, width: width)
                .zoomSource(sourceID, in: zoom)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title.name)
    }
}

struct RowHeader: View {
    let name: String
    var trailing: AnyView?

    var body: some View {
        HStack {
            Text(name).font(.system(size: 18, weight: .bold))
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
    }
}

struct TitleRow: View {
    let id: String
    let name: String
    let titles: [Title]
    var ranks: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RowHeader(name: name)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 7) {
                    ForEach(titles) { title in
                        PosterButton(title: title, sourceID: "\(id)-\(title.key)", rank: ranks[title.key])
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// "Top 10 Shows Today": big outlined numbers next to each poster.
struct Top10Row: View {
    let id: String
    let name: String
    let titles: [Title]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RowHeader(name: name)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(titles.prefix(10).enumerated()), id: \.element.id) { index, title in
                        HStack(alignment: .bottom, spacing: -18) {
                            OutlinedNumber(value: index + 1)
                            PosterButton(title: title, sourceID: "\(id)-\(title.key)", width: 100)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct OutlinedNumber: View {
    let value: Int

    var body: some View {
        let text = Text("\(value)").font(.system(size: 124, weight: .black)).kerning(-8)
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                text.foregroundStyle(Color(white: 0.42))
                    .offset(x: cos(angle) * 2.2, y: sin(angle) * 2.2)
            }
            text.foregroundStyle(.black)
        }
        .frame(height: 110, alignment: .bottom)
        .offset(y: 14)
        .accessibilityHidden(true)
    }
}

struct PosterGrid: View {
    let id: String
    let titles: [Title]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(titles) { title in
                PosterButton(title: title, sourceID: "\(id)-\(title.key)", width: nil)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Continue Watching: tap the poster to resume, ⓘ for the title page, ⋯ for more.
struct ContinueRow: View {
    let items: [LibraryItem]
    var name = "Continue Watching"

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RowHeader(name: name)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 7) {
                    ForEach(items) { item in
                        ContinueTile(item: item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct ContinueTile: View {
    let item: LibraryItem

    @EnvironmentObject private var router: Router
    @Environment(\.zoomNamespace) private var zoom

    private var sourceID: String { "cw-\(item.key)" }
    private var label: String? {
        guard let s = item.lastSeason, let e = item.lastEpisode else { return nil }
        return "S\(s):E\(e)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                router.play(PlayRequest(title: item.asTitle, season: item.lastSeason, episode: item.lastEpisode))
            } label: {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay { PosterImage(path: item.posterPath, name: item.name) }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                    .overlay(alignment: .bottom) {
                        if let label {
                            Text(label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(white: 0.86))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)
                                .padding(.bottom, 6)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                                           startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .clipped()
                    .zoomSource(sourceID, in: zoom)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Resume \(item.name)")

            ProgressBar(fraction: max(item.resumeFraction, 0.04))
            HStack {
                Button {
                    router.open(item.asTitle, from: sourceID)
                } label: {
                    Image(systemName: "info.circle").font(.system(size: 19))
                }
                .accessibilityLabel("Episodes and info")
                Spacer()
                Menu {
                    Button {
                        router.open(item.asTitle, from: sourceID)
                    } label: {
                        Label("Episodes & Info", systemImage: "info.circle")
                    }
                    Button(role: .destructive) {
                        withAnimation(.spring(duration: 0.35)) { item.inHistory = false }
                    } label: {
                        Label("Remove From Row", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).rotationEffect(.degrees(90))
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("More")
            }
            .foregroundStyle(Color(white: 0.86))
            .padding(.horizontal, 9)
            .frame(height: 36)
        }
        .frame(width: 110)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

struct KeyMissingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Add a TMDB key for posters and search", systemImage: "key.fill").font(.headline)
            Text("It's free: sign up at themoviedb.org, open Settings → API, and paste the key into Settings (My Flix → ☰). Until then you can still open the site with the globe button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}

/// The profile picture, drawn in code: a red tile with a friendly face.
struct AvatarView: View {
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.24), Color(red: 0.84, green: 0.1, blue: 0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color(red: 0.7, green: 0.06, blue: 0.18).opacity(0.55))
                    .frame(width: s * 1.6, height: s * 0.5)
                    .offset(y: s * 0.48)
                HStack(spacing: s * 0.12) {
                    eye(s)
                    eye(s)
                }
                .offset(y: -s * 0.05)
                SmileShape()
                    .stroke(Color(red: 0.1, green: 0.04, blue: 0.06), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
                    .frame(width: s * 0.22, height: s * 0.08)
                    .offset(y: s * 0.2)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private func eye(_ s: CGFloat) -> some View {
        Ellipse().fill(.white)
            .frame(width: s * 0.21, height: s * 0.27)
            .overlay(alignment: .center) {
                Circle().fill(Color(red: 0.1, green: 0.04, blue: 0.06))
                    .frame(width: s * 0.1)
                    .offset(x: s * 0.025, y: s * 0.03)
            }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return p
    }
}

/// Grey placeholder that shimmers while rows load.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.8)
                        .offset(x: phase * geo.size.width * 1.4)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

struct SkeletonRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.1)).frame(width: 150, height: 16)
                        .modifier(Shimmer())
                    HStack(spacing: 7) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.1))
                                .frame(width: 110, height: 165)
                                .modifier(Shimmer())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Glass rounded-rectangle chip, used for the home page's Series/Films pills.
struct GlassPill<Label: View>: View {
    var selected = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(white: 0.92))
                .padding(.horizontal, 13)
                .frame(height: 33)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(selected ? 0.85 : 0.2), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: Zoom transition (iOS 18) between a poster and its title page

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func zoomSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTransition(_ id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: Scroll position (iOS 17 has no scroll geometry callback)

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Reports how far a ScrollView has scrolled (0 at rest). iOS 18+ reads
    /// the scroll geometry directly: newer iOS versions no longer pass the
    /// ScrollOffsetReader preference out of the scroll view, so the value
    /// stayed 0 and the header never got its background. iOS 17 uses the reader.
    @ViewBuilder
    func onScrollOffsetChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, y in
                action(y)
            }
        } else {
            onPreferenceChange(ScrollOffsetKey.self, perform: action)
        }
    }
}

/// Put first in a ScrollView's content; reports how far it has scrolled (iOS 17).
struct ScrollOffsetReader: View {
    let space: String

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ScrollOffsetKey.self, value: -geo.frame(in: .named(space)).minY)
        }
        .frame(height: 0)
    }
}

// MARK: Poster colour, for the home page's tinted background

@MainActor
enum ImageTint {
    private static var cache: [String: Color] = [:]

    static func color(for path: String?) async -> Color? {
        guard let path, let url = TMDB.image(path, size: "w92") else { return nil }
        if let cached = cache[path] { return cached }
        guard let result = try? await URLSession.shared.data(from: url),
              let image = CIImage(data: result.0) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage",
                              parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8, colorSpace: nil)
        let average = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let color = Color(hue: Double(h), saturation: Double(min(1, s * 1.35)), brightness: Double(min(0.55, max(0.3, b))))
        cache[path] = color
        return color
    }
}

// MARK: Player presentation

extension View {
    /// Opens the player over this screen with a fade and slight zoom instead
    /// of the usual slide-up.
    func playerCover(_ visit: Binding<SiteVisit?>) -> some View {
        modifier(PlayerCover(visit: visit))
    }
}

/// Presents the player without the system animation. PlayerScreen fades
/// itself in and out over a clear background.
private struct PlayerCover: ViewModifier {
    @Binding var visit: SiteVisit?
    @State private var shown: SiteVisit?

    func body(content: Content) -> some View {
        content
            .onChange(of: visit?.id) {
                withoutAnimation { shown = visit }
            }
            .fullScreenCover(item: $shown) { visit in
                PlayerScreen(visit: visit) {
                    withoutAnimation {
                        shown = nil
                        self.visit = nil
                    }
                }
                .presentationBackground(.clear)
            }
    }
}

func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}
