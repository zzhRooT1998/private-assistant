import SwiftUI

@main
struct PrivateAssistantApp: App {
    @StateObject private var model = AppModel()

    init() {
        AppNotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Color(red: 0.82, green: 0.33, blue: 0.12))
        }
    }
}
