import Foundation
import IOKit.hid

/// Lights the Caps Lock LED while Canto records. Caps Lock is remapped to F18, so macOS no longer
/// drives the light itself. A keyboard's LED is only reachable with Input Monitoring, which macOS
/// asks for once when the user turns this on. The keyboard is opened without seizing it, so typing
/// is never blocked, no key events are read, and only the LED is written: the Caps Lock state stays.
final class CapsLockLight: @unchecked Sendable {
    static let shared = CapsLockLight()

    private let queue = DispatchQueue(label: "io.github.jehkinen.canto.capslock-light", qos: .userInitiated)
    /// Opened once and kept; only touched on `queue`.
    private var manager: IOHIDManager?
    private var isLit = false

    static var isAllowed: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows macOS's Input Monitoring prompt the first time; false until it is granted.
    @discardableResult
    static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    func set(_ on: Bool) {
        queue.async { self.apply(on) }
    }

    /// Before quitting: the light must not stay on after Canto is gone.
    func turnOffNow() {
        queue.sync { apply(false) }
    }

    private func apply(_ on: Bool) {
        guard on != isLit else { return }
        guard let manager = openManager() else { return }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let match = [kIOHIDElementUsagePageKey: kHIDPage_LEDs, kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock] as CFDictionary
        for device in devices {
            let elements = IOHIDDeviceCopyMatchingElements(device, match, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
            for element in elements {
                IOHIDDeviceSetValue(device, element, IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0))
            }
        }
        isLit = on
    }

    private func openManager() -> IOHIDManager? {
        if let manager { return manager }
        guard Self.isAllowed else { return nil }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                                kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        self.manager = manager
        return manager
    }
}
