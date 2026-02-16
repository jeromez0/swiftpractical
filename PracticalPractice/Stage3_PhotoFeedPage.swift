import SwiftUI

// MARK: - Model

// Hashable: required by NavigationLink(value:) for type-safe navigation (if needed)
struct Photo: Codable, Identifiable, Hashable {
    let albumId: Int
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Service

struct PhotoService {
    func fetchPhotos(page: Int, limit: Int = 10) async throws -> [Photo] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/photos?albumId=1&_page=\(page)&_limit=\(limit)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Photo].self, from: data)
    }
}

// MARK: - Image Loader (NEW in Stage 3 — replaces AsyncImage)

// Why replace AsyncImage? AsyncImage has NO caching — it re-fetches every time a view reappears.
// In a scrollable feed, scrolling back up triggers new network requests for already-seen images.

// class (not struct): owns mutable state (the cache). Singleton so cache is shared app-wide.
final class ImageLoader {
    static let shared = ImageLoader()
    // NSCache: thread-safe (no lock needed), auto-evicts under memory pressure
    // Keys must be NSObject — NSURL bridges from URL for free
    private let cache = NSCache<NSURL, UIImage>()

    // Single entry point — caller doesn't know or care about caching strategy
    func loadImage(from url: URL) async throws -> UIImage {
        // Check cache first — instant return, no network
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        // Cache miss — fetch from network
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Store in cache for future requests
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: - ViewModel

enum PaginationState: Equatable {
    case idle
    case loading
    case error(String)
    case done
}

@MainActor
@Observable
final class PhotoFeedViewModel {
    private(set) var photos: [Photo] = []
    private(set) var state: ViewState<[Photo]> = .idle
    private(set) var paginationState: PaginationState = .idle

    private var currentPage = 1
    private let service: PhotoService

    // Service injected via init — default param means views create with zero config,
    // but tests can inject a mock. Mention this; don't build tests.
    init(service: PhotoService = PhotoService()) {
        self.service = service
    }

    func fetchInitialPhotos() async {
        state = .loading
        currentPage = 1
        photos = []
        do {
            let photos = try await service.fetchPhotos(page: currentPage)
            self.photos = photos
            state = .loaded(photos)
            paginationState = photos.isEmpty ? .done : .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func fetchNextPage() async {
        guard paginationState == .idle else { return }

        paginationState = .loading
        let nextPage = currentPage + 1
        do {
            let newPhotos = try await service.fetchPhotos(page: nextPage)
            if newPhotos.isEmpty {
                paginationState = .done
            } else {
                photos.append(contentsOf: newPhotos)
                state = .loaded(photos)
                currentPage = nextPage
                paginationState = .idle
            }
        } catch {
            paginationState = .error(error.localizedDescription)
        }
    }

    func shouldFetchMore(currentItem: Photo) -> Bool {
        guard let lastItem = photos.last else { return false }
        return currentItem.id == lastItem.id && paginationState == .idle
    }
}

// MARK: - Views

struct PhotoFeedView: View {
    @State private var viewModel = PhotoFeedViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading photos...")
                case .loaded:
                    photoList
                case .error(let message):
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.fetchInitialPhotos() }
                        }
                    }
                }
            }
            .navigationTitle("Photo Feed")
            .task {
                await viewModel.fetchInitialPhotos()
            }
        }
    }

    private var photoList: some View {
        List {
            ForEach(viewModel.photos) { photo in
                PhotoRowView(photo: photo)
                    .onAppear {
                        if viewModel.shouldFetchMore(currentItem: photo) {
                            Task { await viewModel.fetchNextPage() }
                        }
                    }
            }

            paginationFooter
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        switch viewModel.paginationState {
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        case .error(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.fetchNextPage() }
                }
            }
        case .done:
            HStack {
                Spacer()
                Text("End of feed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Row (CHANGED — uses CachedAsyncImage instead of AsyncImage)

struct PhotoRowView: View {
    let photo: Photo

    var body: some View {
        HStack(spacing: 12) {
            // CachedAsyncImage: our custom replacement for AsyncImage — caches via ImageLoader
            CachedAsyncImage(url: URL(string: photo.thumbnailUrl))
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(photo.title)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - CachedAsyncImage (NEW in Stage 3)

struct CachedAsyncImage: View {
    let url: URL?

    // @State: local view state — preserved across re-renders, reset when view identity changes
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                // Image(uiImage:) — bridges UIKit's UIImage to SwiftUI's Image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                // Placeholder while image loads
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            } else {
                // Error state — image failed to load
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        // .task(id: url) — THE KEY LINE for cell reuse:
        // When `url` changes (cell reused for different photo), SwiftUI:
        //   1. Cancels the old task (in-flight URLSession request throws CancellationError)
        //   2. Starts a new task with the new url
        // This prevents stale images from appearing in reused cells — no manual tracking needed
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else {
            isLoading = false
            return
        }

        isLoading = true
        image = nil

        do {
            // ImageLoader handles cache check + network fetch + cache store
            // The view doesn't know about caching strategy — just asks for an image
            image = try await ImageLoader.shared.loadImage(from: url)
        } catch {
            // CancellationError (cell reuse) or network failure — placeholder stays visible
        }
        isLoading = false
    }
}
