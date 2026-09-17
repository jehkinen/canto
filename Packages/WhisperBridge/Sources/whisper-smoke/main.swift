import Foundation
import LocalWhisper
import CantoCore

/// Reads 16-bit PCM mono WAV data, walking the RIFF chunks (afconvert adds extra ones).
func readWAV(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    var offset = 12
    while offset + 8 <= data.count {
        let id = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let size = Int(data[offset + 4..<offset + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        if id == "data" {
            return data[offset + 8..<min(offset + 8 + size, data.count)].withUnsafeBytes { raw in
                raw.bindMemory(to: Int16.self).map { Float($0) / Float(Int16.max) }
            }
        }
        offset += 8 + size + (size & 1)
    }
    throw CocoaError(.fileReadCorruptFile)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: whisper-smoke <model.bin> <16k-mono.wav> [language] [gpu|cpu]")
    exit(2)
}
let language = arguments.count > 3 && arguments[3] != "auto" ? arguments[3] : nil
let useGPU = arguments.count > 4 ? arguments[4] == "gpu" : true
let samples = try readWAV(URL(fileURLWithPath: arguments[2]))
let segment = AudioPreprocessor.process(AudioSegment(samples: samples), enabled: true).segment
print(String(format: "audio: %.2f s, gpu: %@", segment.duration, useGPU ? "on" : "off"))

let transcriber = WhisperTranscriber(configuration: .init(modelURL: URL(fileURLWithPath: arguments[1]), useGPU: useGPU, beamSize: 1))
var clock = Date()
try await transcriber.prepare()
print(String(format: "model loaded in %.2f s", Date().timeIntervalSince(clock)))
clock = Date()
// CANTO_VOCAB="Node.js, PHP" overrides the default vocabulary; "noprompt" as the 5th argument disables it.
let usePrompt = arguments.count <= 5 || arguments[5] != "noprompt"
let terms = ProcessInfo.processInfo.environment["CANTO_VOCAB"].map { $0.split(separator: ",").map(String.init) } ?? AppSettings().vocabulary
let promptText = ProcessInfo.processInfo.environment["CANTO_PROMPT"] ?? Vocabulary.prompt(for: terms)
let raw = try await transcriber.transcribe(segment, language: language, prompt: usePrompt ? promptText : nil)
print(String(format: "transcribed in %.2f s", Date().timeIntervalSince(clock)))
print("raw:       \(raw)")

var settings = AppSettings()
settings.language = language
settings.vocabulary = usePrompt ? terms : []
let store = StyleStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("canto-smoke-styles"))
let processed = await TextPipeline(chat: nil, styles: store).process(raw, settings: settings, fallbackLanguage: "en")
print("processed: \(processed.text)")
