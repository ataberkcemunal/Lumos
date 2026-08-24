import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = LightStore()
    private var menuController: MenuBarPanelController?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        menuController = MenuBarPanelController(store: store)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.store.refreshAll() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Lumos’tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Dosya")
        let closeItem = NSMenuItem(title: "Pencereyi Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = nil
        fileMenu.addItem(closeItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Düzen")
        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

@main
enum LumosApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        _ = delegate
    }
}

@MainActor
private final class MenuBarPanelController: NSObject, NSMenuDelegate {
    private let store: LightStore
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let contentItem: NSMenuItem
    private let hostingView: NSHostingView<AnyView>

    init(store: LightStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        contentItem = NSMenuItem()
        hostingView = NSHostingView(rootView: AnyView(
            MenuBarView(dismiss: { [weak menu] in menu?.cancelTracking() })
                .environment(store)
        ))
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "Lumos"
        }

        menu.autoenablesItems = false
        menu.delegate = self
        contentItem.target = self
        contentItem.action = #selector(keepMenuContentEnabled(_:))
        contentItem.view = hostingView
        contentItem.isEnabled = true
        menu.addItem(contentItem)
        statusItem.menu = menu

        updateStatusIcon()
        resizeMenuContent()
        observeStore()
    }

    @objc private func keepMenuContentEnabled(_ sender: Any?) {
        // The custom view handles its own controls. A valid target/action keeps
        // AppKit from treating the containing menu item as disabled.
    }

    func menuWillOpen(_ menu: NSMenu) {
        resizeMenuContent()
        Task { await store.refreshAll() }
    }

    private func resizeMenuContent() {
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: max(120, min(fitting.height, 720)))
    }

    private func updateStatusIcon() {
        let symbol = store.devices.contains { $0.isReachable && $0.isOn } ? "lightbulb.fill" : "lightbulb"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lumos")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.devices.map { ($0.isReachable, $0.isOn) }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusIcon()
                self?.observeStore()
            }
        }
    }

}
