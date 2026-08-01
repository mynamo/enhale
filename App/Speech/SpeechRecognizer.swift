import Foundation
import Speech
import AVFoundation

/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` into a small observable object
/// the UI can start/stop and read a live transcript from.
///
/// Requires, in Info.plist: `NSMicrophoneUsageDescription` and
/// `NSSpeechRecognitionUsageDescription`. On-device recognition is preferred
/// when the device supports it, so meal descriptions aren't sent to Apple.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Segments already finalized during the current recording. Apple's
    /// recognizer finalizes an utterance after a pause; we keep this and start a
    /// fresh segment so a pause never drops earlier words. `transcript` is always
    /// this plus the live partial.
    private var finalizedText = ""

    /// Ask for mic + speech permission. Call before the first recording.
    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    func startRecording() throws {
        // Reset any prior run.
        task?.cancel()
        task = nil
        finalizedText = ""
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Feed audio to whichever request is current (segments are recreated on
        // pause), so keep the tap referencing `self.request`, not a captured one.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        beginSegment()
    }

    /// Start a recognition task on the already-running audio engine. Called again
    /// after each finalized utterance so recording continues until the user stops.
    private func beginSegment() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                if let result {
                    self.transcript = self.combined(with: result.bestTranscription.formattedString)
                }
                // A finalized utterance (pause) or an error ends this segment.
                // Commit what we have and immediately listen for the next one.
                if error != nil || (result?.isFinal ?? false) {
                    self.finalizedText = self.transcript
                    self.request = nil
                    self.task = nil
                    if self.isRecording { self.beginSegment() }
                }
            }
        }
    }

    /// Finalized segments + the current live partial.
    private func combined(with partial: String) -> String {
        if finalizedText.isEmpty { return partial }
        if partial.isEmpty { return finalizedText }
        return finalizedText + " " + partial
    }

    /// Stop capture (user tapped Stop/Done). The accumulated `transcript` is what
    /// gets sent to the backend via `EnhaleAPIClient.parseMeal`.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false // set first so an in-flight callback won't restart a segment
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
