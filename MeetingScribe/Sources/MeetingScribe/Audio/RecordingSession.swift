import Foundation

/// Owns one meeting's pair of recordings: mic (you) + system audio (everyone else).
final class RecordingSession {
    let micFileURL: URL
    let systemFileURL: URL

    private let mic = MicRecorder()
    private let system = SystemAudioRecorder()
    private(set) var startedAt: Date?

    init(meetingID: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = Config.recordingsDirectory
        micFileURL = dir.appendingPathComponent("\(stamp)-mic.wav")
        systemFileURL = dir.appendingPathComponent("\(stamp)-system.wav")
    }

    func start() throws {
        try system.start(writingTo: systemFileURL)
        do {
            try mic.start(writingTo: micFileURL)
        } catch {
            system.stop()
            throw error
        }
        startedAt = Date()
    }

    func stop() {
        mic.stop()
        system.stop()
    }

    func deleteFiles() {
        try? FileManager.default.removeItem(at: micFileURL)
        try? FileManager.default.removeItem(at: systemFileURL)
    }
}
