import AppKit
import SwiftUI
import CantoCore

@main
@MainActor
enum SnapshotMain {
    static func main() {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        // The real icon, which the panel and the About pane show.
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSApp.applicationIconImage = NSImage(contentsOf: repository.appendingPathComponent(
            "Canto/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"))

        let model = AppModel.shared
        let now = Date()
        let russian = Locale.preferredLanguages.first?.hasPrefix("ru") == true
        let samples = russian
            ? [("Созвон перенесли на четверг, я пришлю ссылку в Slack.", "Telegram"),
               ("Бэкенд на NestJS, фронтенд на Next.js, деплоим в AWS.", "Cursor"),
               ("Список покупок: молоко, хлеб, кофе.", "Notes")]
            : [("Let's move the release to Thursday and ship the macOS build first.", "Slack"),
               ("The backend runs on NestJS and deploys to AWS through GitHub Actions.", "Cursor"),
               ("Buy milk, bread and coffee on the way home.", "Notes")]
        model.setSnapshotState(
            phase: .idle, level: 0,
            history: zip(samples, [90.0, 600, 86_400]).map { sample, age in
                TranscriptEntry(date: now.addingTimeInterval(-age), text: sample.0, duration: 4.2, provider: .local,
                                processingMode: .basic, appName: sample.1, latency: 0.4)
            }
        )
        var readme = model.settings
        readme.transcriptionProvider = .local
        readme.whisperModel = .base
        readme.language = russian ? "ru" : "en"
        readme.vocabulary = ["OpenAI", "ChatGPT", "Node.js", "NestJS", "AWS"]
        model.settings = readme

        // The real settings window, including its size, so clipping shows up here too.
        let (settings, tabs) = WindowCoordinator.makeSettingsWindow()
        settings.appearance = NSAppearance(named: .aqua)
        for index in tabs.tabViewItems.indices {
            tabs.selectedTabViewItemIndex = index
            renderWindow(settings, name: "window-settings-\(index)", to: output)
        }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            model.setSnapshotState(phase: .idle, level: 0)
            render(MenuBarPanel(), width: 340, name: "menu-idle-\(suffix)", appearance: appearance, to: output)
            if appearance == .aqua {
                model.setSnapshotState(phase: .listening(since: now.addingTimeInterval(-7)), level: 0.55)
                render(MenuBarPanel(), width: 340, name: "menu-listening-light", appearance: appearance, to: output)
                render(RecordingHUDView().frame(width: 420, height: 90), width: 420, name: "hud-listening", appearance: appearance, to: output)
                model.setSnapshotState(phase: .transcribing, level: 0)
                render(MenuBarPanel(), width: 340, name: "menu-transcribing-light", appearance: appearance, to: output)
                render(RecordingHUDView().frame(width: 420, height: 90), width: 420, name: "hud-transcribing", appearance: appearance, to: output)
                model.setSnapshotState(phase: .idle, level: 0)
            }
            render(GeneralPane().frame(width: 620, height: 560), width: 620, name: "settings-general-\(suffix)", appearance: appearance, to: output)
            render(DictationPane().frame(width: 620, height: 560), width: 620, name: "settings-dictation-\(suffix)", appearance: appearance, to: output)
            render(RecognitionPane().frame(width: 620, height: 560), width: 620, name: "settings-recognition-\(suffix)", appearance: appearance, to: output)
            render(TextPane().frame(width: 620, height: 560), width: 620, name: "settings-text-\(suffix)", appearance: appearance, to: output)
            render(AdvancedPane().frame(width: 620, height: 560), width: 620, name: "settings-advanced-\(suffix)", appearance: appearance, to: output)
            render(AboutPane().frame(width: 620, height: 560), width: 620, name: "settings-about-\(suffix)", appearance: appearance, to: output)
            render(HistoryView().frame(width: 640, height: 480), width: 640, name: "history-\(suffix)", appearance: appearance, to: output)
            for step in WelcomeView.Step.allCases {
                render(WelcomeView(startAt: step) {}, width: 560, name: "welcome-\(step.rawValue)-\(suffix)", appearance: appearance, to: output)
            }
        }
        // A model that is still downloading while another one does the work.
        var downloading = model.settings
        downloading.whisperModel = .largeV3Turbo
        model.settings = downloading
        model.setSnapshotDownload(.largeV3Turbo, progress: DownloadProgress(receivedBytes: 212_000_000, totalBytes: 574_000_000))
        let (downloadWindow, downloadTabs) = WindowCoordinator.makeSettingsWindow()
        downloadWindow.appearance = NSAppearance(named: .aqua)
        downloadTabs.selectedTabViewItemIndex = 2
        renderWindow(downloadWindow, name: "window-settings-downloading", to: output)
        downloadTabs.selectedTabViewItemIndex = 5
        renderWindow(downloadWindow, name: "window-settings-about", to: output)

        print("wrote snapshots to \(output.path)")
    }

    static func renderWindow(_ window: NSWindow, name: String, to output: URL) {
        guard let frameView = window.contentView?.superview else { return }
        for _ in 0..<6 {
            frameView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(name).png"))
    }

    static func render<V: View>(_ view: V, width: CGFloat, name: String, appearance: NSAppearance.Name, to output: URL) {
        let host = NSHostingView(rootView: view.environment(AppModel.shared))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.16, alpha: 1)
        window.contentView = host
        let size = host.fittingSize
        window.setContentSize(NSSize(width: width, height: max(size.height, 60)))
        host.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(name).png"))
    }
}
