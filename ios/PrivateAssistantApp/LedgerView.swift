import PrivateAssistantShared
import SwiftUI

struct LedgerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let strings = model.strings
        let navigationBackground = Color(red: 0.96, green: 0.97, blue: 0.95)

        NavigationStack {
            ZStack {
                navigationBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            statCard(title: strings.entries, value: strings.filteredCount(model.ledgerEntries.count), tint: .green)
                            statCard(title: strings.latest, value: model.ledgerLatestAmount, tint: Color(red: 0.82, green: 0.33, blue: 0.12))
                            statCard(title: strings.totalAmount, value: formattedAmount(model.ledgerVisibleTotalAmount), tint: .blue)
                        }

                        if model.ledgerSearchFilters.hasActiveFilters {
                            activeFiltersBanner
                        }

                        if model.ledgerEntries.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(model.ledgerEntries) { entry in
                                    Button {
                                        Task {
                                            await model.loadLedgerDetail(for: entry.id)
                                        }
                                    } label: {
                                        ledgerCard(entry)
                                    }
                                    .buttonStyle(.plain)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay {
                if model.isRefreshingActivity && model.ledgerEntries.isEmpty {
                    ProgressView()
                }
            }
            .overlay {
                if model.isLoadingLedgerDetail {
                    ZStack {
                        Color.black.opacity(0.08)
                            .ignoresSafeArea()
                        ProgressView()
                            .padding(24)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .navigationTitle(strings.ledgerTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(navigationBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.isPresentingLedgerFilters = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .searchable(text: $model.ledgerSearchFilters.query, prompt: strings.ledgerSearchPrompt)
            .onSubmit(of: .search) {
                Task {
                    await model.applyLedgerFilters()
                }
            }
            .sheet(isPresented: $model.isPresentingLedgerFilters) {
                LedgerFilterSheet()
                    .environmentObject(model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $model.selectedLedgerDetail) { detail in
                LedgerDetailSheet(detail: detail)
                    .environmentObject(model)
            }
            .task {
                if model.ledgerEntries.isEmpty {
                    await model.reloadActivity()
                }
            }
        }
    }

    private var emptyState: some View {
        let strings = model.strings

        return VStack(spacing: 12) {
            Image(systemName: model.ledgerSearchFilters.hasActiveFilters ? "line.3.horizontal.decrease.circle" : "wallet.bifold")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(model.ledgerSearchFilters.hasActiveFilters ? strings.noSearchResults : strings.noLedger)
                .font(.headline)
            Text(model.ledgerSearchFilters.hasActiveFilters ? strings.noSearchResultsHint : strings.noLedgerHint)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var activeFiltersBanner: some View {
        let strings = model.strings

        return VStack(alignment: .leading, spacing: 10) {
            Label(strings.advancedFilters, systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(.headline)
                .foregroundStyle(Color(red: 0.82, green: 0.33, blue: 0.12))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !model.ledgerSearchFilters.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        filterChip(model.ledgerSearchFilters.query)
                    }
                    if !model.ledgerSearchFilters.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        filterChip(model.ledgerSearchFilters.category)
                    }
                    if !model.ledgerSearchFilters.amountMin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        filterChip("≥ \(model.ledgerSearchFilters.amountMin)")
                    }
                    if !model.ledgerSearchFilters.amountMax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        filterChip("≤ \(model.ledgerSearchFilters.amountMax)")
                    }
                    if let dateFrom = model.ledgerSearchFilters.dateFrom {
                        filterChip("\(model.strings.fromDate): \(dateLabel(dateFrom))")
                    }
                    if let dateTo = model.ledgerSearchFilters.dateTo {
                        filterChip("\(model.strings.toDate): \(dateLabel(dateTo))")
                    }
                    filterChip("\(strings.sortBy): \(strings.localizedLedgerSortBy(model.ledgerSearchFilters.sortBy))")
                    filterChip("\(strings.sortOrder): \(strings.localizedLedgerSortOrder(model.ledgerSearchFilters.sortOrder))")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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

    private func ledgerCard(_ entry: LedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.merchant ?? model.strings.unknownMerchant)
                        .font(.headline)
                    Text(entry.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(entry.actualAmount) \(entry.currency ?? "")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    if let originalAmount = entry.originalAmount, originalAmount != entry.actualAmount {
                        Text("\(model.strings.originalAmountLabel): \(originalAmount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                if let category = entry.category, !category.isEmpty {
                    ledgerTag(category.capitalized)
                }
                if let occurredAt = entry.occurredAt, !occurredAt.isEmpty {
                    ledgerTag(model.strings.occurredAt(occurredAt))
                }
                ledgerTag(model.strings.localizedIntent(entry.intent))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func ledgerTag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.94, green: 0.96, blue: 0.93))
            .clipShape(Capsule())
    }

    private func filterChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.97, green: 0.93, blue: 0.89))
            .foregroundStyle(Color(red: 0.45, green: 0.19, blue: 0.07))
            .clipShape(Capsule())
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct LedgerFilterSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = model.strings

        NavigationStack {
            Form {
                Section(strings.searchQuery) {
                    TextField(strings.ledgerSearchPrompt, text: $model.ledgerSearchFilters.query)
                }

                Section(strings.categoryFilter) {
                    Picker(strings.categoryFilter, selection: $model.ledgerSearchFilters.category) {
                        Text(strings.allCategories).tag("")
                        ForEach(model.ledgerFilterOptions.categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }

                Section(strings.amountRange) {
                    TextField(strings.minimumAmount, text: $model.ledgerSearchFilters.amountMin)
                        .keyboardType(.decimalPad)
                    TextField(strings.maximumAmount, text: $model.ledgerSearchFilters.amountMax)
                        .keyboardType(.decimalPad)
                }

                Section(strings.fromDate) {
                    Toggle(strings.fromDate, isOn: includeDateFromBinding)
                    if includeDateFromBinding.wrappedValue {
                        DatePicker(
                            strings.fromDate,
                            selection: Binding(
                                get: { model.ledgerSearchFilters.dateFrom ?? Date() },
                                set: { model.ledgerSearchFilters.dateFrom = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                Section(strings.toDate) {
                    Toggle(strings.toDate, isOn: includeDateToBinding)
                    if includeDateToBinding.wrappedValue {
                        DatePicker(
                            strings.toDate,
                            selection: Binding(
                                get: { model.ledgerSearchFilters.dateTo ?? Date() },
                                set: { model.ledgerSearchFilters.dateTo = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                Section(strings.sortBy) {
                    Picker(strings.sortBy, selection: $model.ledgerSearchFilters.sortBy) {
                        ForEach(LedgerSortBy.allCases) { sortBy in
                            Text(strings.localizedLedgerSortBy(sortBy)).tag(sortBy)
                        }
                    }
                }

                Section(strings.sortOrder) {
                    Picker(strings.sortOrder, selection: $model.ledgerSearchFilters.sortOrder) {
                        ForEach(LedgerSortOrder.allCases) { sortOrder in
                            Text(strings.localizedLedgerSortOrder(sortOrder)).tag(sortOrder)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(strings.advancedFilters)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(strings.resetFilters) {
                        Task {
                            await model.resetLedgerFilters()
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.applyFilters) {
                        Task {
                            await model.applyLedgerFilters()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var includeDateFromBinding: Binding<Bool> {
        Binding(
            get: { model.ledgerSearchFilters.dateFrom != nil },
            set: { enabled in
                model.ledgerSearchFilters.dateFrom = enabled ? (model.ledgerSearchFilters.dateFrom ?? Date()) : nil
            }
        )
    }

    private var includeDateToBinding: Binding<Bool> {
        Binding(
            get: { model.ledgerSearchFilters.dateTo != nil },
            set: { enabled in
                model.ledgerSearchFilters.dateTo = enabled ? (model.ledgerSearchFilters.dateTo ?? Date()) : nil
            }
        )
    }
}

private struct LedgerDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let detail: LedgerEntryDetail

    var body: some View {
        let strings = model.strings

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail.merchant ?? strings.unknownMerchant)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(strings.localizedIntent(detail.intent))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(strings.amountBreakdown)
                            .font(.headline)

                        detailRow(strings.originalAmountLabel, value: detail.originalAmount ?? detail.actualAmount)
                        detailRow(strings.discountAmountLabel, value: detail.discountAmount)
                        detailRow(strings.payableAmountLabel, value: "\(detail.actualAmount) \(detail.currency ?? "")")
                    }
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(strings.metadataSection)
                            .font(.headline)
                        detailRow(strings.merchantLabel, value: detail.merchant ?? strings.unknownMerchant)
                        detailRow(strings.categoryLabel, value: detail.category ?? "-")
                        detailRow(strings.currencyLabel, value: detail.currency ?? "-")
                        detailRow(strings.createdAtLabel, value: detail.createdAt)
                        detailRow(strings.occurredAtLabel, value: detail.effectiveOccurredAt)
                        detailRow(strings.sourceImageLabel, value: detail.sourceImagePath)
                    }
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(strings.rawModelResponse)
                            .font(.headline)
                        Text(detail.rawModelResponseJSON)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(red: 0.95, green: 0.95, blue: 0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(20)
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.95).ignoresSafeArea())
            .navigationTitle(strings.ledgerDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.ok) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}
