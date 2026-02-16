import SwiftUI

// MARK: - Model (unchanged from Stage 1)

struct Stage2Photo: Codable, Identifiable {
    let albumId: Int
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Service (CHANGED — added page + limit params)

struct Stage2PhotoService {
    func fetchPhotos(page: Int, limit: Int = 10) async throws -> [Stage2Photo] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/photos?albumId=1&_page=\(page)&_limit=\(limit)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Stage2Photo].self, from: data)
    }
}

// MARK: - State

enum Stage2ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

enum Stage2PaginationState: Equatable {
    case idle
    case loading
    case error(String)
    case done
}

// MARK: - ViewModel (CHANGED — added pagination logic)

@MainActor
@Observable
final class Stage2ViewModel {
    private(set) var photos: [Stage2Photo] = []
    private(set) var state: Stage2ViewState<[Stage2Photo]> = .idle
    private(set) var paginationState: Stage2PaginationState = .idle

    private var currentPage = 1
    private let service = Stage2PhotoService()

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

    func shouldFetchMore(currentItem: Stage2Photo) -> Bool {
        guard let lastItem = photos.last else { return false }
        return currentItem.id == lastItem.id && paginationState == .idle
    }
}

// MARK: - Views (CHANGED — added pagination trigger + footer)

struct Stage2FeedView: View {
    @State private var viewModel = Stage2ViewModel()

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
            .navigationTitle("Stage 2: Pagination")
            .task {
                await viewModel.fetchInitialPhotos()
            }
        }
    }

    private var photoList: some View {
        List {
            ForEach(viewModel.photos) { photo in
                Stage2RowView(photo: photo)
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

// MARK: - Row (unchanged from Stage 1 — still uses AsyncImage)

struct Stage2RowView: View {
    let photo: Stage2Photo

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: photo.thumbnailUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(photo.title)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
