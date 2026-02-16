# Prompt 2 Cheatsheet — Paginated Photo Feed

Quick reference for the photo feed solution. Covers pagination, image loading + caching, and cell reuse cancellation.

---

## Architecture at a Glance

```
PhotoService (JSON metadata)  -->  PhotoFeedViewModel  -->  PhotoFeedView
ImageLoader  (image bytes + cache)                     -->  CachedAsyncImage
```

Two services, each with one job. The ViewModel doesn't touch images. The image view doesn't know about pagination.

---

## 1. Model

```swift
struct Photo: Codable, Identifiable, Hashable {
    let albumId: Int
    let id: Int
    let title: String
    let url: String
    let thumbnailUrl: String
}
```

Same pattern as Prompt 1. `url` is the full-size image, `thumbnailUrl` is the small one for list rows.

---

## 2. PhotoService

```swift
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
```

**Key points:**

- `page` and `limit` are query params — the API handles server-side pagination.
- Default `limit = 10` means callers don't need to specify it every time.
- Returns an empty array `[]` when you go past the last page — that's how we detect end-of-list.

---

## 3. ImageLoader

```swift
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
```

**Why this design:**

| Decision | Reason |
|---|---|
| Single `loadImage(from:)` method | One entry point — caller doesn't know or care about the cache. Just "give me an image for this URL." |
| `NSCache` (not `Dictionary`) | Thread-safe out of the box. Auto-evicts under memory pressure — no manual memory management needed. |
| `NSURL` as key | `NSCache` requires `NSObject` keys. `NSURL` bridges from `URL` for free. |
| Singleton | Images are shared across the app. A single cache instance prevents duplicate fetches for the same URL from different views. |
| `async throws` | Propagates cancellation (from cell reuse) and network errors naturally. |

**If asked "why not use `URLCache`?"** — `URLCache` caches raw HTTP response data, not decoded `UIImage` objects. Every cache hit would still require `UIImage(data:)` decoding. `NSCache` stores the ready-to-render `UIImage` directly.

**If asked "why not `AsyncImage`?"** — `AsyncImage` has no built-in caching (it re-fetches every time a view reappears) and gives you no control over cancellation or error handling. Fine for profile pictures; not for a feed with 50+ images.

---

## 4. State Management

Two enums working together:

```swift
// Reused from Prompt 1 — overall screen state
enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

// New — pagination-specific state
enum PaginationState: Equatable {
    case idle       // ready to fetch next page
    case loading    // fetching next page
    case error(String)  // next page failed (existing data preserved)
    case done       // no more pages
}
```

**Why two enums instead of one?**

A failed page 3 fetch should NOT blow away pages 1-2 that are already on screen. By separating initial load state (`ViewState`) from pagination state (`PaginationState`), the list stays visible even when pagination fails. The error only shows as an inline retry at the bottom.

---

## 5. ViewModel

```swift
@MainActor
@Observable
final class PhotoFeedViewModel {
    private(set) var photos: [Photo] = []
    private(set) var state: ViewState<[Photo]> = .idle
    private(set) var paginationState: PaginationState = .idle

    private var currentPage = 1
    private let service: PhotoService
    ...
}
```

### fetchInitialPhotos()

- Resets everything (`currentPage = 1`, `photos = []`)
- Sets `state = .loading` (full-screen spinner)
- On success: `state = .loaded(photos)`
- On failure: `state = .error(...)` (full-screen error with Retry)

### fetchNextPage()

- **Guard:** `guard paginationState == .idle else { return }` — prevents duplicate fetches. If we're already loading, at the end, or in error, do nothing.
- Fetches `currentPage + 1`
- **Empty response** = `.done` (no more pages)
- **Success** = appends to `photos`, increments `currentPage`, resets to `.idle`
- **Failure** = `paginationState = .error(...)` — existing photos are untouched

### shouldFetchMore(currentItem:)

```swift
func shouldFetchMore(currentItem: Photo) -> Bool {
    guard let lastItem = photos.last else { return false }
    return currentItem.id == lastItem.id && paginationState == .idle
}
```

Called from `.onAppear` on each row. When the last item appears on screen, triggers the next page fetch. The `paginationState == .idle` check prevents re-triggering during a load.

**If asked about prefetching:** You could trigger at `photos.count - 3` instead of the very last item, giving the network a head start. Mention it, don't build it.

---

## 6. Views

### PhotoFeedView (main screen)

Same pattern as Prompt 1:
- `switch viewModel.state` for initial load / loaded / error
- `.task { await viewModel.fetchInitialPhotos() }` to kick off

New pieces for pagination:
- `.onAppear` on each row calls `shouldFetchMore()`
- `paginationFooter` — a `@ViewBuilder` that switches on `paginationState`:
  - `.loading` → centered `ProgressView`
  - `.error` → message + Retry button (inline, not full screen)
  - `.done` → "End of feed" text
  - `.idle` → `EmptyView()`

### PhotoRowView

Dumb row. `HStack` with a `CachedAsyncImage` (60x60) and the title. Nothing else.

### CachedAsyncImage

```swift
struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image { /* show image */ }
            else if isLoading { /* gray rect + spinner */ }
            else { /* gray rect + photo icon (error) */ }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { isLoading = false; return }
        isLoading = true
        image = nil
        do {
            image = try await ImageLoader.shared.loadImage(from: url)
        } catch {
            // Cancelled or failed — placeholder stays
        }
        isLoading = false
    }
}
```

**The key line is `.task(id: url)`:**

| Behavior | What happens |
|---|---|
| View appears | Task starts, loads image |
| View disappears | Task is cancelled automatically |
| `url` changes (cell reuse) | Old task cancelled, new task starts |

This is how SwiftUI handles cell reuse cancellation for free. No manual `Task` tracking, no cancellation tokens. The `try await URLSession.shared.data(from:)` inside `ImageLoader` throws `CancellationError` when the task is cancelled, which we catch silently.

---

## Common Interview Follow-ups

**"How would you add disk caching?"**
- Wrap `ImageLoader` to check `FileManager` (or a `URLCache` with a disk policy) before hitting the network. The interface stays the same — `loadImage(from:)` — callers don't change.

**"What about prefetching images?"**
- Use `UICollectionViewDataSourcePrefetching` (UIKit) or trigger loads for upcoming URLs in the ViewModel's `fetchNextPage()` after appending new photos. You'd call `ImageLoader.shared.loadImage(from:)` for URLs a few rows ahead, warming the cache.

**"How would you handle really large images?"**
- Downsample at decode time using `ImageIO` (`CGImageSourceCreateThumbnailAtIndex`) instead of loading the full image into memory. Mention this; don't build it.

**"Why `NSCache` instead of a dictionary?"**
- `NSCache` is thread-safe (dictionary isn't without a lock). It auto-evicts under memory pressure. You get memory management for free.

**"What if two cells request the same URL simultaneously?"**
- Both calls hit `ImageLoader`. The first one won't find it in cache and starts a network request. The second one also won't find it in cache and starts its own request. For an interview this is fine. To deduplicate, you'd track in-flight requests with a `[URL: Task<UIImage, Error>]` dictionary and have the second caller `await` the existing task.

**"How does pagination know when to stop?"**
- The API returns an empty array when you request a page beyond the data. `fetchNextPage()` checks `if newPhotos.isEmpty` and sets `paginationState = .done`.

**"What if the user scrolls really fast?"**
- The `guard paginationState == .idle` prevents stacking multiple page fetches. Only one page fetch runs at a time. For images, `.task(id: url)` cancels stale loads on reuse, so fast scrolling just means lots of quick cancellations — no wasted work.
