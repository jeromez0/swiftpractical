# Prompt 3 Cheatsheet — Portfolio Dashboard

Quick reference for the concurrent multi-endpoint fetch with partial failure handling. This is the "senior signal" prompt.

---

## Architecture at a Glance

```
PortfolioService
  ├── fetchHoldings()         -->  [Stock]
  └── fetchQuote(for:)        -->  StockQuote (per holding, called concurrently)
          │
          ▼
PortfolioViewModel
  └── fetchAllQuotes(for:)    -->  TaskGroup  -->  [PortfolioItem]
          │
          ▼
PortfolioView
  ├── Summary header (total value)
  └── Holdings list (per-row success or "Price unavailable")
```

The key pattern: **fetch a list, then fan out concurrent requests for each item, collect results with per-item error handling.**

---

## 1. Models

Three types, each with a clear role:

```swift
struct Stock: Identifiable {
    let id: String      // ticker symbol (AAPL, GOOG, etc.)
    let name: String
    let shares: Double
}

struct StockQuote {
    let symbol: String
    let price: Double
    let change: Double
}

struct PortfolioItem: Identifiable {
    let id: String
    let name: String
    let shares: Double
    let quote: Result<StockQuote, Error>
    ...
}
```

**Why `Result<StockQuote, Error>` on `PortfolioItem`?**

This is the core design decision. Each holding carries its own success/failure independently. If AAPL's quote fails but GOOG's succeeds, you still display GOOG. The alternative — throwing from the whole batch — would give you all-or-nothing, which is worse UX.

**Computed properties for convenience:**

```swift
var marketValue: Double? {
    if case .success(let q) = quote { return q.price * shares }
    return nil
}

var quoteValue: StockQuote? {
    if case .success(let q) = quote { return q }
    return nil
}
```

- `marketValue` — price x shares, or `nil` if the quote failed. Used for the total calculation.
- `quoteValue` — unwraps the success case for the view. Clean pattern to avoid `if case let` in the view body.

---

## 2. Service

```swift
struct PortfolioService {
    func fetchHoldings() async throws -> [Stock] { ... }
    func fetchQuote(for symbol: String) async throws -> StockQuote { ... }
}
```

Two methods, mirroring two endpoints. In a real interview, these would hit actual URLs. Here they return hardcoded data with simulated delays and random failures.

**The mock simulates:**
- **Random latency** (200-1000ms per quote) — so quotes arrive at different times, exercising the TaskGroup collection
- **~15% failure rate** — so you see partial failures on most refreshes
- **8 holdings** — enough to see concurrent behavior, not so many it's slow

**If asked "would you change anything for production?"** — swap the static data for real `URLSession` calls. The interface stays identical. The ViewModel doesn't change at all.

---

## 3. ViewModel — The Core of This Prompt

### fetchPortfolio()

```swift
func fetchPortfolio() async {
    state = .loading
    do {
        let holdings = try await service.fetchHoldings()
        let items = await fetchAllQuotes(for: holdings)
        state = .loaded(items)
    } catch {
        state = .error(error.localizedDescription)
    }
}
```

Two-phase fetch:
1. Fetch holdings list — if THIS fails, show full-screen error (we have nothing to display)
2. Fetch all quotes concurrently — partial failures are OK (we still have the holdings)

Note: `fetchAllQuotes` does NOT throw. It always returns a result for every holding (success or failure per item). Only the initial `fetchHoldings()` can put us in the `.error` state.

### fetchAllQuotes() — TaskGroup

```swift
private func fetchAllQuotes(for holdings: [Stock]) async -> [PortfolioItem] {
    await withTaskGroup(of: PortfolioItem.self) { group in
        for stock in holdings {
            group.addTask {
                do {
                    let quote = try await self.service.fetchQuote(for: stock.id)
                    return PortfolioItem(..., quote: .success(quote))
                } catch {
                    return PortfolioItem(..., quote: .failure(error))
                }
            }
        }

        var items: [PortfolioItem] = []
        for await item in group {
            items.append(item)
        }
        return items.sorted { $0.id < $1.id }
    }
}
```

**Line by line:**

| Line | What it does |
|---|---|
| `withTaskGroup(of: PortfolioItem.self)` | Creates a structured task group. All child tasks must return `PortfolioItem`. |
| `for stock in holdings` | Loops over all holdings... |
| `group.addTask { }` | ...and adds a concurrent task for each. All 8 fire at once, not sequentially. |
| `do/catch` inside each task | Per-item error handling. A failed quote wraps the error in `.failure()` instead of crashing the group. |
| `for await item in group` | Collects results as they complete (order is non-deterministic). |
| `.sorted { $0.id < $1.id }` | Restores alphabetical order since TaskGroup results arrive in completion order, not submission order. |

