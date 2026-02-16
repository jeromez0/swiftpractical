import SwiftUI

// MARK: - Model

// Codable: auto-synthesizes JSON decoding — extra API fields are silently ignored
// Identifiable: required by SwiftUI List/ForEach to diff rows efficiently (uses `id`)
struct Stage1Photo: Codable, Identifiable {
    let albumId: Int
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Service

// struct (not class): stateless, no reference counting overhead, no retain cycle risk
struct Stage1PhotoService {
    // async: suspends without blocking the calling thread
    // throws: errors propagate naturally to the caller via try/catch
    func fetchPhotos() async throws -> [Stage1Photo] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/photos?albumId=1")!
        // URLSession.shared.data(from:) — async/await variant (iOS 15+)
        // Returns (Data, URLResponse) — does NOT throw on 4xx/5xx
        let (data, response) = try await URLSession.shared.data(from: url)

        // Must manually check status code — URLSession only throws on network-level failures
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // [Stage1Photo].self — tells decoder to expect a JSON array, decode each element
        return try JSONDecoder().decode([Stage1Photo].self, from: data)
    }
}

// MARK: - State

// Generic enum — reusable for any screen's data type (ViewState<[Photo]>, ViewState<User>, etc.)
// Mutually exclusive cases — no impossible states like isLoading=true AND error!=nil
enum Stage1ViewState<T> {
    case idle       // haven't started yet
    case loading    // request in flight
    case loaded(T)  // success — carries the data as associated value
    case error(String) // failure — carries the error message
}

// MARK: - ViewModel

// @MainActor: guarantees all property access/mutations happen on the main thread
// Required in Swift 6 strict concurrency — without it, mutating state from async context is a compiler error
@MainActor
// @Observable: iOS 17+ observation framework — SwiftUI tracks which properties each view reads
// and only re-renders when those specific properties change. Replaces ObservableObject + @Published.
@Observable
// final: prevents subclassing, enables compiler optimizations. class required by @Observable (reference type).
final class Stage1ViewModel {
    // private(set): views can read, only ViewModel can write — enforces unidirectional data flow
    private(set) var state: Stage1ViewState<[Stage1Photo]> = .idle

    private let service = Stage1PhotoService()

    func fetchPhotos() async {
        state = .loading
        do {
            let photos = try await service.fetchPhotos()
            state = .loaded(photos)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

// MARK: - Views

struct Stage1FeedView: View {
    // @State: owns the ViewModel's lifecycle — SwiftUI creates it once, preserves across re-renders
    // With @Observable, @State is all you need (no @StateObject required)
    @State private var viewModel = Stage1ViewModel()

    var body: some View {
        // NavigationStack: modern replacement for NavigationView (iOS 16+), supports programmatic nav via path
        NavigationStack {
            // Group: transparent container — lets you switch between different view hierarchies without affecting layout
            Group {
                // Exhaustive switch on state — compiler forces you to handle every case
                switch viewModel.state {
                case .idle, .loading:
                    // ProgressView: system loading spinner with optional label
                    ProgressView("Loading photos...")
                case .loaded(let photos):
                    // List: scrollable container that handles cell reuse internally
                    // photos conforms to Identifiable so no need for `id:` param
                    List(photos) { photo in
                        Stage1RowView(photo: photo)
                    }
                case .error(let message):
                    // ContentUnavailableView: iOS 17+ built-in error/empty state — icon + description + action
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            // Task: creates async context from synchronous button action
                            Task { await viewModel.fetchPhotos() }
                        }
                    }
                }
            }
            .navigationTitle("Stage 1: Fetch + Display")
            // .task: fires async work when view appears, auto-cancels when view disappears
            // Replaces onAppear + manual Task creation
            .task {
                await viewModel.fetchPhotos()
            }
        }
    }
}

struct Stage1RowView: View {
    let photo: Stage1Photo

    var body: some View {
        HStack(spacing: 12) {
            // AsyncImage: built-in SwiftUI image loader (iOS 15+)
            // Simple but NO caching — re-fetches every time the view reappears
            // Fine for MVP, replace with custom ImageLoader for production feeds
            AsyncImage(url: URL(string: photo.thumbnailUrl)) { image in
                image
                    .resizable()
                    // .fill: scales to fill the frame, may crop edges
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                // Shown while image is loading
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(ProgressView())
            }
            // Fixed frame for consistent row heights
            .frame(width: 60, height: 60)
            // Clips overflowing image content to rounded rect shape
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(photo.title)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
