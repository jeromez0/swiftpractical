import SwiftUI

// MARK: - Model

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let phone: String
}

// MARK: - Service

struct UserService {
    func fetchUsers() async throws -> [User] {
        let url = URL(string: "https://jsonplaceholder.typicode.com/users")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([User].self, from: data)
    }
}

// MARK: - ViewModel

enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

@MainActor
@Observable
final class UserListViewModel {
    private(set) var state: ViewState<[User]> = .idle

    private let service: UserService

    init(service: UserService = UserService()) {
        self.service = service
    }

    func fetchUsers() async {
        state = .loading
        do {
            try await Task.sleep(for: .seconds(3)) // Simulate slow network
            let users = try await service.fetchUsers()
            state = .loaded(users)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

// MARK: - Views

struct UserListView: View {
    @State private var viewModel = UserListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading users...")
                case .loaded(let users):
                    List(users) { user in
                        NavigationLink(value: user) {
                            UserRowView(user: user)
                        }
                    }
                case .error(let message):
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.fetchUsers() }
                        }
                    }
                }
            }
            .navigationTitle("Users")
            .navigationDestination(for: User.self) { user in
                UserDetailView(user: user)
            }
            .task {
                await viewModel.fetchUsers()
            }
        }
    }
}

struct UserRowView: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.name)
                .font(.headline)
            Text(user.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct UserDetailView: View {
    let user: User

    var body: some View {
        List {
            Section {
                DetailRow(label: "Name", value: user.name)
                DetailRow(label: "Username", value: user.username)
                DetailRow(label: "Email", value: user.email)
                DetailRow(label: "Phone", value: user.phone)
            }
        }
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}