**Why `withTaskGroup` and not `async let`?**

- `async let` requires you to know the number of concurrent tasks at compile time (one variable per task)
- `withTaskGroup` works with a dynamic number of tasks (loop over an array)
- For 8 holdings, `async let` would mean 8 separate variables — ugly and not scalable

**If asked "what about `ThrowingTaskGroup`?"**

`withThrowingTaskGroup` would propagate the first error and cancel remaining tasks. We don't want that — we want all tasks to complete and handle failures individually. So we use the non-throwing `withTaskGroup` and catch errors inside each task.

### Computed Properties

```swift
var totalValue: Double {
    guard case .loaded(let items) = state else { return 0 }
    return items.compactMap(\.marketValue).reduce(0, +)
}

var hasPartialFailures: Bool {
    guard case .loaded(let items) = state else { return false }
    return items.contains { $0.marketValue == nil }
}
```

- `totalValue` — `compactMap` skips `nil` (failed quotes), sums only successful ones
- `hasPartialFailures` — checks if any item has no market value, used to show a warning banner

---

## 4. Views

### PortfolioView

Same `switch viewModel.state` pattern as Prompts 1 and 2.

**New piece — `.refreshable`:**

```swift
.refreshable {
    await viewModel.fetchPortfolio()
}
```

That's it. SwiftUI gives you native pull-to-refresh for free. The closure is `async`, so it naturally waits for the fetch to complete before hiding the refresh spinner. No manual `isRefreshing` bool needed.

### Summary Header

```swift
Text(viewModel.totalValue, format: .currency(code: "USD"))
```

Uses Swift's `FormatStyle` API instead of `String(format:)`. Benefits:
- Locale-aware (comma grouping, decimal separator)
- Handles currency symbol automatically
- The modern Swift approach — interviewers like seeing it

### HoldingRowView

```swift
if let quote = item.quoteValue, let value = item.marketValue {
    // Show price + change (green/red)
} else {
    Text("Price unavailable")
}
```

Each row handles its own success/failure independently. A failed quote just shows "Price unavailable" — doesn't affect other rows.

**Change indicator:**

```swift
Text(quote.change, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
```

- `.precision(.fractionLength(2))` — always two decimal places
- `.sign(strategy: .always())` — shows `+` for positive values (e.g. `+1.34`)

---

## The Big Picture — Why This Pattern Matters

This is the exact pattern used in production apps that aggregate data from multiple sources:

```
1. Fetch a list of things
2. For each thing, concurrently fetch detail/enrichment data
3. Collect all results, handling per-item failures
4. Display what you have, indicate what failed
```

Real-world examples:
- Portfolio screen: holdings + prices (this prompt)
- Social feed: posts + user profiles + like counts
- Search results: items + availability + pricing from different providers
- Dashboard: multiple metrics from different microservices

---

## Common Interview Follow-ups

**"Why not fetch all quotes in a single batch request?"**
- If the API supports it (e.g. `GET /quotes?symbols=AAPL,GOOG,TSLA`), absolutely do that instead. One request is simpler and faster. TaskGroup is for when you MUST make separate requests per item. Be ready to discuss both approaches.

**"How would you add a timeout for the whole batch?"**
- Wrap the `fetchAllQuotes` call in a `Task` with a timeout using `withThrowingTaskGroup` and a deadline task that throws after N seconds. Or use `Task.sleep` + cancellation.

**"What about rate limiting?"**
- If the API limits concurrent requests, you could use a semaphore pattern or process the TaskGroup in batches (e.g. 5 at a time). Mention `AsyncSemaphore` or manual batching.

**"Why `Result` instead of an optional?"**
- `Result` preserves the error. If you wanted to show "Timed out" vs. "Server error" per row, you can. An optional just gives you `nil` with no context.

**"How does pull-to-refresh know when to stop spinning?"**
- `.refreshable` receives an `async` closure. SwiftUI keeps the spinner until the closure returns. Since `fetchPortfolio()` is `async` and we `await` it, the spinner stops exactly when the data is ready.

**"What if the user pulls to refresh while already loading?"**
- Currently it would fire a second fetch. To prevent that, add a guard: `guard state != .loading else { return }` at the top of `fetchPortfolio()`. Mention this as a refinement.

**"Why sort the results?"**
- `TaskGroup` collects results in completion order (whichever network request finishes first). Without sorting, the list would shuffle on every refresh. Sorting by `id` (ticker symbol, alphabetical) gives stable, predictable order.
