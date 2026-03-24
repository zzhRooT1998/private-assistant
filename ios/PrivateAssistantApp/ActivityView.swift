import PrivateAssistantShared
import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let strings = model.strings

        NavigationStack {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.95)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            summaryMetric(title: strings.todos, value: "\(model.todoEntries.count)", color: .orange)
                            summaryMetric(title: strings.references, value: "\(model.referenceEntries.count)", color: .blue)
                            summaryMetric(title: strings.schedule, value: "\(model.scheduleEntries.count)", color: .pink)
                        }

                        if model.todoEntries.isEmpty && model.referenceEntries.isEmpty && model.scheduleEntries.isEmpty {
                            emptyState
                        } else {
                            if !model.todoEntries.isEmpty {
                                activitySection(strings.todos, systemImage: "checklist", tint: .orange) {
                                    ForEach(model.todoEntries) { entry in
                                        activityCard(title: entry.title, subtitle: entry.details, meta: entry.dueAt ?? entry.createdAt)
                                    }
                                }
                            }

                            if !model.referenceEntries.isEmpty {
                                activitySection(strings.references, systemImage: "bookmark", tint: .blue) {
                                    ForEach(model.referenceEntries) { entry in
                                        activityCard(title: entry.title, subtitle: entry.summary, meta: entry.pageURL ?? entry.createdAt)
                                    }
                                }
                            }

                            if !model.scheduleEntries.isEmpty {
                                activitySection(strings.schedule, systemImage: "calendar", tint: .pink) {
                                    ForEach(model.scheduleEntries) { entry in
                                        activityCard(title: entry.title, subtitle: entry.details, meta: entry.startAt)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .refreshable {
                    await model.reloadActivity()
                }
            }
            .overlay {
                if model.isRefreshingActivity && model.todoEntries.isEmpty && model.referenceEntries.isEmpty && model.scheduleEntries.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle(strings.activityTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                if model.todoEntries.isEmpty && model.referenceEntries.isEmpty && model.scheduleEntries.isEmpty {
                    await model.reloadActivity()
                }
            }
        }
    }

    private var emptyState: some View {
        let strings = model.strings
        return VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(strings.noActivity)
                .font(.headline)
            Text(strings.noActivityHint)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func activitySection<Content: View>(_ title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
    }

    private func activityCard(title: String, subtitle: String?, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(meta)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
