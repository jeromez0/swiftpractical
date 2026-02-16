import SwiftUI

@main
struct PracticalPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Contacts", systemImage: "person.crop.circle") {
                    UserListView()
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
