import Foundation
import AVFoundation
import WhisperKit
import FluidAudio
import OpenCC

/// One utterance in the merged transcript.
struct TranscriptLine: Identifiable {
    let id = UUID()
    let start: TimeInterval
    let end: TimeInterval
    /// "me" for the mic track, or a diarization speaker id like "S1".
    let speakerKey: String
    let text: String
}

struct Transcript {
    var lines: [TranscriptLine]
    /// Distinct speaker keys in order of first appearance ("me" first if present).
    var speakerKeys: [String] {
        var seen = [String]()
        if lines.contains(where: { $0.speakerKey == "me" }) { seen.append("me") }
        for line in lines where line.speakerKey != "me" && !seen.contains(line.speakerKey) {
            seen.append(line.speakerKey)
        }
        return seen
    }

    func sampleText(for key: String, maxLength: Int = 180) -> String {
        let texts = lines.filter { $0.speakerKey == key }.map(\.text)
        let joined = texts.prefix(3).joined(separator: " … ")
        return joined.count > maxLength ? String(joined.prefix(maxLength)) + "…" : joined
    }
}

/// Local, on-device pipeline:
///   1. WhisperKit (large-v3 family → real Cantonese "yue" support) transcribes
///      the mic track and the system track separately.
///   2. FluidAudio's offline diarizer splits the system track into speakers.
///   3. Whisper segments are matched to diarized speakers by time overlap and
///      merged with the mic track ("me") into one timeline.
struct TranscriptionPipeline {
    let config: Config

    func run(micURL: URL, systemURL: URL, progress: @escaping (String) -> Void) async throws -> Transcript {
        progress("Loading Whisper model (first run downloads it)…")
        let whisper = try await WhisperKit(WhisperKitConfig(model: config.whisperModel))

        var options = DecodingOptions()
        options.task = .transcribe
        if config.language != "auto" {
            options.language = config.language
            // Force the language token through the decoder prefill — without
            // this Whisper can still auto-detect and override the setting.
            options.usePrefillPrompt = true
        }
        // Whisper mimics the style of its context prompt. For Cantonese this
        // is the lever that pulls output toward colloquial 粵文 instead of
        // Standard Written Chinese (its subtitle-heavy training default).
        let promptText = config.initialPrompt
            ?? (config.language == "yue"
                ? "喂，早晨，我哋今日開會傾吓個project先。你哋聽唔聽到我講嘢呀？冇問題嘅話我哋開始啦。"
                : nil)
        if let promptText, let tokenizer = whisper.tokenizer {
            let tokens = tokenizer.encode(text: " " + promptText)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if !tokens.isEmpty { options.promptTokens = tokens }
        }
        NSLog("MeetingScribe: transcribing with model=%@ language=%@",
              config.whisperModel, config.language)

        progress("Transcribing your microphone track (\(config.language))…")
        let micSegments = try await transcribe(whisper, path: micURL.path, options: options)

        var systemSegments: [Segment] = []
        var turns: [SpeakerTurn] = []
        if Self.isEffectivelySilent(systemURL) {
            // Nothing played through the speakers (typical for an ad-hoc test).
            // Whisper hallucinates text like "Thank you." or URLs when fed
            // silence, so skip the track entirely.
            NSLog("MeetingScribe: system track is silent — skipping it")
        } else {
            progress("Separating speakers…")
            // nil = diarizer unavailable (still transcribe, single speaker);
            // []  = diarizer ran and found no remote speech (skip the track).
            let turnsResult = await diarize(systemURL)
            turns = turnsResult ?? []

            if turnsResult == nil || !turns.isEmpty {
                progress("Transcribing the meeting audio (\(config.language))…")
                systemSegments = try await transcribe(whisper, path: systemURL.path, options: options)
            }
            if !turns.isEmpty {
                // Drop Whisper segments that overlap no diarized speech at
                // all — hallucinations on silent or music-only stretches.
                systemSegments = systemSegments.filter { seg in
                    turns.contains { min(seg.end, $0.end) - max(seg.start, $0.start) > 0.2 }
                }
            }
        }

        var lines: [TranscriptLine] = []
        for seg in micSegments {
            lines.append(TranscriptLine(start: seg.start, end: seg.end, speakerKey: "me", text: seg.text))
        }
        var lastSpeaker = "S1"
        for seg in systemSegments {
            let speaker = dominantSpeaker(for: seg, in: turns) ?? lastSpeaker
            lastSpeaker = speaker
            lines.append(TranscriptLine(start: seg.start, end: seg.end, speakerKey: speaker, text: seg.text))
        }
        lines.sort { $0.start < $1.start }

        // Merge consecutive lines from the same speaker for readability.
        var merged: [TranscriptLine] = []
        for line in lines {
            if let last = merged.last, last.speakerKey == line.speakerKey, line.start - last.end < 2.0 {
                merged[merged.count - 1] = TranscriptLine(
                    start: last.start, end: line.end,
                    speakerKey: last.speakerKey,
                    text: last.text + " " + line.text
                )
            } else {
                merged.append(line)
            }
        }

        // Normalize any Simplified characters Whisper mixed in to Hong Kong-
        // standard Traditional. Deterministic, character-level — English and
        // already-Traditional text pass through unchanged.
        if config.traditionalChinese ?? true,
           let converter = try? ChineseConverter(options: [.traditionalize, .hkStandard]) {
            merged = merged.map {
                TranscriptLine(start: $0.start, end: $0.end,
                               speakerKey: $0.speakerKey,
                               text: converter.convert($0.text))
            }
        }
        return Transcript(lines: merged)
    }

