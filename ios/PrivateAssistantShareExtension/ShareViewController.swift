import Foundation
import PrivateAssistantShared
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private var hasLoadedDraft = false
    private var draftPayload: MobileIntakePayload?
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let textView = UITextView()
    private let pageURLField = UITextField()
    private let sourceAppField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let previewImageView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.text = "Review the shared content before uploading."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)

        previewImageView.contentMode = .scaleAspectFit
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = 12
        previewImageView.backgroundColor = .secondarySystemBackground
        previewImageView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        textView.font = .preferredFont(forTextStyle: .body)
        textView.layer.cornerRadius = 12
        textView.backgroundColor = .secondarySystemBackground
        textView.heightAnchor.constraint(equalToConstant: 140).isActive = true

        pageURLField.borderStyle = .roundedRect
        pageURLField.placeholder = "Page URL"
        pageURLField.autocapitalizationType = .none

        sourceAppField.borderStyle = .roundedRect
        sourceAppField.placeholder = "Source App"
        sourceAppField.autocapitalizationType = .words

        sendButton.setTitle("Send", for: .normal)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, sendButton])
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 12

        let stack = UIStackView(arrangedSubviews: [
            statusLabel,
            previewImageView,
            textView,
            pageURLField,
            sourceAppField,
            activityIndicator,
            buttonRow,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
        activityIndicator.isHidden = true
        previewImageView.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true

        Task {
            await loadDraft()
        }
    }

    private func loadDraft() async {
        do {
            let payload = try await makePayload()
            draftPayload = payload
            textView.text = payload.textInput ?? ""
            pageURLField.text = payload.pageURL
            sourceAppField.text = payload.sourceApp
            if let imageData = payload.imageData, let image = UIImage(data: imageData) {
                previewImageView.image = image
                previewImageView.isHidden = false
            }
        } catch {
            statusLabel.text = error.localizedDescription
        }
    }

    @objc
    private func sendTapped() {
        Task {
            await uploadDraft()
        }
    }

    @objc
    private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "PrivateAssistantShare", code: 0))
    }

    private func uploadDraft() async {
        guard var payload = draftPayload else {
            statusLabel.text = "No content to send."
            return
        }

        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        sendButton.isEnabled = false
        cancelButton.isEnabled = false

        payload = MobileIntakePayload(
            imageData: payload.imageData,
            imageFilename: payload.imageFilename,
            imageContentType: payload.imageContentType,
            textInput: textView.text,
            pageURL: pageURLField.text,
            sourceApp: sourceAppField.text,
            sourceType: payload.sourceType,
            capturedAt: payload.capturedAt
        )

        do {
            let response = try await PrivateAssistantAPIClient().submitMobileIntake(payload)
            statusLabel.text = response.analysis?.summary ?? response.message
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.text = error.localizedDescription
            sendButton.isEnabled = true
            cancelButton.isEnabled = true
        }
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    private func makePayload() async throws -> MobileIntakePayload {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            throw PrivateAssistantAPIError.emptyPayload
        }

        var textInput: String?
        var pageURL: String?
        var imageData: Data?
        var imageFilename: String?
        var imageContentType: String?

        for item in items {
            if textInput == nil {
                textInput = item.attributedContentText?.string
            }

            for provider in item.attachments ?? [] {
                if imageData == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageData = try await provider.loadData(forTypeIdentifier: UTType.image.identifier)
                    imageFilename = provider.suggestedName ?? "shared-image.jpg"
                    imageContentType = "image/jpeg"
                    continue
                }

                if pageURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    pageURL = try await provider.loadURL()?.absoluteString
                    continue
                }

                if textInput == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    textInput = try await provider.loadPlainText()
                }
            }
        }

        return MobileIntakePayload(
            imageData: imageData,
            imageFilename: imageFilename,
            imageContentType: imageContentType,
            textInput: textInput,
            pageURL: pageURL,
            sourceApp: nil,
            sourceType: SourceType.shareExtension.rawValue,
            capturedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

@MainActor
private extension NSItemProvider {
    func loadData(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                    return
                }
                continuation.resume(throwing: error ?? PrivateAssistantAPIError.invalidResponse)
            }
        }
    }

    func loadURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    func loadPlainText() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: NSString.self) { string, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let string = string {
                    continuation.resume(returning: String(string as! Substring))
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
}
