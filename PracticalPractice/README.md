# iOS Practical Round Practice

Three timed prompts simulating Snapchat / Robinhood-style practical rounds.
Each prompt is self-contained. Work in a fresh Xcode project (or Swift Playground) for each one.
Use UIKit or SwiftUI — whichever you expect in the interview.

---

## Prompt 1 — User Directory (45 min)

**Difficulty:** ⭐⭐ Medium

You are given a JSON endpoint that returns a list of users:

```
GET https://jsonplaceholder.typicode.com/users
```

Each user object has (among other fields):
```json
{
  "id": 1,
  "name": "Leanne Graham",
  "username": "Bret",
  "email": "Sincere@april.biz",
  "phone": "1-770-736-8031 x56442"
}
```

**Requirements:**

1. Fetch the list of users from the endpoint above.
2. Display the users in a scrollable list. Each row should show the user's **name** and **email**.
3. Tapping a row should navigate to (or present) a detail view showing **all four fields** (name, username, email, phone).
4. While the network request is in flight, show a loading indicator.
5. If the request fails, show an error state with a **Retry** button that re-triggers the fetch.

**What the interviewer is evaluating:**
- Clean networking layer (`URLSession` + `Codable`)
- Correct use of concurrency (`async/await`, main-thread UI updates)
- Basic navigation / presentation
- Error handling that doesn't crash or leave the UI in a broken state

---

## Prompt 2 — Paginated Photo Feed with Thumbnails (60 min)

**Difficulty:** ⭐⭐⭐ Medium-Hard

You are building a paginated photo feed. The endpoint supports pagination via `_page` and `_limit` query parameters:

```
GET https://jsonplaceholder.typicode.com/photos?albumId=1&_page=1&_limit=10
```

This returns 10 photos per page. There are 50 total photos for `albumId=1` (5 pages).

Each photo object:
```json
{
  "albumId": 1,
  "id": 1,
  "title": "accusamus beatae ad facilis cum similique qui sunt",
  "url": "https://via.placeholder.com/600/92c952",
  "thumbnailUrl": "https://via.placeholder.com/150/92c952"
}
```

**Requirements:**

1. Fetch the **first page** of photos on launch (page 1, limit 10).
2. Display them in a scrollable list (or grid). Each cell shows the **thumbnail image** and the **title**.
3. Images must be loaded **asynchronously** — cells should not block or stutter while images load.
4. Handle **cell reuse** correctly: if a cell is reused before its image finishes loading, the old image request should be cancelled and the cell should not display a stale image.
5. Implement a simple **in-memory image cache** so that scrolling back to an already-loaded image does not trigger another network request.
6. Show a placeholder (e.g. a gray box or `UIActivityIndicatorView`) while each image is loading.
7. **Infinite scroll / pagination:** When the user scrolls near the bottom of the list, automatically fetch the next page and append the results. Do not re-fetch pages already loaded.
8. Show a **loading indicator at the bottom** of the list while the next page is being fetched.
9. When there are no more pages (empty response), stop fetching and optionally show an "end of list" indicator.
10. If the feed request fails, show an error state with a Retry button. If a *pagination* request fails, show an inline retry at the bottom of the list (don't replace the already-loaded content).

**What the interviewer is evaluating:**
- Async image loading without UI jank
- Correct cell reuse handling (cancellation of in-flight requests)
- Caching strategy (even a simple `NSCache` or `[URL: UIImage]` dictionary is fine)
- Concurrency correctness — no data races, no main-thread network calls
- Pagination logic: page tracking, preventing duplicate fetches, appending vs. replacing data
- Handling end-of-list and pagination errors separately from initial load errors

---

## Prompt 3 — Portfolio Dashboard (60 min)

**Difficulty:** ⭐⭐⭐⭐ Hard

You are building a simplified portfolio screen (think Robinhood). The data comes from **two separate endpoints** that must both succeed for the screen to render:

**Holdings:**
```
GET https://jsonplaceholder.typicode.com/posts?userId=1
```
Treat each post as a "holding." Use `id` as the holding ID and `title` as the holding name.

**Holding Details (price info):**
```
GET https://jsonplaceholder.typicode.com/comments?postId={id}
```
For each holding, fetch its comments. Treat the **number of comments** as the current price (e.g. 5 comments = $5.00).

**Requirements:**

1. Fetch the user's holdings from the first endpoint.
2. For each holding, **concurrently** fetch its detail (comments) from the second endpoint. Do not fetch them one at a time sequentially.
3. Display a list where each row shows the holding **name** and its **price**.
4. At the top of the screen, display the **total portfolio value** (sum of all prices).
5. Handle **partial failures** gracefully: if some detail requests fail, still show the holdings that succeeded, and display an indicator (e.g. "Price unavailable") for the ones that failed.
6. Show a loading state while data is being fetched.
7. Add a **pull-to-refresh** that re-fetches everything.

**What the interviewer is evaluating:**
- Concurrent network requests (`async let`, `TaskGroup`, or similar)
- Aggregating results from multiple endpoints
- Partial failure handling (not all-or-nothing)
- UI state management (loading → success/partial error → full error)
- Pull-to-refresh integration

---

## Tips

- **Talk out loud.** Narrate your decisions, even when practicing alone. Record yourself if possible.
- **Start with the data layer.** Define your models and networking first, then build the UI on top.
- **Don't gold-plate.** Get a working end-to-end flow first, then improve. Interviewers want to see something functional at the 30-minute mark.
- **Know your concurrency primitives.** Be ready to explain *why* you chose `async/await` vs. GCD vs. Combine. For modern Swift, `async/await` is the default unless the interviewer says otherwise.
- **Handle the unhappy path.** Error states and edge cases are where senior candidates separate themselves.
