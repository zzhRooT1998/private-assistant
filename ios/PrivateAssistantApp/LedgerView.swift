import SwiftUI

struct LedgerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let strings = model.strings

        NavigationStack {
            ZStack {
                Color(red: 0.96, green: 0.97, blue: 0.95)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            statCard(title: strings.entries, value: "\(model.ledgerEntries.count)", tint: .green)
                            statCard(
                                title: strings.latest,
                                value: model.ledgerEntries.first?.actualAmount ?? "0",
                                tint: Color(red: 0.82, green: 0.33, blue: 0.12)
                            )
                        }

                        if model.ledgerEntries.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "wallet.bifold")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.secondary)
                                Text(strings.noLedger)
                                    .font(.headline)
                                Text(strings.noLedgerHint)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(30)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        } else {
                            VStack(spacing: 12) {
                                ForEach(model.ledgerEntries) { entry in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(entry.merchant ?? "Unknown Merchant")
                                                .font(.headline)
                                            Spacer()
                                            Text("\(entry.actualAmount) \(entry.currency ?? "")")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.green)
                                        }

                                        HStack(spacing: 8) {
                                            if let category = entry.category, !category.isEmpty {
                                                ledgerTag(category.capitalized)
                                            }
                                            if let occurredAt = entry.occurredAt, !occurredAt.isEmpty {
                                                ledgerTag(strings.occurredAt(occurredAt))
                                            }
                                        }

                                        Text(entry.createdAt)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                if model.isRefreshingActivity && model.ledgerEntries.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle(strings.ledgerTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                if model.ledgerEntries.isEmpty {
                    await model.reloadActivity()
                }
            }
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func ledgerTag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.94, green: 0.96, blue: 0.93))
            .clipShape(Capsule())
    }
}
