import Foundation
import EventKit

/// Polls Apple Calendar (EventKit) and fires `onMeetingImminent` once per event
/// when its start time enters the lead window.
final class CalendarWatcher {
    private let store = EKEventStore()
    private var timer: Timer?
    private var promptedIDs = Set<String>()
    private var leadMinutes = 2

    var onMeetingImminent: ((MeetingContext) -> Void)?
    private(set) var accessGranted = false

    func start(leadMinutes: Int) {
        self.leadMinutes = max(0, leadMinutes)
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard let self else { return }
            self.accessGranted = granted
            guard granted else {
                NSLog("MeetingScribe: Calendar access denied — enable it in System Settings ▸ Privacy & Security ▸ Calendars")
                return
            }
            DispatchQueue.main.async {
                self.timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                    self.poll()
                }
                self.timer?.tolerance = 5
                self.poll()
            }
        }
    }

    /// Email addresses of the calendar accounts EventKit can see — surfaced in
    /// the menu so filling in the email→shortcut config is easy.
    func knownSelfAddresses() -> [String] {
        guard accessGranted else { return [] }
        // EventKit doesn't expose account emails directly; collect the
        // "isCurrentUser" participant addresses from recent + upcoming events.
        let cal = Calendar.current
        let predicate = store.predicateForEvents(
            withStart: cal.date(byAdding: .day, value: -14, to: Date())!,
            end: cal.date(byAdding: .day, value: 14, to: Date())!,
            calendars: nil
        )
        var addresses = Set<String>()
        for event in store.events(matching: predicate) {
            for participant in event.attendees ?? [] where participant.isCurrentUser {
                if let email = Self.email(from: participant) { addresses.insert(email) }
            }
        }
        return addresses.sorted()
    }

    private func poll() {
        let now = Date()
        // Look slightly into the past so a meeting isn't missed if the Mac was asleep.
        let windowStart = now.addingTimeInterval(-5 * 60)
        let windowEnd = now.addingTimeInterval(Double(leadMinutes) * 60)
        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)

        for event in store.events(matching: predicate) {
            guard !event.isAllDay else { continue }
            // Skip events that already ended.
            if let end = event.endDate, end < now { continue }
            let key = (event.eventIdentifier ?? event.title ?? "?") + "@" + String(event.startDate.timeIntervalSince1970)
            guard !promptedIDs.contains(key) else { continue }
            promptedIDs.insert(key)
            onMeetingImminent?(Self.context(for: event, id: key))
        }

        // Keep the prompted set from growing forever.
        if promptedIDs.count > 200 { promptedIDs.removeAll() }
    }

    private static func context(for event: EKEvent, id: String) -> MeetingContext {
        var attendees: [MeetingContext.Attendee] = []
        var selfEmail: String?

        for participant in event.attendees ?? [] {
            let email = email(from: participant)
            let name = participant.name ?? email ?? "Unknown"
            if participant.isCurrentUser {
                selfEmail = email
            }
            attendees.append(.init(name: name, email: email, isMe: participant.isCurrentUser))
        }

        return MeetingContext(
            id: id,
            title: event.title ?? "Untitled meeting",
            start: event.startDate,
            end: event.endDate,
            attendees: attendees,
            selfEmail: selfEmail
        )
    }

    private static func email(from participant: EKParticipant) -> String? {
        let raw = participant.url.absoluteString
        guard raw.lowercased().hasPrefix("mailto:") else { return nil }
        return String(raw.dropFirst("mailto:".count)).removingPercentEncoding?.lowercased()
    }
}
