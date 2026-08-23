import Foundation

/// Saves a transcript into Apple Notes via osascript. The script is written to
/// a temp file and the title/body are passed as argv, so note content never
/// needs AppleScript string escaping.
enum NotesExporter {
    private static let script = """
    on run argv
        set noteTitle to item 1 of argv
        set noteBody to item 2 of argv
        set folderName to item 3 of argv
        tell application "Notes"
            set targetAccount to default account
            if not (exists folder folderName of targetAccount) then
                make new folder at targetAccount with properties {name:folderName}
            end if
            make new note at folder folderName of targetAccount with properties {name:noteTitle, body:noteBody}
        end tell
    end run
    """

    static func export(title: String, htmlBody: String, folderName: String) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetingscribe-notes.applescript")
        try script.data(using: .utf8)!.write(to: scriptURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptURL.path, title, htmlBody, folderName]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "MeetingScribe", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: err.isEmpty ? "osascript failed" : err
            ])
        }
    }
}
