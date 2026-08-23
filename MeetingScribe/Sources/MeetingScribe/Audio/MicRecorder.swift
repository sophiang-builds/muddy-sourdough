import Foundation
import AVFoundation

/// Records the built-in / selected microphone (i.e. *you*) to a WAV file.
/// Keeping the mic on its own track is what lets the transcript label your
/// speech "Me" without any voice recognition.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func start(writingTo url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "MeetingScribe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No microphone input available"
            ])
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let audioFile = try AVAudioFile(forWriting: url, settings: settings,
                                        commonFormat: format.commonFormat,
                                        interleaved: format.isInterleaved)
        file = audioFile

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            default:
                continuation.resume(returning: false)
            }
        }
    }
}
