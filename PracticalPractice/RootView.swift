import SwiftUI

@main
struct PracticalPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Contacts", systemImage: "person.crop.circle") {
                    UserListView()
                }
                Tab("Stage 1", systemImage: "1.circle") {
                    Stage1FeedView()
                }
                Tab("Stage 2", systemImage: "2.circle") {
                    Stage2FeedView()
                }
                Tab("Photos", systemImage: "photo.on.rectangle") {
                    PhotoFeedView()
                }
                Tab("Portfolio", systemImage: "chart.line.uptrend.xyaxis") {
                    PortfolioView()
                }
            }
        }
    }
}
