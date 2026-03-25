import AVFoundation
import Foundation
import Speech

enum SpeechCaptureError: LocalizedError {
    case speechRecognizerUnavailable
    case speechAuthorizationDenied
    case microphoneAuthorizationDenied
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognition is unavailable on this device."
        case .speechAuthorizationDenied:
            return "Speech recognition permission is required."
        case .microphoneAuthorizationDenied:
            return "Microphone permission is required."
        case .audioInputUnavailable:
            return "Audio input is unavailable."
        }
    }
}

@MainActor
final class SpeechCaptureService {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startTranscribing(
        localeIdentifier: String,
        onUpdate: @escaping @MainActor (_ text: String, _ confidence: Double?) -> Void
    ) async throws {
        try await requestPermissionsIfNeeded()
        stopTranscribing()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechCaptureError.speechRecognizerUnavailable
        }
        self.speechRecognizer = recognizer

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.channelCount > 0 else {
            throw SpeechCaptureError.audioInputUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                Task { @MainActor in
                    onUpdate(result.bestTranscription.formattedString, nil)
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.stopTranscribing()
                }
            }
        }
    }

    func stopTranscribing() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissionsIfNeeded() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw SpeechCaptureError.speechAuthorizationDenied
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard microphoneGranted else {
            throw SpeechCaptureError.microphoneAuthorizationDenied
        }
    }
}
