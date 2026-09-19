import SwiftUI

@main
struct CantoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .environment(\.layoutDirection, AppLanguage.layoutDirection)
        } label: {
            MenuBarIcon(phase: model.phase, isEnabled: model.settings.isEnabled)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Quit properly on kill, Ctrl-C in a terminal or a closed terminal, so Caps Lock is given back.
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            terminationSources.append(source)
        }

        let model = AppModel.shared
        model.start()
        RecordingHUDController.shared.start(model: model)
        if model.needsOnboarding {
            WindowCoordinator.shared.showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.prepareForQuit()
    }

    /// Opening Canto again from Finder or Spotlight shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowCoordinator.shared.showSettings()
        return false
    }
}
