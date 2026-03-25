import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let strings = model.strings

        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.95)
                .ignoresSafeArea()

            TabView {
                CaptureComposerView()
                    .tabItem {
                        Label(strings.captureTab, systemImage: "sparkles.rectangle.stack")
                    }

                ActivityView()
                    .tabItem {
                        Label(strings.activityTab, systemImage: "tray.full")
                    }

                LedgerView()
                    .tabItem {
                        Label(strings.ledgerTab, systemImage: "list.bullet.rectangle")
                    }

                SettingsView()
                    .tabItem {
                        Label(strings.settingsTab, systemImage: "gearshape")
                    }
            }
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(red: 0.97, green: 0.97, blue: 0.95), for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .task {
            await model.refreshActivityIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await model.refreshActivityIfNeeded()
                }
            } else {
                model.stopSpeechCapture()
            }
        }
    }
}
