import Foundation
import SwiftUI

/// A meeting pulled from Apple Calendar (or an ad-hoc recording).
struct MeetingContext: Identifiable {
    struct Attendee: Identifiable, Hashable {
        var id: String { email ?? name }
        let name: String
        let email: String?
        let isMe: Bool
    }

    let id: String            // eventIdentifier + start, or a UUID for ad-hoc
    let title: String
    let start: Date
    let end: Date?
    let attendees: [Attendee]
    /// The address (of mine) the invite was sent to, if EventKit could tell.
    let selfEmail: String?

    static func adHoc() -> MeetingContext {
        MeetingContext(
            id: UUID().uuidString,
            title: "Ad-hoc meeting \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            start: Date(), end: nil, attendees: [], selfEmail: nil
        )
    }
}

enum AppPhase {
    case idle
    case prompting(MeetingContext)
    case recording(MeetingContext)
    case processing(MeetingContext)
    case tagging(MeetingContext)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: AppPhase = .idle
    @Published var config = Config.load()
    @Published var statusDetail: String = ""     // shown in the menu while processing
    @Published var lastError: String?

    let calendarWatcher = CalendarWatcher()
    private var recorder: RecordingSession?
    private var breadcrumb: BreadcrumbController?
    private var taggingWindow: TaggingWindowController?

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    func start() {
        calendarWatcher.onMeetingImminent = { [weak self] meeting in
            Task { @MainActor in self?.showBreadcrumb(for: meeting) }
        }
        calendarWatcher.start(leadMinutes: config.leadMinutes)
    }

    // MARK: - Breadcrumb

    func showBreadcrumb(for meeting: MeetingContext) {
        guard case .idle = phase else { return }   // never interrupt an active recording
        phase = .prompting(meeting)
        breadcrumb = BreadcrumbController(
            meeting: meeting,
            onStart: { [weak self] in self?.startMeeting(meeting) },
            onDismiss: { [weak self] in
                self?.breadcrumb = nil
                self?.phase = .idle
            }
        )
        breadcrumb?.show()
    }

    // MARK: - Meeting lifecycle

    func startMeeting(_ meeting: MeetingContext) {
        breadcrumb = nil
        lastError = nil

        // 1. Open the meeting via the right Shortcut for the invited address.
        if let name = resolveShortcut(for: meeting) {
            statusDetail = "Running shortcut “\(name)”…"
            ShortcutRunner.run(name: name)
        }

        // 2. Start capturing mic + system audio.
        let session = RecordingSession(meetingID: meeting.id)
        do {
            try session.start()
            recorder = session
            phase = .recording(meeting)
            statusDetail = "Recording “\(meeting.title)”"
        } catch {
            lastError = "Could not start recording: \(error.localizedDescription)"
            phase = .idle
            BreadcrumbController.showToast("⚠️ Recording failed — check mic & screen/audio permissions")
        }
    }

    func startAdHoc() {
        guard case .idle = phase else { return }
        startMeeting(.adHoc())
    }

    func stopAndTranscribe() {
        guard case .recording(let meeting) = phase, let session = recorder else { return }
        session.stop()
        recorder = nil
        phase = .processing(meeting)
        statusDetail = "Loading Whisper model…"

        let cfg = config
        Task.detached(priority: .userInitiated) {
            do {
                let pipeline = TranscriptionPipeline(config: cfg)
                let transcript = try await pipeline.run(
                    micURL: session.micFileURL,
                    systemURL: session.systemFileURL,
                    progress: { detail in
                        Task { @MainActor in AppState.shared.statusDetail = detail }
                    }
                )
                await MainActor.run {
                    AppState.shared.openTagging(meeting: meeting, transcript: transcript, session: session)
                }
            } catch {
                await MainActor.run {
                    AppState.shared.lastError = "Transcription failed: \(error.localizedDescription)"
                    AppState.shared.phase = .idle
                    BreadcrumbController.showToast("⚠️ Transcription failed — see menu for details")
                }
            }
        }
    }

    func cancelRecording() {
        recorder?.stop()
        recorder?.deleteFiles()
        recorder = nil
        phase = .idle
        statusDetail = ""
    }

    // MARK: - Tagging & export

    private func openTagging(meeting: MeetingContext, transcript: Transcript, session: RecordingSession) {
        phase = .tagging(meeting)
        statusDetail = "Waiting for speaker names…"
        taggingWindow = TaggingWindowController(
            meeting: meeting,
            transcript: transcript,
            config: config,
            onDone: { [weak self] finalTranscript in
                self?.finish(meeting: meeting, text: finalTranscript, session: session)
            },
            onCancel: { [weak self] in
                self?.taggingWindow = nil
                self?.phase = .idle
                self?.statusDetail = ""
            }
        )
        taggingWindow?.show()
    }

    private func finish(meeting: MeetingContext, text: FinalTranscript, session: RecordingSession) {
        taggingWindow = nil

        // Markdown backup first — cheap insurance if the Notes export fails.
        let mdURL = Config.transcriptsDirectory
            .appendingPathComponent(text.suggestedFileName + ".md")
        try? text.markdown.data(using: .utf8)?.write(to: mdURL)

        do {
            try NotesExporter.export(
                title: text.noteTitle,
                htmlBody: text.html,
                folderName: config.notesFolderName
            )
            BreadcrumbController.showToast("✅ Transcript saved to Apple Notes › \(config.notesFolderName)")
        } catch {
            lastError = "Apple Notes export failed: \(error.localizedDescription). A markdown copy is at \(mdURL.path)"
            BreadcrumbController.showToast("⚠️ Notes export failed — markdown copy kept")
        }

        if !config.keepAudioFiles { session.deleteFiles() }
        phase = .idle
        statusDetail = ""
    }

    // MARK: - Helpers

    /// Which shortcut to run: prefer the address the invite was sent to (me),
    /// otherwise any attendee address that appears in the config map.
    private func resolveShortcut(for meeting: MeetingContext) -> String? {
        if let name = config.shortcut(forEmail: meeting.selfEmail) { return name }
        for attendee in meeting.attendees {
            if let name = config.shortcut(forEmail: attendee.email) { return name }
        }
        return nil
    }
}
