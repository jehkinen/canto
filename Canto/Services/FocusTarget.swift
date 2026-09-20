import AppKit
import ApplicationServices

/// The text field the user was in when a dictation started. The phrase goes back there, so text
/// recognized while the user clicked somewhere else does not land in the wrong place.
struct FocusTarget {
    let element: AXUIElement
    let pid: pid_t
    private let role: String
    private let frame: CGRect?

    /// Accessibility calls wait for the other app to answer; a busy app must not stall dictation.
    private static let messagingTimeout: Float = 0.25

    /// Only a place where text can land is worth remembering; anything else means the user was
    /// not in a field, and the phrase goes wherever the cursor is, as before.
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]

    /// The field that has the keyboard focus right now, in whichever app is frontmost.
    static func current() -> FocusTarget? {
        guard Permissions.accessibility else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        guard let element = copyElement(system, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let role = string(element, kAXRoleAttribute), textRoles.contains(role) else { return nil }
        return FocusTarget(element: element, pid: pid, role: role, frame: frame(of: element))
    }

    /// Whether the keyboard focus is back in this field. Some apps rebuild their elements, so a
    /// field of the same kind, in the same app, in the same place counts as the same field.
    var isFocused: Bool {
        guard let now = Self.current() else { return false }
        if CFEqual(now.element, element) { return true }
        return now.pid == pid && now.role == role && now.frame != nil && now.frame == frame
    }

    /// False once the app the field belonged to is gone.
    var isAlive: Bool {
        NSRunningApplication(processIdentifier: pid) != nil
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(element, kAXPositionAttribute), AXValueGetValue(position, .cgPoint, &origin),
              let extent = axValue(element, kAXSizeAttribute), AXValueGetValue(extent, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
