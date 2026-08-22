import SwiftUI
import AppKit

@main
struct MeetingScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(AppState.shared)
        } label: {
            MenuBarLabel()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only (also set via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            _ = await MicRecorder.requestPermission()
            AppState.shared.start()
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        if state.isRecording {
            Image(systemName: "record.circle.fill")
        } else if case .processing = state.phase {
            Image(systemName: "waveform.circle")
        } else {
            Image(systemName: "text.bubble")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        switch state.phase {
        case .idle:
            Text("Waiting for your next meeting…")
            Button("Start ad-hoc recording") { state.startAdHoc() }
        case .prompting(let meeting):
            Text("Meeting soon: \(meeting.title)")
            Button("Start meeting now") { state.startMeeting(meeting) }
        case .recording(let meeting):
            Text("● Recording: \(meeting.title)")
            Button("Stop & transcribe") { state.stopAndTranscribe() }
            Button("Cancel (discard recording)") { state.cancelRecording() }
        case .processing:
            Text("Transcribing… \(state.statusDetail)")
        case .tagging:
            Text("Transcript ready — tag speakers in the open window")
        }

        if let error = state.lastError {
            Divider()
            Text("⚠️ \(error)")
        }

        Divider()
        Button("Edit configuration…") {
            NSWorkspace.shared.open(Config.configURL)
        }
        Button("Open transcripts folder") {
            NSWorkspace.shared.open(Config.transcriptsDirectory)
        }
        Button("Show my calendar addresses") {
            let addresses = state.calendarWatcher.knownSelfAddresses()
            let msg = addresses.isEmpty
                ? "No invite addresses found in ±14 days of events (or Calendar access is off)."
                : "Invite addresses seen on your events:\n" + addresses.joined(separator: "\n")
            BreadcrumbController.showToast(msg, seconds: 10)
        }
        Divider()
        Button("Quit MeetingScribe") { NSApp.terminate(nil) }
    }
}
