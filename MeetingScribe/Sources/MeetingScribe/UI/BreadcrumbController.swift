import AppKit
import SwiftUI

/// The "breadcrumb": a small floating panel in the top-right corner that
/// appears when a calendar meeting is about to start.
final class BreadcrumbController {
    private var panel: NSPanel?
    private let meeting: MeetingContext
    private let onStart: () -> Void
    private let onDismiss: () -> Void

    init(meeting: MeetingContext, onStart: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.meeting = meeting
        self.onStart = onStart
        self.onDismiss = onDismiss
    }

    func show() {
        let view = BreadcrumbView(
            meeting: meeting,
            onStart: { [weak self] in self?.close(); self?.onStart() },
            onDismiss: { [weak self] in self?.close(); self?.onDismiss() }
        )
        let panel = Self.makePanel(hosting: view, size: NSSize(width: 340, height: 150))
        self.panel = panel
        panel.orderFrontRegardless()

        // Auto-dismiss if ignored for 10 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
            guard let self, self.panel != nil else { return }
            self.close()
            self.onDismiss()
        }
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Shared panel plumbing

    fileprivate static func makePanel(hosting view: some View, size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - size.width - 16,
                y: frame.maxY - size.height - 16
            ))
        }
        return panel
    }

    /// Transient toast (e.g. "Saved to Apple Notes"), auto-dismisses.
    static func showToast(_ message: String, seconds: TimeInterval = 5) {
        DispatchQueue.main.async {
            let panel = makePanel(hosting: ToastView(message: message),
                                  size: NSSize(width: 340, height: 64))
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                panel.orderOut(nil)
            }
        }
    }
}

private struct BreadcrumbView: View {
    let meeting: MeetingContext
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(meeting.start, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !meeting.attendees.isEmpty {
                Text(meeting.attendees.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Button("Not now", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: onStart) {
                    Label("Start meeting", systemImage: "record.circle")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct ToastView: View {
    let message: String
    var body: some View {
        HStack {
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 340)
    }
}
