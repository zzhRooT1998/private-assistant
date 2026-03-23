import Foundation
import PhotosUI
import PrivateAssistantShared
import SwiftUI

@MainActor
struct CaptureComposerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard

                    if let response = model.lastResponse {
                        resultCard(response)
                    }

                    contextCard
                    screenshotCard
                    actionCard
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.96, blue: 0.93),
                        Color(red: 0.95, green: 0.95, blue: 0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if model.totalActivityCount == 0 {
                    await model.reloadActivity()
                }
            }
            .alert("Request Failed", isPresented: Binding(get: {
                model.errorMessage != nil
            }, set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            })) {
                Button("OK", role: .cancel) {
                    model.errorMessage = nil
                }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turn a screen into an action")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Paste text, attach a screenshot, or drop in a page URL. The assistant will classify the capture and execute bookkeeping, todo, reference, or schedule workflows.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
            HStack(spacing: 10) {
                badge("Live Intake", systemImage: "sparkles")
                badge(model.sourceType.displayName, systemImage: "app.connected.to.app.below.fill")
                if model.totalActivityCount > 0 {
                    badge("\(model.totalActivityCount) Saved", systemImage: "tray.full.fill")
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
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Context", systemImage: "text.bubble")

            inputLabel("Shared Text")
            TextField("Paste message text or notes", text: $model.textInput, axis: .vertical)
                .lineLimit(4...8)
                .appInputStyle()

            inputLabel("Page URL")
            TextField("https://example.com/article", text: $model.pageURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .appInputStyle()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    inputLabel("Source App")
                    TextField("Safari, WeChat, Photos", text: $model.sourceApp)
                        .appInputStyle()
                }

                VStack(alignment: .leading, spacing: 8) {
                    inputLabel("Source Type")
                    Picker("Source Type", selection: $model.sourceType) {
                        ForEach(SourceType.allCases) { sourceType in
                            Text(sourceType.displayName).tag(sourceType)
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
        let hasPreviewImage = model.previewImage != nil

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Screenshot", systemImage: "photo.on.rectangle")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text(hasPreviewImage ? "Replace Screenshot" : "Choose Screenshot")
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
                        Text("Attached")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                    }
            } else {
                Text("Attach a receipt, article page, map, or a message screenshot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .captureCardStyle()
    }

    private var actionCard: some View {
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Actions", systemImage: "paperplane")

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
                        Text("Send To Assistant")
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

            Button("Clear Draft", role: .destructive) {
                model.clearComposer()
                pickerItem = nil
            }
        }
        .captureCardStyle()
    }

    private func resultCard(_ response: MobileIntakeResponse) -> some View {
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest Result")
                        .font(.headline)
                    Text(response.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(response.intent.capitalized)
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

            HStack(spacing: 10) {
                metricPill(title: "Confidence", value: String(format: "%.0f%%", response.confidence * 100))
                if let action = response.executedAction {
                    metricPill(title: "Action", value: action.replacingOccurrences(of: "_", with: " "))
                }
                if let amount = response.analysis?.actualAmount {
                    metricPill(title: "Amount", value: amount)
                }
            }

            if let sourceApp = response.analysis?.sourceApp, !sourceApp.isEmpty {
                LabeledContent("Source", value: sourceApp)
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
