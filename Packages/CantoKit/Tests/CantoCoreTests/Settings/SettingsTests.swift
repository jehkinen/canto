import Foundation
import Testing
@testable import CantoCore

struct KeyRemappingTests {
    static let rightCommandToEscape = KeyRemapping.Mapping(source: 0x7_0000_00E7, destination: 0x7_0000_0029)

    @Test func parsesRealHidutilOutput() {
        let output = "(\n        {\n        HIDKeyboardModifierMappingDst = 30064771181;\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)\n"
        #expect(KeyRemapping.parse(output) == [KeyRemapping.capsLockToF18])
    }

    @Test func parsesEmptyMapping() {
        #expect(KeyRemapping.parse("(null)\n").isEmpty)
        #expect(KeyRemapping.parse("(\n)\n").isEmpty)
    }

    @Test func parsesSeveralEntriesInAnyOrderAndHex() {
        let output = "( { HIDKeyboardModifierMappingSrc = 0x7000000E7; HIDKeyboardModifierMappingDst = 0x700000029; }, { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; } )"
        #expect(KeyRemapping.parse(output) == [Self.rightCommandToEscape, KeyRemapping.capsLockToF18])
    }

    @Test func enablingKeepsOtherMappingsAndReplacesCapsLockRemap() {
        let capsToEscape = KeyRemapping.Mapping(source: KeyRemapping.capsLock, destination: 0x7_0000_0029)
        #expect(KeyRemapping.applying(capsLockToF18: true, to: [Self.rightCommandToEscape, capsToEscape])
            == [Self.rightCommandToEscape, KeyRemapping.capsLockToF18])
    }

    @Test func disablingRemovesOnlyOurMapping() {
        #expect(KeyRemapping.applying(capsLockToF18: false, to: [Self.rightCommandToEscape, KeyRemapping.capsLockToF18])
            == [Self.rightCommandToEscape])
    }

    @Test func payloadIsJSON() throws {
        let payload = KeyRemapping.setPayload([KeyRemapping.capsLockToF18])
        let object = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: [[String: UInt64]]]
        #expect(object?["UserKeyMapping"]?.first?["HIDKeyboardModifierMappingDst"] == KeyRemapping.f18)
    }
}

struct AppSettingsTests {
    @Test func capsLockToggleRemembersAndRestoresHotkey() {
        var settings = AppSettings()
        settings.hotkey = Hotkey(keyCode: 0x60, modifiers: [.option])
        settings.setCapsLockAsHotkey(true)
        #expect(settings.hotkey == .capsLock)
        settings.setCapsLockAsHotkey(false)
        #expect(settings.hotkey == Hotkey(keyCode: 0x60, modifiers: [.option]))
        #expect(settings.hotkeyBeforeCapsLock == nil)
    }

    @Test func turningCapsLockOffKeepsAShortcutChosenMeanwhile() {
        var settings = AppSettings()
        settings.setCapsLockAsHotkey(true)
        settings.hotkey = Hotkey(keyCode: 0x61)
        settings.setCapsLockAsHotkey(false)
        #expect(settings.hotkey == Hotkey(keyCode: 0x61))
    }

    @Test func decodesOlderPayloadWithMissingKeys() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"activationMode":"toggle"}"#.utf8))
        #expect(settings.activationMode == .toggle)
        #expect(settings.hotkey == .default)
        #expect(settings.silenceTimeoutMs == 700)
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = AppSettings()
        settings.language = "ru"
        settings.textProcessingMode = .mdStructural
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func sanitizedClampsRanges() {
        var settings = AppSettings()
        settings.silenceTimeoutMs = 50
        settings.whisperBeamSize = 9
        settings.enterTriggerPhrase = String(repeating: "a", count: 200)
        let clean = settings.sanitized()
        #expect(clean.silenceTimeoutMs == 200)
        #expect(clean.whisperBeamSize == 5)
        #expect(clean.enterTriggerPhrase.count == 120)
    }
}
