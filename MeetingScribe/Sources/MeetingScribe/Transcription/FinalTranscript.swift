import Foundation

/// The finished, name-tagged transcript in the formats we export.
struct FinalTranscript {
    let noteTitle: String
    let markdown: String
    let html: String
    let suggestedFileName: String

    static func build(meeting: MeetingContext,
                      transcript: Transcript,
                      speakerNames: [String: String]) -> FinalTranscript {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let dateString = df.string(from: meeting.start)
        let title = "\(meeting.title) — \(dateString)"

        func name(for key: String) -> String {
            let n = speakerNames[key]?.trimmingCharacters(in: .whitespaces) ?? ""
            if !n.isEmpty { return n }
            return key == "me" ? "Me" : key
        }

        func timestamp(_ t: TimeInterval) -> String {
            let s = Int(t)
            return String(format: "%02d:%02d", s / 60, s % 60)
        }

        // Markdown
        var md = "# \(title)\n\n"
        if !meeting.attendees.isEmpty {
            md += "**On the call:** " + meeting.attendees.map {
                $0.email != nil ? "\($0.name) <\($0.email!)>" : $0.name
            }.joined(separator: ", ") + "\n\n"
        }
        md += "---\n\n"
        for line in transcript.lines {
            md += "**\(name(for: line.speakerKey))** [\(timestamp(line.start))]: \(line.text)\n\n"
        }

        // HTML (Apple Notes body)
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        var html = "<h1>\(esc(title))</h1>"
        if !meeting.attendees.isEmpty {
            let list = meeting.attendees.map { esc($0.name) }.joined(separator: ", ")
            html += "<div><b>On the call:</b> \(list)</div><div><br></div>"
        }
        for line in transcript.lines {
            html += "<div><b>\(esc(name(for: line.speakerKey)))</b> [\(timestamp(line.start))]: \(esc(line.text))</div>"
        }

        let fileStamp = ISO8601DateFormatter().string(from: meeting.start)
            .replacingOccurrences(of: ":", with: "-")
        let safeTitle = meeting.title
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")

        return FinalTranscript(
            noteTitle: title,
            markdown: md,
            html: html,
            suggestedFileName: "\(fileStamp)-\(safeTitle)"
        )
    }
}
