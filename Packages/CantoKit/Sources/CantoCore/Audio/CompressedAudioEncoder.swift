import AVFoundation

/// AAC in an M4A container for uploads: about a tenth of the size of 16-bit WAV.
public enum CompressedAudioEncoder {
    public static func m4a(_ segment: AudioSegment, bitRate: Int = 32_000) -> Data? {
        guard !segment.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioSegment.sampleRate),
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(segment.samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(segment.samples.count)
        segment.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("canto-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard write(buffer, to: url, bitRate: bitRate) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The file is finalized when `AVAudioFile` is released, which happens when this returns.
    private static func write(_ buffer: AVAudioPCMBuffer, to url: URL, bitRate: Int) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioSegment.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }
}
