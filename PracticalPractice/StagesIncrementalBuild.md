# Incremental Build Cheatsheet — Photo Feed

How to build the photo feed in stages during an interview. Each stage is a working app. You stop wherever time runs out.

Stage 3 (pagination) is the existing `PhotoFeedPage.swift` — no separate file needed.

---

## The Strategy

1. Verbally outline your approach (2-3 min)
2. Build Stage 1 — fetch + display, text only (~15 min)
3. Build Stage 2 — add images + cache (~10 min)
4. Build Stage 3 — add pagination (~10 min)
5. Test + polish (~5-10 min)

Each stage adds code. You rarely change existing code — you add new types and extend existing views.

---

## Stage 1 — Fetch + Display (~15 min)

**Goal:** Get data on screen. Working app as fast as possible.

**Files/types you write:**

| Type | Lines | What it does |
|---|---|---|
| `Photo` (model) | 6 | Codable struct with id, title, thumbnailUrl |
| `PhotoService` | 10 | Single `fetchPhotos() async throws` — fetches all photos at once, no pagination |
| `PhotoFeedViewModel` | 12 | `ViewState<[Photo]>` + `fetchPhotos()` — identical to Contacts page |
| `PhotoFeedView` | 25 | `switch` on state, `List` of rows, loading/error states |
| `PhotoRowView` | 5 | Just `Text(photo.title)` — no image yet |

**Total: ~58 lines. This is a working app.**

**What to say:**
- "I'll start with fetch and display, then layer in images and pagination."
- "I'm using an enum for state so the view has a clean switch — no impossible states."
- "The service is a separate struct. In production I'd protocol-ify it for testability."

**What to NOT do yet:**
- No images
- No caching
- No pagination
- Don't optimize — just get it working

---

## Stage 2 — Add Images + Cache (~10 min)

**Goal:** Show thumbnails with async loading, caching, and cell reuse handling.

**New types you add:**

| Type | Lines | What it does |
|---|---|---|
| `ImageLoader` | 15 | Singleton with `NSCache`. One method: `loadImage(from:) async throws -> UIImage`. Checks cache first, fetches if miss, stores on success. |
| `CachedAsyncImage` | 30 | SwiftUI view. Uses `.task(id: url)` to call `ImageLoader`. Shows placeholder while loading, error state on failure. |

**Existing code you change:**

| Type | Change |
|---|---|
| `PhotoRowView` | Wrap in `HStack`. Add `CachedAsyncImage` before the title text. |

**Nothing else changes.** Service, ViewModel, main view — all untouched.

**What to say:**
- "I'm adding an ImageLoader that owns the cache. The view doesn't know about caching strategy — it just asks for an image."
- "NSCache is thread-safe out of the box and auto-evicts under memory pressure."
- "`.task(id: url)` is the key — when SwiftUI reuses this cell for a different photo, it cancels the old task and starts a new one. No stale images, no manual cancellation tracking."
- "If asked about AsyncImage — it has no caching. Every reappear triggers a re-fetch. Not suitable for a feed."

**ARC / memory points to narrate:**
- "ImageLoader is a class because it owns mutable state (the cache). It's a singleton so the cache is shared app-wide."
- "CachedAsyncImage is a struct (value type) — no retain cycle risk. The `.task` closure doesn't capture self strongly because it's a value type."
- "NSCache stores UIImage objects which can be large. NSCache's auto-eviction handles memory warnings for us."

---

## Stage 3 — Add Pagination (~10 min)

**Goal:** Infinite scroll with duplicate fetch prevention and separate error handling.

This is the jump from Stage 2 to the full `PhotoFeedPage.swift`.

**New types you add:**

| Type | Lines | What it does |
|---|---|---|
| `PaginationState` enum | 5 | idle / loading / error / done — tracks pagination separately from initial load |

**Existing code you change:**

| Type | Change |
|---|---|
| `PhotoService` | Add `page: Int` and `limit: Int = 10` params. Update URL to include `_page` and `_limit`. |
| `PhotoFeedViewModel` | Add `photos: [Photo]` array, `currentPage`, `paginationState`. Split `fetchPhotos()` into `fetchInitialPhotos()` and `fetchNextPage()`. Add `shouldFetchMore(currentItem:)`. |
| `PhotoFeedView` | Add `.onAppear` on each row calling `shouldFetchMore`. Add `paginationFooter` (switch on `paginationState`). |

**No changes to:** Photo model, ImageLoader, CachedAsyncImage, PhotoRowView.

**What to say:**
- "I'm adding a separate PaginationState enum because a failed page 3 shouldn't blow away pages 1-2."
- "The guard on `paginationState == .idle` prevents duplicate fetches — if we're already loading or at the end, we bail out."
- "When the API returns an empty array, I set `.done` — that's how we know there are no more pages."
- "I could add prefetching by triggering at `count - 3` instead of the last item, but I'll keep it simple."

---

## Side-by-Side Diff: What Changes Between Stages

### PhotoRowView

```
Stage 1:                          Stage 2:
─────────                         ─────────
Text(photo.title)                 HStack(spacing: 12) {
    .font(.subheadline)               CachedAsyncImage(url: ...)
    .lineLimit(2)                         .frame(width: 60, height: 60)
                                          .clipShape(RoundedRectangle(...))
                                      Text(photo.title)
                                          .font(.subheadline)
                                          .lineLimit(2)
                                  }
```

### PhotoService

```
Stage 1/2:                        Stage 3:
──────────                        ────────
func fetchPhotos()                func fetchPhotos(page: Int, limit: Int = 10)
    async throws -> [Photo]           async throws -> [Photo]

URL: photos?albumId=1             URL: photos?albumId=1&_page=\(page)&_limit=\(limit)
```

### ViewModel

```
Stage 1/2:                        Stage 3:
──────────                        ────────
state: ViewState<[Photo]>         state: ViewState<[Photo]>
                                  photos: [Photo] = []
                                  paginationState: PaginationState = .idle
                                  currentPage = 1

fetchPhotos()                     fetchInitialPhotos()
                                  fetchNextPage()
                                  shouldFetchMore(currentItem:)
```

---

## Quick Reference: Key APIs

| API | What / Why |
|---|---|
| `URLSession.shared.data(from:)` | Async/await variant. Returns `(Data, URLResponse)`. |
| `JSONDecoder().decode(_:from:)` | Pass `[Photo].self` to decode a JSON array. Extra keys ignored automatically. |
| `@Observable` | iOS 17+ observation. SwiftUI tracks reads per-view, re-renders only on change. |
| `@MainActor` | All property mutations on main thread. Required for Swift 6 strict concurrency. |
| `ViewState<T>` enum | idle/loading/loaded/error. Mutually exclusive states. |
| `.task { }` | Fires async work on appear. Auto-cancels on disappear. |
| `.task(id: url)` | Restarts when `id` changes. Cancels old task first. Cell reuse cancellation for free. |
| `NSCache<NSURL, UIImage>` | Thread-safe, auto-evicts under memory pressure. Keys must be `NSObject`. |
| `ContentUnavailableView` | iOS 17+ built-in error/empty state view. |
| `.refreshable { }` | Native pull-to-refresh. Async closure — spinner hides when it returns. |
| `PaginationState` enum | Separate from ViewState so pagination errors don't nuke existing data. |
