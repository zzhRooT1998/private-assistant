import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let strings = model.strings

        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.95)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(strings.backend)
                                .font(.headline)
                            TextField(strings.serverBaseURL, text: $model.baseURLString)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Button(strings.saveEndpoint) {
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
                            Label(strings.currentEndpoint, systemImage: "network")
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

                        VStack(alignment: .leading, spacing: 12) {
                            Label(strings.languageSection, systemImage: "globe")
                                .font(.headline)
                            Picker(strings.languageSection, selection: $model.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: model.language) { _, _ in
                                model.saveLanguage()
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            Label(strings.notificationSection, systemImage: "bell.badge")
                                .font(.headline)
                            Text(strings.notificationHelp)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button(strings.enableNotifications) {
                                Task {
                                    await model.requestNotificationAuthorization()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.18, green: 0.24, blue: 0.31))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Label(strings.notes, systemImage: "info.circle")
                                .font(.headline)
                            Text(strings.noteSimulator)
                            Text(strings.notePersonalTeam)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .padding(20)
                }
            }
            .navigationTitle(strings.settingsTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
