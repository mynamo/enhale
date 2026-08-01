import Foundation
import Speech
import AVFoundation

/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` into a small observable object
/// the UI can start/stop and read a live transcript from.
///
/// Requires, in Info.plist: `NSMicrophoneUsageDescription` and
/// `NSSpeechRecognitionUsageDescription`. On-device recognition is preferred
/// when the device supports it, so meal descriptions aren't sent to Apple.
///
/// Dictation is continuous: it keeps listening through pauses until the user
/// stops. Each utterance is committed to `finalizedText` (via a short
/// silence-timer, which also survives devices where the recognizer resets its
/// partial transcript on a pause), and a fresh recognition request is started —
/// so pausing and speaking again never overwrites earlier words.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var finalizedText = ""      // utterances already committed this session
    private var liveText = ""           // current, not-yet-committed utterance
    private var segmentID = 0           // ignore callbacks from superseded segments
    private var silenceWork: DispatchWorkItem?
    /// Commit the current utterance after this much silence (no new partials).
    private let silenceInterval: TimeInterval = 1.3

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
        task?.cancel()
        task = nil
        finalizedText = ""
        liveText = ""
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Feed audio to whichever request is current (they're recreated per
        // utterance), so reference `self.request`, not a captured one.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        beginSegment()
    }

    /// Start a recognition task on the already-running audio engine.
    private func beginSegment() {
        segmentID += 1
        let id = segmentID
        liveText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                // Ignore late callbacks from a segment we've already moved past.
                guard let self, self.isRecording, id == self.segmentID else { return }
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    self.transcript = self.combined(self.liveText)
                    self.scheduleSilenceCommit()
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.commitAndRestart()
                }
            }
        }
    }

    /// After a short silence (a pause), commit the current utterance and start a
    /// fresh request — so the next utterance builds on it instead of replacing it.
    private func scheduleSilenceCommit() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording, !self.liveText.isEmpty else { return }
            self.commitAndRestart()
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceInterval, execute: work)
    }

    private func commitAndRestart() {
        silenceWork?.cancel()
        finalizedText = combined(liveText)
        liveText = ""
        transcript = finalizedText

        // Tear down the current recognition and start a new one on the still-
        // running audio engine.
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if isRecording { beginSegment() }
    }

    /// Finalized text + the current live utterance.
    private func combined(_ partial: String) -> String {
        if finalizedText.isEmpty { return partial }
        if partial.isEmpty { return finalizedText }
        return finalizedText + " " + partial
    }

    /// Stop capture (user tapped Stop/Done). The accumulated `transcript` is what
    /// gets sent to the backend via `EnhaleAPIClient.parseMeal`.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false     // set first so in-flight callbacks won't restart
        segmentID += 1          // invalidate any pending callbacks
        silenceWork?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
