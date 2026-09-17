import Foundation
import CantoCore

/// Applies and removes the Caps Lock → F18 remapping with `/usr/bin/hidutil`.
enum CapsLockRemapper {
    private static var applied = false

    static func setEnabled(_ enabled: Bool) throws {
        let current = KeyRemapping.parse(try hidutil(["property", "--get", "UserKeyMapping"]))
        let updated = KeyRemapping.applying(capsLockToF18: enabled, to: current)
        if updated != current {
            _ = try hidutil(["property", "--set", KeyRemapping.setPayload(updated)])
        }
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
