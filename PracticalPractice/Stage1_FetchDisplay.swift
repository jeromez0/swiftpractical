import SwiftUI

// MARK: - Model

struct Stage1Photo: Codable, Identifiable {
    let albumId: Int
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}

// MARK: - Service

struct Stage1PhotoService {
    func fetchPhotos() async throws -> [Stage1Photo] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/photos?albumId=1")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Stage1Photo].self, from: data)
    }
}

// MARK: - State

enum Stage1ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

// MARK: - ViewModel

@MainActor
@Observable
final class Stage1ViewModel {
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
    @State private var viewModel = Stage1ViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading photos...")
                case .loaded(let photos):
                    List(photos) { photo in
                        Stage1RowView(photo: photo)
                    }
                case .error(let message):
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.fetchPhotos() }
                        }
                    }
                }
            }
            .navigationTitle("Stage 1: Fetch + Display")
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
