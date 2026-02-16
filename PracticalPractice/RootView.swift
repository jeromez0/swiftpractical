import SwiftUI

@main
struct PracticalPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Contacts", systemImage: "person.crop.circle") {
                    UserListView()
                }
            }
        }
    }
}
