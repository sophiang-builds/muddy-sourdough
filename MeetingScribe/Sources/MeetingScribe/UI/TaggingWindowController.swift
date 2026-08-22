import AppKit
import SwiftUI

/// Post-meeting window: assign each detected voice to an attendee name,
/// preview the transcript, then save to Apple Notes.
final class TaggingWindowController {
    private var window: NSWindow?
    private let meeting: MeetingContext
    private let transcript: Transcript
    private let config: Config
    private let onDone: (FinalTranscript) -> Void
    private let onCancel: () -> Void

    init(meeting: MeetingContext, transcript: Transcript, config: Config,
         onDone: @escaping (FinalTranscript) -> Void,
         onCancel: @escaping () -> Void) {
        self.meeting = meeting
        self.transcript = transcript
        self.config = config
        self.onDone = onDone
        self.onCancel = onCancel
    }

    func show() {
        let view = TaggingView(
            meeting: meeting,
            transcript: transcript,
            myName: config.resolvedMyName,
            onSave: { [weak self] names in
                guard let self else { return }
                let final = FinalTranscript.build(meeting: self.meeting,
                                                  transcript: self.transcript,
                                                  speakerNames: names)
                self.close()
                self.onDone(final)
            },
            onCancel: { [weak self] in
                self?.close()
                self?.onCancel()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Tag speakers — \(meeting.title)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct TaggingView: View {
    let meeting: MeetingContext
    let transcript: Transcript
    let myName: String
    let onSave: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var names: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section("Who is who?") {
                    ForEach(transcript.speakerKeys, id: \.self) { key in
                        speakerRow(key)
                    }
                }
                Section("Preview") {
                    ForEach(transcript.lines.prefix(30)) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(displayName(line.speakerKey) + ":")
                                .bold()
                                .frame(minWidth: 70, alignment: .trailing)
                            Text(line.text)
                        }
                        .font(.callout)
                    }
                    if transcript.lines.count > 30 {
                        Text("… \(transcript.lines.count - 30) more lines")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Button("Discard", role: .destructive, action: onCancel)
                Spacer()
                Button("Save to Apple Notes") { onSave(names) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 500)
        .onAppear { prefill() }
    }

    private func prefill() {
        var initial: [String: String] = ["me": myName]
        // If the invite has exactly one non-me attendee and we detected exactly
        // one remote voice, pre-assign it.
        let others = meeting.attendees.filter { !$0.isMe }
        let remoteKeys = transcript.speakerKeys.filter { $0 != "me" }
        if others.count == 1, remoteKeys.count == 1 {
            initial[remoteKeys[0]] = others[0].name
        }
        names = initial
    }

    private func displayName(_ key: String) -> String {
        let n = names[key]?.trimmingCharacters(in: .whitespaces) ?? ""
        if !n.isEmpty { return n }
        return key == "me" ? "Me" : key
    }

    @ViewBuilder
    private func speakerRow(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key == "me" ? "Your mic" : "Voice \(key)")
                    .font(.headline)
                TextField("Name", text: Binding(
                    get: { names[key] ?? "" },
                    set: { names[key] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            }
            if key != "me" {
                let sample = transcript.sampleText(for: key)
                if !sample.isEmpty {
                    Text("“\(sample)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !meeting.attendees.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(meeting.attendees.filter { !$0.isMe }) { attendee in
                            Button(attendee.name) { names[key] = attendee.name }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
