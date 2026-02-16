import SwiftUI

// MARK: - Model (unchanged from Stage 1)

struct Stage2Photo: Codable, Identifiable {
    let albumId: Int
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Service (CHANGED — added page + limit params for pagination)

struct Stage2PhotoService {
    // page + limit enable server-side pagination via query params
    // Default limit = 10 so callers don't have to specify it every time
    func fetchPhotos(page: Int, limit: Int = 10) async throws -> [Stage2Photo] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/photos?albumId=1&_page=\(page)&_limit=\(limit)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Returns empty array [] when past the last page — that's how we detect end-of-list
        return try JSONDecoder().decode([Stage2Photo].self, from: data)
    }
}

// MARK: - State

// Same ViewState as Stage 1 — handles initial load lifecycle
enum Stage2ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

// NEW in Stage 2 — tracks pagination separately from initial load
// Why separate? A failed page 3 shouldn't blow away pages 1-2 already on screen
// Equatable: allows guard checks like `paginationState == .idle`
enum Stage2PaginationState: Equatable {
    case idle       // ready to fetch next page
    case loading    // fetching next page right now
    case error(String) // next page failed (existing data preserved)
    case done       // no more pages — API returned empty array
}

// MARK: - ViewModel (CHANGED — added pagination logic)

@MainActor
@Observable
final class Stage2ViewModel {
    // Accumulated photos across all loaded pages
    private(set) var photos: [Stage2Photo] = []
    // Overall screen state (initial load)
    private(set) var state: Stage2ViewState<[Stage2Photo]> = .idle
    // Pagination-specific state (subsequent page loads)
    private(set) var paginationState: Stage2PaginationState = .idle

    private var currentPage = 1
    private let service = Stage2PhotoService()

    // Called on first load — resets everything
    func fetchInitialPhotos() async {
        state = .loading
        currentPage = 1
        photos = []
        do {
            let photos = try await service.fetchPhotos(page: currentPage)
            self.photos = photos
            state = .loaded(photos)
            // If first page is empty, there's nothing to paginate
            paginationState = photos.isEmpty ? .done : .idle
        } catch {
            // Initial load failure → full-screen error (we have nothing to show)
            state = .error(error.localizedDescription)
        }
    }

    // Called when user scrolls near bottom
    func fetchNextPage() async {
        // Guard prevents duplicate fetches — if already loading, done, or in error, bail out
        guard paginationState == .idle else { return }

        paginationState = .loading
        let nextPage = currentPage + 1
        do {
            let newPhotos = try await service.fetchPhotos(page: nextPage)
            if newPhotos.isEmpty {
                // Empty response = no more data on the server
                paginationState = .done
            } else {
                // Append (not replace) — preserves existing photos
                photos.append(contentsOf: newPhotos)
                state = .loaded(photos)
                currentPage = nextPage
                paginationState = .idle
            }
        } catch {
            // Pagination error only affects the footer — existing photos stay visible
            paginationState = .error(error.localizedDescription)
        }
    }

    // Called from .onAppear on each row — triggers next page when last item is visible
    func shouldFetchMore(currentItem: Stage2Photo) -> Bool {
        guard let lastItem = photos.last else { return false }
        // Only fetch if this is the last item AND we're in idle state
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
            // ForEach instead of List(photos) so we can add the footer outside the loop
            ForEach(viewModel.photos) { photo in
                Stage2RowView(photo: photo)
                    // .onAppear: fires when this row becomes visible on screen
                    // Triggers next page fetch when the last item scrolls into view
                    .onAppear {
                        if viewModel.shouldFetchMore(currentItem: photo) {
                            Task { await viewModel.fetchNextPage() }
                        }
                    }
            }

            // Footer sits below the list items — shows pagination state
            paginationFooter
        }
    }

    // @ViewBuilder: lets you return different view types from a switch without wrapping in AnyView
    @ViewBuilder
    private var paginationFooter: some View {
        switch viewModel.paginationState {
        case .loading:
            // Centered spinner while next page loads
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        case .error(let message):
            // Inline error + retry — does NOT replace existing content
            VStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.fetchNextPage() }
                }
            }
        case .done:
            // End of feed indicator
            HStack {
                Spacer()
                Text("End of feed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        case .idle:
            // Nothing to show — waiting for scroll trigger
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
