import SwiftUI

// MARK: - Model

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

// MARK: - Image Loader

final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()

    func loadImage(from url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

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

struct PhotoRowView: View {
    let photo: Photo

    var body: some View {
        HStack(spacing: 12) {
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

struct CachedAsyncImage: View {
    let url: URL?

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
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
            image = try await ImageLoader.shared.loadImage(from: url)
        } catch {
            // Cancelled (cell reuse) or network failure — show placeholder
        }
        isLoading = false
    }
}
