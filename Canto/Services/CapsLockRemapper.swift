import Foundation
import CantoCore

/// Applies and removes the Caps Lock → F18 remapping with `/usr/bin/hidutil`.
enum CapsLockRemapper {
    private static var applied = false
    /// Where the user's own Caps Lock remap pointed before Canto replaced it, kept across launches.
    private static let previousDestinationKey = "capsLockMappingBeforeCanto"

    static func setEnabled(_ enabled: Bool) throws {
        let current = KeyRemapping.parse(try hidutil(["property", "--get", "UserKeyMapping"]))
        let defaults = UserDefaults.standard
        if enabled, let own = KeyRemapping.userCapsLockMapping(in: current) {
            defaults.set(String(own.destination), forKey: previousDestinationKey)
        }
        let previous = defaults.string(forKey: previousDestinationKey).flatMap(UInt64.init)
            .map { KeyRemapping.Mapping(source: KeyRemapping.capsLock, destination: $0) }
        let updated = KeyRemapping.applying(capsLockToF18: enabled, to: current, restoring: previous)
        if updated != current {
            _ = try hidutil(["property", "--set", KeyRemapping.setPayload(updated)])
        }
        if !enabled { defaults.removeObject(forKey: previousDestinationKey) }
        applied = enabled
    }

    /// Undo this session's remapping so Caps Lock works normally without Canto.
    static func restoreOnQuit() {
        guard applied else { return }
        try? setEnabled(false)
    }

    private static func hidutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "hidutil \(arguments.first ?? "") failed"])
        }
        return String(decoding: data, as: UTF8.self)
    }
}
