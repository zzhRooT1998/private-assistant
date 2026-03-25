import Foundation
import PhotosUI
import PrivateAssistantShared
import SwiftUI

@MainActor
struct CaptureComposerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var customIntentInputs: [String: String] = [:]

    var body: some View {
        let strings = model.strings
        let navigationBackground = Color(red: 0.95, green: 0.95, blue: 0.92)

        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.96, blue: 0.93),
                        Color(red: 0.95, green: 0.95, blue: 0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard

                        if !model.pendingIntentReviews.isEmpty {
                            pendingReviewSection
                        }

                        if let response = model.lastResponse {
                            resultCard(response)
                        }

                        contextCard
                        speechCard
                        screenshotCard
                        actionCard
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(strings.captureTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(navigationBackground, for: .navigationBar)
            .task {
                if model.totalActivityCount == 0 {
                    await model.reloadActivity()
                }
            }
            .alert(strings.requestFailed, isPresented: Binding(get: {
                model.errorMessage != nil
            }, set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            })) {
                Button(strings.ok, role: .cancel) {
                    model.errorMessage = nil
                }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var heroCard: some View {
        let strings = model.strings

        return VStack(alignment: .leading, spacing: 12) {
            Text(strings.heroTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(strings.heroDescription)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
            HStack(spacing: 10) {
                badge(strings.liveIntake, systemImage: "sparkles")
                badge(strings.localizedSourceType(model.sourceType), systemImage: "app.connected.to.app.below.fill")
                if model.totalActivityCount > 0 {
                    badge(strings.savedCount(model.totalActivityCount), systemImage: "tray.full.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.24, blue: 0.31),
                    Color(red: 0.50, green: 0.23, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 24, y: 14)
    }

    private var contextCard: some View {
        let strings = model.strings

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(strings.contextSection, systemImage: "text.bubble")

            inputLabel(strings.sharedText)
            TextField(strings.sharedTextPlaceholder, text: $model.textInput, axis: .vertical)
                .lineLimit(4...8)
                .appInputStyle()

            inputLabel(strings.pageURL)
            TextField("https://example.com/article", text: $model.pageURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .appInputStyle()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    inputLabel(strings.sourceApp)
                    TextField(strings.sourceAppPlaceholder, text: $model.sourceApp)
                        .appInputStyle()
                }

                VStack(alignment: .leading, spacing: 8) {
                    inputLabel(strings.sourceType)
                    Picker(strings.sourceType, selection: $model.sourceType) {
                        ForEach(SourceType.allCases) { sourceType in
                            Text(strings.localizedSourceType(sourceType)).tag(sourceType)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
            }
        }
        .captureCardStyle()
    }

    private var screenshotCard: some View {
        let strings = model.strings
        let hasPreviewImage = model.previewImage != nil

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(strings.screenshotSection, systemImage: "photo.on.rectangle")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text(hasPreviewImage ? strings.replaceScreenshot : strings.chooseScreenshot)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
                        .foregroundStyle(Color.black.opacity(0.12))
                )
            }
            .onChange(of: pickerItem) { _, newValue in
                Task {
                    await model.loadSelectedImage(from: newValue)
                }
            }

            if let previewImage = model.previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Text(strings.attached)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                    }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings.screenshotHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(strings.queuedShortcutNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .captureCardStyle()
    }

    private var speechCard: some View {
        let strings = model.strings

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(strings.speechSection, systemImage: "waveform.badge.mic")

            Text(strings.speechHint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await model.toggleSpeechCapture()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isRecordingSpeech ? "stop.circle.fill" : "mic.circle.fill")
                    Text(model.isRecordingSpeech ? strings.stopRecording : strings.startRecording)
                        .fontWeight(.semibold)
                    Spacer()
                    if model.isRecordingSpeech {
                        Text(strings.recordingNow)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.14))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                inputLabel(strings.speechTranscript)
                if model.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(strings.speechPlaceholder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Text(model.speechText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }
            }

            Text(strings.speechPriorityNote)
                .font(.footnote)
                .foregroundStyle(Color(red: 0.43, green: 0.27, blue: 0.11))
        }
        .captureCardStyle()
    }

    private var actionCard: some View {
        let strings = model.strings
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(strings.actionsSection, systemImage: "paperplane")

            Button {
                Task {
                    await model.submitCapture()
                }
            } label: {
                HStack {
                    if model.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                        Text(strings.sendToAssistant)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(model.canSubmit ? Color(red: 0.82, green: 0.33, blue: 0.12) : Color.gray.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(model.isSubmitting || !model.canSubmit)

            Button(strings.clearDraft, role: .destructive) {
                model.clearComposer()
                pickerItem = nil
            }
        }
        .captureCardStyle()
    }

    private func resultCard(_ response: MobileIntakeResponse) -> some View {
        let strings = model.strings
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.latestResult)
                        .font(.headline)
                    Text(response.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(strings.localizedIntent(response.intent))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(intentColor(response.intent).opacity(0.14))
                    .foregroundStyle(intentColor(response.intent))
                    .clipShape(Capsule())
            }

            if let summary = response.analysis?.summary {
                Text(summary)
                    .font(.body)
            }

            if response.requiresConfirmation {
                Text(response.confirmationReason ?? strings.pendingDecisionSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                metricPill(title: strings.confidence, value: String(format: "%.0f%%", response.confidence * 100))
                if let action = response.executedAction {
                    metricPill(title: strings.actionLabel, value: action.replacingOccurrences(of: "_", with: " "))
                }
                if let amount = response.analysis?.actualAmount {
                    metricPill(title: strings.amountLabel, value: amount)
                }
            }

            if let sourceApp = response.analysis?.sourceApp, !sourceApp.isEmpty {
                LabeledContent(strings.sourceLabel, value: sourceApp)
            }
            if let url = response.analysis?.pageURL, !url.isEmpty {
                Text(url)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .captureCardStyle(background: .white)
    }

    private var pendingReviewSection: some View {
        let strings = model.strings

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.pendingDecisionTitle)
                        .font(.headline)
                    Text(strings.pendingDecisionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(strings.refreshPendingReviews) {
                    Task {
                        await model.reloadActivity()
                    }
                }
                .buttonStyle(.bordered)
            }

            ForEach(Array(model.pendingIntentReviews.prefix(3))) { review in
                pendingReviewCard(review)
            }
        }
        .captureCardStyle(background: Color.white)
    }

    private func pendingReviewCard(_ review: IntentReview) -> some View {
        let strings = model.strings
        let isConfirming = model.confirmingReviewID == review.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.suggestedIntents)
                        .font(.headline)
                    Text(review.confirmationReason ?? strings.pendingDecisionSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(review.sourceApp ?? strings.localizedSourceType(review.sourceType))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.95, green: 0.93, blue: 0.90))
                    .clipShape(Capsule())
            }

            if let contextSummary = pendingReviewContext(review) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(strings.pendingReviewContext)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(contextSummary)
                        .font(.subheadline)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(review.rankedIntents.prefix(3)), id: \.intent) { candidate in
                    Button {
                        Task {
                            await model.confirmIntentReview(review, selectedIntent: candidate.intent)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(strings.localizedIntent(candidate.intent))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let summary = candidate.summary ?? candidate.reason {
                                    Text(summary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", candidate.confidence * 100))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(intentColor(candidate.intent).opacity(0.14))
                                .foregroundStyle(intentColor(candidate.intent))
                                .clipShape(Capsule())
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirming)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                inputLabel(strings.customIntentTitle)
                TextField(strings.customIntentPlaceholder, text: customIntentBinding(for: review.id))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .appInputStyle()

                Button {
                    Task {
                        await model.confirmIntentReview(
                            review,
                            customIntent: customIntentInputs[review.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        customIntentInputs[review.id] = ""
                    }
                } label: {
                    HStack {
                        if isConfirming {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                            Text(strings.confirmCustomIntent)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.23, green: 0.36, blue: 0.55))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isConfirming || normalizedCustomIntent(for: review.id) == nil)
            }
        }
        .padding(18)
        .background(Color(red: 0.99, green: 0.98, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func badge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func inputLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func customIntentBinding(for reviewID: String) -> Binding<String> {
        Binding(
            get: { customIntentInputs[reviewID] ?? "" },
            set: { customIntentInputs[reviewID] = $0 }
        )
    }

    private func normalizedCustomIntent(for reviewID: String) -> String? {
        let rawValue = customIntentInputs[reviewID]
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func pendingReviewContext(_ review: IntentReview) -> String? {
        let candidates = [review.speechText, review.textInput, review.pageURL, review.capturedAt]
        var pieces: [String] = []
        for value in candidates {
            guard let value, !value.isEmpty else {
                continue
            }
            pieces.append(value)
        }

        guard !pieces.isEmpty else {
            return nil
        }

        return pieces.joined(separator: "\n")
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.95, green: 0.93, blue: 0.90))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func intentColor(_ intent: String) -> Color {
        switch intent {
        case "bookkeeping":
            return .green
        case "todo":
            return .orange
        case "reference":
            return .blue
        case "schedule":
            return .pink
        default:
            return .gray
        }
    }
}

private extension View {
    func captureCardStyle(background: Color = Color(red: 0.98, green: 0.97, blue: 0.95)) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }

    func appInputStyle() -> some View {
        self
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}
