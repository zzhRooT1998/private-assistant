import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            CaptureComposerView()
                .tabItem {
                    Label("Capture", systemImage: "sparkles.rectangle.stack")
                }

            ActivityView()
                .tabItem {
                    Label("Activity", systemImage: "tray.full")
                }

            LedgerView()
                .tabItem {
                    Label("Ledger", systemImage: "list.bullet.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .toolbarBackground(.visible, for: .tabBar)
    }
}
