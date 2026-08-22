import Foundation

/// User-editable configuration, stored as JSON at
/// ~/Library/Application Support/MeetingScribe/config.json
struct Config: Codable {
    /// Maps the email address a calendar invite was sent to → the Shortcuts-app
    /// shortcut to run when the meeting starts.
    var emailShortcutMap: [String: String]

    /// Apple Notes folder that finished transcripts are saved into.
    var notesFolderName: String

    /// "auto" (per-window language detection), "yue" (force Cantonese), or "en".
    /// HK meetings that code-switch mid-sentence usually do best on "auto";
    /// if English words keep getting romanized try "yue".
    var language: String

    /// WhisperKit model variant. large-v3 generation is required for Cantonese.
    /// "large-v3-v20240930_turbo" is the fastest on Apple Silicon;
    /// "large-v3-v20240930_626MB" is smaller if disk is tight.
    var whisperModel: String

    /// Show the "Start meeting?" breadcrumb this many minutes before the event.
    var leadMinutes: Int

    /// Keep the raw .wav recordings after a transcript is produced.
    var keepAudioFiles: Bool

    /// Name used for your own (microphone) speech in transcripts.
    /// Empty = use your macOS account full name.
    var myName: String

    /// Optional text used to seed Whisper's context before decoding.
    /// Whisper mimics the style of this prompt — for Cantonese, a colloquial
    /// 口語 sentence here biases output toward written Cantonese (唔/嘅/嘢)
    /// instead of Standard Written Chinese. When unset and language is "yue",
    /// a built-in colloquial seed is used automatically.
    /// (Optional so configs saved by older versions still load.)
    var initialPrompt: String?

    static let `default` = Config(
        emailShortcutMap: [
            "sophia@asynk.ai": "asynk",
            "sophia@hkcocoon.org": "cocoon",
        ],
        notesFolderName: "Meetings",
        language: "auto",
        whisperModel: "large-v3-v20240930_turbo",
        leadMinutes: 2,
        keepAudioFiles: false,
        myName: "",
        initialPrompt: nil
    )

    var resolvedMyName: String {
        myName.isEmpty ? NSFullUserName() : myName
    }

    // MARK: - Persistence

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MeetingScribe", isDirectory: true)
    }

    static var configURL: URL { supportDirectory.appendingPathComponent("config.json") }
    static var recordingsDirectory: URL { supportDirectory.appendingPathComponent("recordings", isDirectory: true) }
    static var transcriptsDirectory: URL { supportDirectory.appendingPathComponent("transcripts", isDirectory: true) }

    static func load() -> Config {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: configURL),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let cfg = Config.default
        cfg.save()
        return cfg
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Config.configURL)
        }
    }

    /// Case-insensitive lookup of the shortcut for an email address.
    func shortcut(forEmail email: String?) -> String? {
        guard let email else { return nil }
        let needle = email.lowercased().trimmingCharacters(in: .whitespaces)
        return emailShortcutMap.first { $0.key.lowercased() == needle }?.value
    }
}