    // MARK: - Silence detection

    /// True when the file's RMS level is below roughly -66 dBFS — i.e. no one
    /// ever actually played audio on this track.
    private static func isEffectivelySilent(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return true }
        let format = file.processingFormat
        let chunkFrames: AVAudioFrameCount = 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return false }

        var sumSquares: Double = 0
        var sampleCount: Double = 0
        while file.framePosition < file.length {
            guard (try? file.read(into: buffer, frameCount: chunkFrames)) != nil,
                  buffer.frameLength > 0,
                  let channel = buffer.floatChannelData?[0] else { break }
            for i in 0..<Int(buffer.frameLength) {
                let sample = Double(channel[i])
                sumSquares += sample * sample
            }
            sampleCount += Double(buffer.frameLength)
        }
        guard sampleCount > 0 else { return true }
        let rms = (sumSquares / sampleCount).squareRoot()
        NSLog("MeetingScribe: system track RMS = %f", rms)
        return rms < 0.0005
    }

    // MARK: - Whisper

    private struct Segment { let start: TimeInterval; let end: TimeInterval; let text: String }

    private func transcribe(_ whisper: WhisperKit, path: String, options: DecodingOptions) async throws -> [Segment] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let results = try await whisper.transcribe(audioPath: path, decodeOptions: options)
        var segments: [Segment] = []
        for result in results {
            for seg in result.segments {
                let text = seg.text
                    .replacingOccurrences(of: "<\\|[^>]*\\|>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(Segment(start: TimeInterval(seg.start), end: TimeInterval(seg.end), text: text))
            }
        }
        return segments
    }

    // MARK: - Diarization

    private struct SpeakerTurn { let speaker: String; let start: TimeInterval; let end: TimeInterval }

    /// nil = diarizer failed or file missing (caller should still transcribe,
    /// falling back to one speaker); [] = diarizer ran and found no speech.
    private func diarize(_ url: URL) async -> [SpeakerTurn]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
            try await manager.prepareModels()
            let result = try await manager.process(url)
            return result.segments.map {
                SpeakerTurn(speaker: "S\($0.speakerId)",
                            start: TimeInterval($0.startTimeSeconds),
                            end: TimeInterval($0.endTimeSeconds))
            }
        } catch {
            // Diarization failing shouldn't sink the whole transcript —
            // fall back to a single "S1" remote speaker.
            NSLog("MeetingScribe: diarization failed, using single speaker: %@", error.localizedDescription)
            return nil
        }
    }

    private func dominantSpeaker(for seg: Segment, in turns: [SpeakerTurn]) -> String? {
        guard !turns.isEmpty else { return "S1" }
        var overlapBySpeaker: [String: TimeInterval] = [:]
        for turn in turns {
            let overlap = min(seg.end, turn.end) - max(seg.start, turn.start)
            if overlap > 0 { overlapBySpeaker[turn.speaker, default: 0] += overlap }
        }
        return overlapBySpeaker.max { $0.value < $1.value }?.key
    }
}
