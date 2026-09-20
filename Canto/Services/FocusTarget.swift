import AppKit
import ApplicationServices

/// The app whose text field the user dictates into. A phrase waits for the cursor to be back in a
/// text field of that app, so text recognized after the user clicked away does not land in the
/// wrong window.
///
/// The field itself is deliberately not compared: Electron apps and web pages hand out a new
/// element for the same box while the user types, and Canto would then wait for a field that is
/// already in front of the user. Waiting must never make insertion less reliable than it was.
struct FocusTarget: Sendable {
    let pid: pid_t

    /// Accessibility calls wait for the other app to answer; a busy app must not stall dictation.
    private static let messagingTimeout: Float = 0.1

    /// Only a place where text can land is worth remembering. Anywhere else the user was not in a
    /// field, and the phrase goes wherever the cursor is, exactly as before.
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]

    /// The app whose text field has the keyboard focus, or nil when the focus is not in a field of
    /// another app.
    static func current() -> FocusTarget? {
        guard Permissions.accessibility else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        guard let element = copyElement(system, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let role = string(element, kAXRoleAttribute), textRoles.contains(role) else { return nil }
        return FocusTarget(pid: pid)
    }

    /// Whether the cursor is back in a text field of that app. Asked off the main thread: an app
    /// that stops answering must not freeze Canto's own interface while a phrase waits.
    func isReady() async -> Bool {
        let pid = pid
        return await Task.detached { Self.current()?.pid == pid }.value
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
}
