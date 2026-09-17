import Carbon.HIToolbox
import CantoCore

/// A system-wide shortcut through the Carbon hot key API: it needs no Accessibility or Input
/// Monitoring permission and reports both key down and key up, which push-to-talk requires.
final class HotkeyCenter {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isDown = false
    private let signature = OSType(0x5645_5952) // "VEYR"

    init() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handle(kind: GetEventKind(event))
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Returns false when another app already owns the shortcut.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode, Self.carbonModifiers(hotkey.modifiers), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        if isDown {
            isDown = false
            onRelease?()
        }
    }

    private func handle(kind: UInt32) {
        switch Int(kind) {
        case kEventHotKeyPressed where !isDown:
            isDown = true
            onPress?()
        case kEventHotKeyReleased where isDown:
            isDown = false
            onRelease?()
        default:
            break
        }
    }

    static func carbonModifiers(_ modifiers: Hotkey.Modifiers) -> UInt32 {
        var result: Int = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}
