import AppKit

enum SoundEffects {
    static func start() { play("Tink") }
    static func stop() { play("Pop") }
    static func failure() { play("Basso") }

    private static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.35
        sound.play()
    }
}
