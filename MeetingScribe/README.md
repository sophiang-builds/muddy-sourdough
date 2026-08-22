# MeetingScribe

A macOS menu bar app that watches your Apple Calendar, pops a **"Start meeting?"**
breadcrumb when a meeting begins, opens the meeting via your **asynk** or
**cocoon** Shortcut (based on which email address the invite was sent to),
records the call, and produces a **fully local, speaker-labeled transcript in
Cantonese + English**, saved to **Apple Notes › Meetings**.

Nothing ever leaves your Mac: transcription is Whisper `large-v3` (the first
Whisper generation with real Cantonese support) running on the Neural
Engine/GPU via WhisperKit, and speaker separation is FluidAudio's on-device
diarizer.

## How it works

1. **Calendar watch** — polls Apple Calendar (EventKit); a couple of minutes
   before an event starts, a floating breadcrumb appears top-right with the
   meeting title, time, and attendees.
2. **Start meeting** — clicking the button:
   - looks up which of *your* addresses the invite was sent to and runs the
     matching Shortcut (`sophia@asynk.ai` → `asynk`, `sophia@hkcocoon.org` →
     `cocoon`) so the meeting opens auto-authenticated;
   - starts recording **two tracks**: your microphone (= you) and system
     audio via a Core Audio process tap (= everyone else). No BlackHole or
     other drivers needed on macOS 14.4+.
3. **Stop & transcribe** — from the menu bar icon when the meeting ends. Both
   tracks are transcribed by Whisper, the system track is split into speakers
   by the diarizer, and everything is merged into one timeline. Because your
   mic is its own track, your lines are labeled as you with 100% accuracy.
4. **Tag speakers** — a window lists each detected voice with a sample quote
   and one-click buttons for the invite's attendee names.
5. **Save** — the transcript (title, date, "On the call" list, speaker-labeled
   lines with timestamps) is created in Apple Notes in the folder from your
   config, plus a markdown backup in
   `~/Library/Application Support/MeetingScribe/transcripts/`.

## Build & install (on your Mac)

Requires macOS 14.4+ (you're on macOS 26 — perfect) and Xcode or the Xcode
Command Line Tools.

```bash
cd MeetingScribe
chmod +x build.sh
./build.sh
open dist/MeetingScribe.app
```

Add `dist/MeetingScribe.app` to **System Settings ▸ General ▸ Login Items** so
it's always running.

### First-run permission dance

macOS will prompt for each of these the first time the relevant feature runs —
approve them all:

| Prompt | When it appears | Why |
|---|---|---|
| **Calendars** (Full Access) | at launch | to see upcoming meetings & attendees |
| **Microphone** | at launch / first recording | your own audio track |
| **System Audio Recording** (under Privacy ▸ Screen & System Audio Recording) | first recording | the other participants' audio |
| **Automation → Notes** | first transcript save | creating the note |

The **first transcription** downloads the Whisper model (~1 GB) and the
diarization models (~100 MB) from Hugging Face, then everything runs offline.
Expect roughly 1–3 minutes of processing per 30 minutes of meeting on Apple
Silicon.

## Configuration

`~/Library/Application Support/MeetingScribe/config.json`
(menu bar ▸ *Edit configuration…*):

```json
{
  "emailShortcutMap": {
    "sophia@asynk.ai": "asynk",
    "sophia@hkcocoon.org": "cocoon"
  },
  "notesFolderName": "Meetings",
  "language": "auto",
  "whisperModel": "large-v3-v20240930_turbo",
  "leadMinutes": 2,
  "keepAudioFiles": false,
  "myName": ""
}
```

- `language`: `"auto"` detects Cantonese/English per 30-second window (best
  for code-switching meetings). Force `"yue"` if English loanwords keep coming
  out romanized, or `"en"` for English-only calls.
- If a meeting's invite address isn't in `emailShortcutMap`, recording still
  starts — the app just doesn't run a Shortcut. Use menu bar ▸ *Show my
  calendar addresses* to see exactly which addresses EventKit reports for
  your accounts, and paste them into the map.
- `whisperModel`: switch to `"large-v3-v20240930_626MB"` for a smaller
  download at some accuracy cost.

## Tips for best results

- **Wear headphones.** Then your mic track contains only your voice and the
  system track only theirs, so speaker separation is essentially perfect. On
  speakers, the mic also hears the remote side and you may see duplicated
  lines.
- Diarization guesses *how many* remote voices there are; the tagging window
  is where you turn "Voice S1/S2" into real names. For a 1:1 call the app
  pre-fills the other person's name from the invite automatically.
- Recordings are audio only — no video, no screen contents.

## Troubleshooting

- **Breadcrumb never appears** → System Settings ▸ Privacy & Security ▸
  Calendars: MeetingScribe must have *Full Access*. All-day events are
  ignored by design.
- **"Recording failed"** → check both Microphone and Screen & System Audio
  Recording permissions, then quit & relaunch the app (macOS only re-checks
  audio-tap permission at process start).
- **Shortcut didn't run** → run `shortcuts run asynk` in Terminal yourself;
  if that fails, the shortcut name doesn't match. `shortcuts list` shows the
  exact names.
- **Notes export failed** → System Settings ▸ Privacy & Security ▸
  Automation: allow MeetingScribe to control Notes. The markdown backup is
  always written regardless.
- **Build errors mentioning WhisperKit or FluidAudio** → both libraries are
  young and their APIs move. Pin/adjust in `Package.swift`; the integration
  points are deliberately isolated in
  `Sources/MeetingScribe/Transcription/TranscriptionPipeline.swift` (the
  `transcribe` and `diarize` functions are the only places that touch each
  library).
