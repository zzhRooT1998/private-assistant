import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Backend")
                            .font(.headline)
                        TextField("Server Base URL", text: $model.baseURLString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button("Save Endpoint") {
                            model.saveBaseURL()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.82, green: 0.33, blue: 0.12))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(18)
                    .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Current Endpoint", systemImage: "network")
                            .font(.headline)
                        Text(model.baseURLString)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Notes", systemImage: "info.circle")
                            .font(.headline)
                        Text("Use 127.0.0.1 only in the iOS Simulator. On a physical iPhone, replace it with your public tunnel or your Mac's LAN IP.")
                        Text("This build avoids App Groups so it can run with a Personal Team account. Update the endpoint separately inside the main app if the extension still points at an older value.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(20)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.95).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
