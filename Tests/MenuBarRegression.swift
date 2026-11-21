import AppKit
import SwiftUI

@main
struct MenuBarRegression {
    @MainActor
    static func main() async {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let store = LightStore()
        // This executable has its own defaults domain. Never contact real lamps.
        store.devices = []
        let controller = MenuBarPanelController(store: store)
        guard let item = controller.statusItem else { fatalError("Missing status item") }
        precondition(item.length == NSStatusItem.squareLength)
        precondition(item.menu == nil, "Interactive controls must not use menu tracking")
        precondition(item.button?.image?.isTemplate == true)
        precondition(controller.popover.contentViewController == nil, "Content should be lazy")
        try? await Task.sleep(for: .milliseconds(300))

        // The panel fades out, so it counts as shown until the animation ends.
        func closed() async -> Bool {
            for _ in 0..<50 where controller.popover.isShown {
                try? await Task.sleep(for: .milliseconds(20))
            }
            return !controller.popover.isShown
        }

        for _ in 0..<5 {
            controller.togglePopover(nil)
            precondition(controller.popover.isShown, "Popover failed to open in GUI session")
            precondition(controller.popover.contentSize.width == 280)
            precondition((120...640).contains(controller.popover.contentSize.height))
            controller.togglePopover(nil)
            let isClosed = await closed()
            precondition(isClosed)
            precondition(controller.statusItem === item, "Status item was recreated")
        }

        controller.togglePopover(nil)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: application)
        let isClosed = await closed()
        precondition(isClosed, "Display change should dismiss stale anchor")
        precondition(controller.statusItem === item)

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            controller.togglePopover(nil)
            NSWorkspace.shared.notificationCenter.post(name: name, object: NSWorkspace.shared)
            let isClosed = await closed()
            precondition(isClosed, "Workspace transition should close presentation")
            precondition(controller.statusItem === item)
        }
        try? await Task.sleep(for: .milliseconds(100))

        // A long device list remains scrollable inside the panel, not the status item.
        let sample = LightDevice(name: "Regression lamp", ip: "127.0.0.1", room: "")
        store.devices = (0..<12).map { _ in LightDevice(name: sample.name, ip: sample.ip, room: "") }
        // Mark refreshing to prevent network work when opening this synthetic fixture.
        store.isRefreshing = true
        controller.togglePopover(nil)
        guard let scroll = controller.popover.contentViewController?.view as? NSScrollView else {
            fatalError("Missing scroll container")
        }
        precondition(scroll.documentView!.frame.height > controller.popover.contentSize.height)
        precondition(controller.popover.contentSize.height <= 640)
        controller.dismiss()
        let isDismissed = await closed()
        precondition(isDismissed)

        store.devices[0].isOn = true
        try? await Task.sleep(for: .milliseconds(100))
        precondition(controller.statusItem === item)
        precondition(item.button?.image != nil)
        controller.stop()
        controller.stop()
        precondition(controller.statusItem == nil)
        controller.togglePopover(nil)
        precondition(!controller.popover.isShown)
        store.devices = []
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: application)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(100))
        precondition(controller.statusItem == nil, "Stopped observers must not recreate status item")
        print("PASS: menu-bar lifecycle, repeated presentation, display/Space/sleep/wake notifications, scrolling and teardown")
    }
}
