import AppKit
import SwiftUI

/// Owns Canto's regular windows. A menu bar app has to activate itself before showing a
/// window, otherwise the window opens behind the app the user is in.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = WindowCoordinator()

    enum SettingsTab: Int, CaseIterable {
        case general, dictation, recognition, text, advanced, about
    }

    private var settingsWindow: NSWindow?
    private var settingsTabs: SettingsTabViewController?
    private var historyWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func showSettings(tab: SettingsTab? = nil) {
        if settingsWindow == nil {
            let (window, tabs) = Self.makeSettingsWindow()
            window.delegate = self
            settingsWindow = window
            settingsTabs = tabs
        }
        if let tab {
            settingsTabs?.selectedTabViewItemIndex = tab.rawValue
        }
        present(settingsWindow)
    }

    /// The settings window, not yet shown. The size is set explicitly: a tab view controller
    /// otherwise starts from NSTabView's small default and clips the forms.
    static func makeSettingsWindow() -> (NSWindow, SettingsTabViewController) {
        let tabs = SettingsTabViewController()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsTabViewController.contentSize),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.contentViewController = tabs
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(SettingsTabViewController.contentSize)
        window.center()
        return (window, tabs)
    }

    func showHistory() {
        if historyWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "History")
            window.contentViewController = NSHostingController(rootView: HistoryView().environment(AppModel.shared))
            window.minSize = NSSize(width: 460, height: 360)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("CantoHistory")
            historyWindow = window
        }
        present(historyWindow)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentViewController = NSHostingController(rootView: WelcomeView { [weak self] in
                AppModel.shared.completeOnboarding()
                self?.welcomeWindow?.close()
            }.environment(AppModel.shared))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            welcomeWindow = window
        }
        present(welcomeWindow)
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow {
            AppModel.shared.stopMicrophoneTest()
        }
        // Back to a pure menu bar app once the last window is gone.
        DispatchQueue.main.async {
            let open = [self.settingsWindow, self.historyWindow, self.welcomeWindow].contains { $0?.isVisible == true }
            if !open {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

/// System Settings–style toolbar tabs; the window title follows the selected tab.
final class SettingsTabViewController: NSTabViewController {
    static let contentSize = NSSize(width: 680, height: 600)

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        let model = AppModel.shared
        add(GeneralPane(), title: String(localized: "General"), symbol: "gearshape", model: model)
        add(DictationPane(), title: String(localized: "Dictation"), symbol: "mic", model: model)
        add(RecognitionPane(), title: String(localized: "Recognition"), symbol: "waveform", model: model)
        add(TextPane(), title: String(localized: "Text & AI"), symbol: "text.badge.star", model: model)
        add(AdvancedPane(), title: String(localized: "Advanced"), symbol: "slider.horizontal.3", model: model)
        add(AboutPane(), title: String(localized: "About"), symbol: "info.circle", model: model)
    }

    private func add<Content: View>(_ view: Content, title: String, symbol: String, model: AppModel) {
        let controller = NSHostingController(rootView: view.environment(model).frame(maxWidth: .infinity, maxHeight: .infinity))
        // Every tab has the same size, so switching tabs never resizes or clips the window.
        controller.sizingOptions = []
        controller.preferredContentSize = Self.contentSize
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? ""
    }
}
