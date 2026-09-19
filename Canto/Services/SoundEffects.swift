import AppKit

/// Short interface sounds. Starting one can block for a few hundred milliseconds while the output
/// device wakes up (Bluetooth headphones especially), so they play on their own queue, not the main
/// thread that inserts the text.
enum SoundEffects {
    static func start() { play("Tink") }
    static func stop() { play("Pop") }
    static func failure() { play("Basso") }

    private static let queue = DispatchQueue(label: "io.github.jehkinen.canto.sounds", qos: .userInitiated)
    /// Loaded once and only touched on `queue`.
    nonisolated(unsafe) private static var sounds: [String: NSSound] = [:]

    private static func play(_ name: String) {
        queue.async {
            guard let sound = sounds[name] ?? (NSSound(named: NSSound.Name(name))?.copy() as? NSSound) else { return }
            sounds[name] = sound
            sound.volume = 0.35
            if sound.isPlaying { sound.stop() }
            sound.play()
        }
    }
}
