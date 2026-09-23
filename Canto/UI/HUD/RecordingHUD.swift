import AppKit
import OSLog
import SwiftUI
import CantoCore

/// The floating capsule near the bottom of the screen that shows listening and transcription
/// progress. It never takes focus, so text still lands in the app the user is working in.
@MainActor
final class RecordingHUDController {
    static let shared = RecordingHUDController()

    private let logger = Logger(subsystem: "io.github.jehkinen.canto", category: "hud")
    private var panel: NSPanel?
    private weak var model: AppModel?
    private var hideTask: Task<Void, Never>?
    /// The collection behavior the capsule needs on every desktop and over full-screen apps.
    private static let everywhere: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                                                  .stationary, .ignoresCycle]

    func start(model: AppModel) {
        self.model = model
        observe()
        // Switching to another desktop or a full-screen app while recording: bring the capsule along.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let panel = RecordingHUDController.shared.panel, panel.alphaValue > 0 else { return }
                panel.orderFrontRegardless()
            }
        }
    }

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.phase
            _ = model.notice
            _ = model.settings.showRecordingHUD
        } onChange: {
            Task { @MainActor [weak self] in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        guard let model else { return }
        let visible: Bool
        switch model.phase {
        case .listening, .transcribing, .inserted, .failed: visible = model.settings.showRecordingHUD
        case .idle: visible = model.settings.showRecordingHUD && model.notice != nil
        }
        if visible {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
        }
        // Every time, not only when hidden: a capsule macOS left on another desktop or behind a
        // full-screen app is otherwise faded in where the user is not.
        panel.orderFrontRegardless()
        if !panel.isOnActiveSpace {
            // macOS kept the capsule on the desktop it was last shown on. Taking it out and
            // putting it back, with the behavior set again, brings it to the desktop in use.
            panel.orderOut(nil)
            panel.collectionBehavior = Self.everywhere
            panel.orderFrontRegardless()
        }
        logger.info("""
            capsule on the active desktop: \(panel.isOnActiveSpace, privacy: .public),             level \(panel.level.rawValue, privacy: .public),             at \(Int(panel.frame.origin.x), privacy: .public),\(Int(panel.frame.origin.y), privacy: .public)
            """)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        hideTask?.cancel()
        hideTask = Task {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: nil)
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 90),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Above the screen-saver level: some apps (the Claude desktop app, presentation and
        // meeting tools) put their own window there, and the capsule has to stay visible over them.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        panel.collectionBehavior = Self.everywhere
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        if let model {
            let host = NSHostingView(rootView: RecordingHUDView().environment(model).environment(\.layoutDirection, AppLanguage.layoutDirection))
            host.sizingOptions = []
            panel.contentView = host
        }
        self.panel = panel
        return panel
    }

    /// Bottom center of the screen with the mouse pointer, above the Dock.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + 28))
    }
}

struct RecordingHUDView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(hudBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.3), value: model.phase)
    }

    @ViewBuilder
    private var hudBackground: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .listening where model.microphoneWarmingUp:
            ProgressView().controlSize(.small)
            Text("Starting the microphone…").font(.callout.weight(.medium))
        case .listening(let since):
            PulsingDot()
            Waveform(level: model.level, barCount: 22, maxHeight: 26)
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text(Duration.seconds(max(0, context.date.timeIntervalSince(since))), format: .time(pattern: .minuteSecond))
                    .font(.system(.callout, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // Hands-free after a tap: the key that finishes the take.
            if model.isHandsFree {
                KeyCaps(hotkey: model.settings.hotkey)
                    .help(Text("Press the shortcut again to finish"))
            }
        case .transcribing:
            ProgressView().controlSize(.small)
            Text("Transcribing…").font(.callout.weight(.medium))
            if let since = model.transcribingSince {
                ElapsedTime(since: since)
            }
        case .inserted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                .symbolEffect(.bounce, value: model.phase)
            Text("Inserted").font(.callout.weight(.medium))
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
            Text(message).font(.callout.weight(.medium)).lineLimit(1)
        case .idle:
            if let notice = model.notice {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.title3)
                Text(notice.message).font(.callout.weight(.medium)).lineLimit(1)
            }
        }
    }
}

private struct PulsingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Theme.listening)
            .frame(width: 10, height: 10)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
