import Carbon.HIToolbox
import SwiftUI
import CantoCore

/// Click, then press the new shortcut. Esc cancels. Plain letters need a modifier so typing
/// is never hijacked; function keys work alone.
struct ShortcutRecorder: View {
    @Binding var hotkey: Hotkey
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Group {
                if isRecording {
                    Text("Press shortcut…")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 110)
                } else {
                    KeyCaps(hotkey: hotkey)
                        .frame(minWidth: 110)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .overlay {
            if isRecording {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .onDisappear(perform: stop)
        .help(Text("Click and press a new shortcut"))
    }

    private func start() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecordingChange(false)
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if keyCode == UInt32(kVK_Escape) {
            stop()
            return
        }
        var modifiers: Hotkey.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        let onlyShift = modifiers.isEmpty || modifiers == .shift
        guard KeyNames.isFunctionKey(keyCode) || !onlyShift else {
            NSSound.beep()
            return
        }
        hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
        stop()
    }
}
