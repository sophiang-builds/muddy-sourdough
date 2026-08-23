import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio

/// Captures everything the Mac plays (Zoom/Meet/Teams — i.e. the *other*
/// participants) using a Core Audio process tap (macOS 14.2+, no drivers).
///
/// Mechanics: create a global process tap, wrap it in a private aggregate
/// device alongside the default output device, then read the tap's stream
/// with an IO proc and write it to a WAV file.
final class SystemAudioRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var tapFormat: AVAudioFormat?
    private let queue = DispatchQueue(label: "meetingscribe.system-tap")

    func start(writingTo url: URL) throws {
        // 1. Global tap over all processes' output.
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.name = "MeetingScribe system tap"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(tapDescription, &newTapID), "creating system audio tap (grant Screen & System Audio Recording permission?)")
        tapID = newTapID

        // 2. Ask the tap what format it delivers.
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd), "reading tap format")
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw NSError(domain: "MeetingScribe", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported tap audio format"])
        }
        tapFormat = format

        // 3. WAV file matching the tap format.
        file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: format.commonFormat,
                               interleaved: format.isInterleaved)

        // 4. Private aggregate device: default output + our tap.
        let outputUID = try defaultOutputDeviceUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "MeetingScribe Capture",
            kAudioAggregateDeviceUIDKey as String: "com.meetingscribe.capture." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: tapDescription.uuid.uuidString,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID),
                  "creating aggregate capture device")
        aggregateID = newAggregateID

        // 5. Pump tap buffers into the file.
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inInputData, _, _, _ in
            guard let self, let file = self.file, let format = self.tapFormat else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                bufferListNoCopy: inInputData,
                                                deallocator: nil) else { return }
            try? file.write(from: buffer)
        }, "installing audio IO proc")
        ioProcID = procID
        try check(AudioDeviceStart(aggregateID, procID), "starting audio capture")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let procID = ioProcID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        ioProcID = nil
        file = nil
    }

    // MARK: - Helpers

    private func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID),
                  "finding default output device")

        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        try check(withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }, "reading output device UID")
        return uid as String
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Error \(status) while \(what)"
            ])
        }
    }
}
