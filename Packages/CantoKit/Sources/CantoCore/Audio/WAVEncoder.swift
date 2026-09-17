import Foundation

/// 16-bit PCM mono WAV, the upload format for OpenAI transcription.
public enum WAVEncoder {
    public static func encode(_ segment: AudioSegment) -> Data {
        let sampleRate = UInt32(AudioSegment.sampleRate)
        let dataSize = UInt32(segment.samples.count * 2)
        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))        // fmt chunk size
        data.appendLittleEndian(UInt16(1))         // PCM
        data.appendLittleEndian(UInt16(1))         // mono
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(sampleRate * 2)    // byte rate
        data.appendLittleEndian(UInt16(2))         // block align
        data.appendLittleEndian(UInt16(16))        // bits per sample
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(dataSize)
        for sample in segment.samples {
            data.appendLittleEndian(UInt16(bitPattern: Int16(sample.clamped(to: -1...1) * Float(Int16.max))))
        }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
