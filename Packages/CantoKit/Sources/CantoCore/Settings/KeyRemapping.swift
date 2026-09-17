import Foundation

/// Caps Lock → F18 through the per-session HID key mapping managed by `hidutil`.
/// F18 exists on no Apple keyboard, so nothing else listens for it. Other user remappings are
/// kept; the mapping lasts until reboot, so the app re-applies it on launch and removes it on quit.
public enum KeyRemapping {
    public struct Mapping: Equatable, Sendable {
        public var source: UInt64
        public var destination: UInt64

        public init(source: UInt64, destination: UInt64) {
            self.source = source
            self.destination = destination
        }
    }

    /// HID usages (page 0x07).
    public static let capsLock: UInt64 = 0x7_0000_0039
    public static let f18: UInt64 = 0x7_0000_006D
    public static let capsLockToF18 = Mapping(source: capsLock, destination: f18)

    public static func applying(capsLockToF18 enabled: Bool, to mappings: [Mapping]) -> [Mapping] {
        if enabled {
            // A key has a single mapping, so ours replaces any other Caps Lock remap.
            return mappings.filter { $0.source != capsLock } + [capsLockToF18]
        }
        return mappings.filter { $0 != capsLockToF18 }
    }

    /// Parses `hidutil property --get UserKeyMapping`, which prints an NSArray description:
    /// `(null)` or `( { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; } )`.
    public static func parse(_ output: String) -> [Mapping] {
        output.split(separator: "{").dropFirst().compactMap { entry in
            let body = entry.split(separator: "}", omittingEmptySubsequences: false).first ?? ""
            var source: UInt64?
            var destination: UInt64?
            for field in body.split(separator: ";") {
                let parts = field.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let value = number(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                switch parts[0].trimmingCharacters(in: .whitespacesAndNewlines) {
                case "HIDKeyboardModifierMappingSrc": source = value
                case "HIDKeyboardModifierMappingDst": destination = value
                default: break
                }
            }
            guard let source, let destination else { return nil }
            return Mapping(source: source, destination: destination)
        }
    }

    /// The JSON `hidutil property --set` expects.
    public static func setPayload(_ mappings: [Mapping]) -> String {
        let entries = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    private static func number(_ text: String) -> UInt64? {
        text.hasPrefix("0x") ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text)
    }
}
