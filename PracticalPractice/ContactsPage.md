# Prompt 1 Cheatsheet — User Directory

Quick reference for every piece of the solution. Skim this before the round.

---

## Architecture at a Glance

```
Model (User)  -->  Service (UserService)  -->  ViewModel (UserListViewModel)  -->  Views
```

Single file, four logical layers. Data flows down, events flow up.

---

## 1. Model

```swift
struct User: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let phone: String
}
```

**Why these protocols?**

| Protocol | Reason |
|---|---|
| `Codable` | Auto-synthesizes JSON decoding. The API returns extra fields (`address`, `company`, etc.) — they're silently ignored because we don't declare them. |
| `Identifiable` | Required by SwiftUI `List` and `ForEach` to diff rows efficiently. Uses `id` property. |
| `Hashable` | Required by `NavigationLink(value:)` and `.navigationDestination(for:)` for type-safe navigation. |

---

## 2. Service

```swift
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
```

**Key points:**

- **`async throws`** — lets callers use `try await`, errors propagate naturally.
- **`URLSession.shared.data(from:)`** — the async/await variant (iOS 15+). No delegates, no completion handlers.
- **Status code check** — `data(from:)` doesn't throw on 4xx/5xx. The `guard` catches bad responses before we try to decode garbage.
- **`[User].self`** — tells the decoder to expect a JSON array and decode each element as a `User`.
- **`struct` not `class`** — stateless, no reference semantics needed. Lightweight.

**If asked "why not Combine / completion handlers?"** — async/await is the modern standard (Swift 5.5+), more readable, and easier to reason about cancellation. You'd use Combine if you needed reactive streams (e.g. real-time updates), and completion handlers only for legacy API compatibility.

---

## 3. ViewState Enum

```swift
enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}
```

**Why an enum instead of bools?**

- **No impossible states.** With `isLoading: Bool` + `errorMessage: String?` + `users: [User]`, you can have `isLoading = true` AND `errorMessage != nil` at the same time. The enum makes states mutually exclusive.
- **Exhaustive switch.** The compiler forces the view to handle every case. Add a new state? The app won't compile until you handle it.
- **Generic `<T>`** — reusable for any screen. `ViewState<[User]>`, `ViewState<Photo>`, etc.

---

## 4. ViewModel

```swift
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
            let users = try await service.fetchUsers()
            state = .loaded(users)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
```

**Annotations explained:**

| Annotation | What it does |
|---|---|
| `@MainActor` | Guarantees all property access and mutations happen on the main thread. Required in Swift 6 strict concurrency — without it, mutating `state` from an async context is a compiler error. |
| `@Observable` | iOS 17+ Observation framework. SwiftUI automatically tracks which properties each view reads and only re-renders when those change. Replaces the older `ObservableObject` + `@Published` pattern. |
| `final class` | `@Observable` requires a class (reference type). `final` prevents subclassing — cleaner, and enables compiler optimizations. |
| `private(set)` | Views can read `state` but only the ViewModel can mutate it. Enforces unidirectional data flow. |

**Service injection:** `init(service: UserService = UserService())` — the default parameter means the view can create a ViewModel with zero config, but tests can inject a mock. Mention this; don't build tests.

---

## 5. Views

### UserListView (main screen)

```swift
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
                    ContentUnavailableView { ... } actions: {
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
```

**Key pieces:**

| Piece | Why |
|---|---|
| `@State private var viewModel` | Owns the ViewModel's lifecycle. SwiftUI creates it once and preserves it across re-renders. With `@Observable`, `@State` is all you need (no `@StateObject`). |
| `NavigationStack` | Modern replacement for `NavigationView` (iOS 16+). Supports programmatic navigation via path. |
| `Group { switch ... }` | `Group` is a transparent container — lets you switch between completely different view hierarchies without affecting layout. |
| `.task { }` | Fires an async task when the view appears. Automatically cancelled if the view disappears. Replaces `onAppear` + manual `Task` creation. |
| `.navigationDestination(for: User.self)` | Type-safe navigation. When a `NavigationLink(value: user)` is tapped, SwiftUI matches the value's type to this destination closure. Requires `User: Hashable`. |
| `ContentUnavailableView` | iOS 17+ built-in view for empty/error states. Shows icon + description + action button. Saves you from building a custom error view. |
| `Task { await ... }` in Retry button | Creates a new async task from a synchronous context (button action). The task inherits `@MainActor` from the ViewModel. |

### UserDetailView (detail screen)

```swift
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
```

- **Dumb view.** No ViewModel, no networking. Just receives a `User` and renders it.
- **`.inline` title display** — keeps the detail screen compact since the name is already shown in the content.

---

## Common Interview Follow-ups

**"How would you test this?"**
- Inject a mock `UserService` that returns hardcoded data or throws errors. The init already supports this.
- Test the ViewModel directly: call `fetchUsers()`, assert `state == .loaded(expectedUsers)`.

**"What about cancellation?"**
- `.task` automatically cancels when the view disappears. The `URLSession` request respects cooperative cancellation via Swift's `Task` system.

**"What if you needed to support iOS 15?"**
- Replace `@Observable` with `ObservableObject` + `@Published`.
- Replace `@State var viewModel` with `@StateObject var viewModel`.
- Replace `NavigationStack` with `NavigationView` + `NavigationLink(destination:)`.
- Replace `ContentUnavailableView` with a custom VStack.

**"Why not use a `Result` type instead of the enum?"**
- `Result<[User], Error>` only has two cases (success/failure). We need four states: idle, loading, loaded, error. `Result` can't express "loading."

**"Should the ViewModel be a struct?"**
- No. `@Observable` requires a reference type (class) so SwiftUI can track identity across re-renders. A struct would get copied and lose observation.
