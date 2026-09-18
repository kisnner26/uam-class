import SwiftUI

@main
struct UAMClassWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
            .task {
                NotificationPlanner.requestAuthorization()
                WatchConnectivityManager.shared.activate()
            }
        }
    }
}
