import Foundation

/// Runs a shortcut from the Shortcuts app via the `shortcuts` CLI.
enum ShortcutRunner {
    static func run(name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    NSLog("MeetingScribe: shortcut “%@” failed (%d): %@", name, process.terminationStatus, err)
                }
            }
        } catch {
            NSLog("MeetingScribe: could not launch shortcuts CLI: %@", error.localizedDescription)
        }
    }

    /// Names of all shortcuts in the Shortcuts app (for the config helper menu).
    static func list() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.split(separator: "\n").map(String.init)
    }
}
