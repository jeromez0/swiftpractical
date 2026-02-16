import SwiftUI

// MARK: - Models

struct Stock: Identifiable {
    let id: String // ticker symbol
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

    var marketValue: Double? {
        if case .success(let q) = quote { return q.price * shares }
        return nil
    }

    var quoteValue: StockQuote? {
        if case .success(let q) = quote { return q }
        return nil
    }
}

// MARK: - Service

struct PortfolioService {
    private static let holdings: [Stock] = [
        Stock(id: "AAPL", name: "Apple Inc.", shares: 15),
        Stock(id: "GOOG", name: "Alphabet Inc.", shares: 8),
        Stock(id: "TSLA", name: "Tesla Inc.", shares: 12),
        Stock(id: "AMZN", name: "Amazon.com Inc.", shares: 5),
        Stock(id: "MSFT", name: "Microsoft Corp.", shares: 20),
        Stock(id: "NVDA", name: "NVIDIA Corp.", shares: 10),
        Stock(id: "META", name: "Meta Platforms Inc.", shares: 7),
        Stock(id: "NFLX", name: "Netflix Inc.", shares: 3),
    ]

    private static let quotes: [String: StockQuote] = [
        "AAPL": StockQuote(symbol: "AAPL", price: 182.52, change: 1.34),
        "GOOG": StockQuote(symbol: "GOOG", price: 175.30, change: -0.87),
        "TSLA": StockQuote(symbol: "TSLA", price: 248.91, change: 5.62),
        "AMZN": StockQuote(symbol: "AMZN", price: 198.44, change: 2.15),
        "MSFT": StockQuote(symbol: "MSFT", price: 415.60, change: -1.23),
        "NVDA": StockQuote(symbol: "NVDA", price: 131.88, change: 3.47),
        "META": StockQuote(symbol: "META", price: 595.21, change: -4.10),
        "NFLX": StockQuote(symbol: "NFLX", price: 912.33, change: 8.75),
    ]

    func fetchHoldings() async throws -> [Stock] {
        try await Task.sleep(for: .milliseconds(.random(in: 300...800)))
        return Self.holdings
    }

    func fetchQuote(for symbol: String) async throws -> StockQuote {
        try await Task.sleep(for: .milliseconds(.random(in: 200...1000)))

        // Simulate ~15% chance of failure per quote
        if Int.random(in: 0..<20) < 3 {
            throw URLError(.timedOut)
        }

        guard let quote = Self.quotes[symbol] else {
            throw URLError(.badServerResponse)
        }
        return quote
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class PortfolioViewModel {
    private(set) var state: ViewState<[PortfolioItem]> = .idle

    private let service: PortfolioService

    init(service: PortfolioService = PortfolioService()) {
        self.service = service
    }

    var totalValue: Double {
        guard case .loaded(let items) = state else { return 0 }
        return items.compactMap(\.marketValue).reduce(0, +)
    }

    var hasPartialFailures: Bool {
        guard case .loaded(let items) = state else { return false }
        return items.contains { $0.marketValue == nil }
    }

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

    private func fetchAllQuotes(for holdings: [Stock]) async -> [PortfolioItem] {
        await withTaskGroup(of: PortfolioItem.self) { group in
            for stock in holdings {
                group.addTask {
                    do {
                        let quote = try await self.service.fetchQuote(for: stock.id)
                        return PortfolioItem(
                            id: stock.id,
                            name: stock.name,
                            shares: stock.shares,
                            quote: .success(quote)
                        )
                    } catch {
                        return PortfolioItem(
                            id: stock.id,
                            name: stock.name,
                            shares: stock.shares,
                            quote: .failure(error)
                        )
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
}

// MARK: - Views

struct PortfolioView: View {
    @State private var viewModel = PortfolioViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading portfolio...")
                case .loaded(let items):
                    portfolioList(items: items)
                case .error(let message):
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.fetchPortfolio() }
                        }
                    }
                }
            }
            .navigationTitle("Portfolio")
            .task {
                await viewModel.fetchPortfolio()
            }
        }
    }

    private func portfolioList(items: [PortfolioItem]) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Portfolio Value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.totalValue, format: .currency(code: "USD"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.vertical, 8)

                if viewModel.hasPartialFailures {
                    Label("Some prices unavailable", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Holdings") {
                ForEach(items) { item in
                    HoldingRowView(item: item)
                }
            }
        }
        .refreshable {
            await viewModel.fetchPortfolio()
        }
    }
}

struct HoldingRowView: View {
    let item: PortfolioItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.id)
                    .font(.headline)
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let quote = item.quoteValue, let value = item.marketValue {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    HStack(spacing: 2) {
                        Image(systemName: quote.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(quote.change, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                            .font(.caption)
                    }
                    .foregroundStyle(quote.change >= 0 ? .green : .red)
                }
            } else {
                Text("Price unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
