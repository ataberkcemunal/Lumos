import AppKit
import SwiftUI

extension NSApplication {
    /// Brings Lumos to the front. The cooperative `activate()` is refused while
    /// another app is frontmost, which is always the case after a menu bar click,
    /// so the panel and window would open behind it without keyboard focus.
    func bringLumosForward() {
        activate(ignoringOtherApps: true)
    }
}

/// Owns exactly one status item for the application's lifetime. Display changes
/// dismiss its presentation, never remove/reinsert or resize the status item.
@MainActor
final class MenuBarPanelController: NSObject, NSPopoverDelegate {
    private let store: LightStore
    private(set) var statusItem: NSStatusItem?
    let popover = NSPopover()
    private let scrollView = NSScrollView()
    private var hostingView: NSHostingView<AnyView>?
    private var refreshTask: Task<Void, Never>?
    private var isStopped = false
    private var lastIconIsOn: Bool?
    /// When a press on the status button closed the transient popover, the
    /// same click's mouse-up must not open it again.
    private var closedByButtonPressAt: TimeInterval?
    private static let width: CGFloat = 280
    private static let maximumHeight: CGFloat = 640

    init(store: LightStore) {
        self.store = store
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.autosaveName = "LumosStatusItem"
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.toolTip = "Lumos"
            button.setAccessibilityLabel("Lumos — ışık kontrolleri")
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Controls live in a regular window, outside NSMenu's tracking loop.
        // AppKit owns outside-click and Escape dismissal; no global event taps.
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(displayContextChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(self, selector: #selector(displayContextChanged(_:)), name: name, object: nil)
        }
        workspace.addObserver(self, selector: #selector(didWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        updateStatusIcon()
        observeStore()
        refresh()
    }

    @objc func togglePopover(_ sender: Any?) {
        guard !isStopped else { return }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
            return
        }
        if popover.isShown {
            dismiss()
            return
        }
        if let closedAt = closedByButtonPressAt {
            closedByButtonPressAt = nil
            if let event = NSApp.currentEvent, event.timestamp - closedAt < 1 { return }
        }
        // Use the current status button's window on every click. Cached screen
        // coordinates are invalid after hotplug, scaling, or Space transitions.
        guard let button = statusItem?.button, button.window?.screen != nil else { return }
        prepareContent()
        resizeContent()
        // Anchor first, on the menu bar that was clicked. Activating beforehand can
        // move menu bar focus to the display holding Lumos's window, which shifts
        // the status button and opens the panel on the wrong monitor.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(popover.isShown)
        // An accessory app is not active by itself; without activation, Tab and
        // arrow keys would go to the previously frontmost app.
        NSApp.bringLumosForward()
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
            // Start without a focused control so a stray Space cannot switch lamps;
            // the first Tab enters the controls.
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
        }
        refresh()
    }

    /// Right-click (or Control-click) shows a plain menu with Quit. The menu is
    /// attached only while it is tracking, so left clicks keep opening the popover.
    private func showContextMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        dismiss()
        let menu = NSMenu()
        menu.addItem(withTitle: "Lumos’tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    func dismiss() {
        popover.close()
        statusItem?.button?.highlight(false)
    }

    @objc func displayContextChanged(_ notification: Notification) {
        dismiss()
    }

    @objc func didWake(_ notification: Notification) {
        guard !isStopped else { return }
        dismiss()
        refresh()
    }

    /// A transient popover closes on mouse-down outside it, which includes the
    /// status button, so the toggle sees it already closed on mouse-up.
    func popoverWillClose(_ notification: Notification) {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
              let button = statusItem?.button, event.window === button.window,
              button.bounds.contains(button.convert(event.locationInWindow, from: nil)) else {
            closedByButtonPressAt = nil
            return
        }
        closedByButtonPressAt = event.timestamp
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        // Releasing the view resets transient UI and cancels pending slider previews.
        scrollView.documentView = nil
        hostingView = nil
        popover.contentViewController = nil
    }

    private func prepareContent() {
        guard hostingView == nil else { return }
        let host = NSHostingView(rootView: AnyView(
            MenuBarView(dismiss: { [weak self] in self?.dismiss() })
                .environment(store)
                .fixedSize(horizontal: false, vertical: true)
        ))
        host.frame.size.width = Self.width
        hostingView = host
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = host
        let controller = NSViewController()
        controller.view = scrollView
        popover.contentViewController = controller
    }

    private func resizeContent() {
        guard let host = hostingView else { return }
        host.layoutSubtreeIfNeeded()
        let height = max(120, ceil(host.fittingSize.height))
        host.setFrameSize(NSSize(width: Self.width, height: height))
        let available = statusItem?.button?.window?.screen?.visibleFrame.height ?? Self.maximumHeight
        let limit = max(120, min(Self.maximumHeight, available - 24))
        let size = NSSize(width: Self.width, height: min(height, limit))
        scrollView.setFrameSize(size)
        popover.contentSize = size
    }

    private func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self, store] in
            await store.refreshAll()
            self?.refreshTask = nil
        }
    }

    private func updateStatusIcon() {
        let isOn = store.devices.contains { $0.isReachable && $0.isOn }
        guard lastIconIsOn != isOn else { return }
        lastIconIsOn = isOn
        let image = NSImage(systemSymbolName: isOn ? "lightbulb.fill" : "lightbulb",
                            accessibilityDescription: "Lumos")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    private func observeStore() {
        guard !isStopped else { return }
        withObservationTracking {
            _ = store.devices
            _ = store.favoriteColors
            _ = store.favoriteTemperatures
            _ = store.connectionFeedback
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.updateStatusIcon()
                if self.popover.isShown { self.resizeContent() }
                self.observeStore()
            }
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        refreshTask?.cancel()
        refreshTask = nil
        dismiss()
        scrollView.documentView = nil
        hostingView = nil
        popover.contentViewController = nil
        popover.delegate = nil
        if let statusItem {
            statusItem.button?.target = nil
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }
}
