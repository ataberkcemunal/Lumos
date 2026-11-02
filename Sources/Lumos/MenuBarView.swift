import AppKit
import SwiftUI

private enum MenuLayout {
    static let width: CGFloat = 280
    static let horizontalInset: CGFloat = 12
    static let iconColumnWidth: CGFloat = 28
    static let columnSpacing: CGFloat = 8
    static let headerHeight: CGFloat = 44
    static let rowVerticalInset: CGFloat = 8
    static let rowSpacing: CGFloat = 6
    static let footerHeight: CGFloat = 44
    static let footerButtonHeight: CGFloat = 28
    static let footerCornerRadius: CGFloat = 7
    static let compactThumbRadius: CGFloat = 9.5
    static let valueColumnWidth: CGFloat = 31
}

struct MenuBarView: View {
    let dismiss: () -> Void
    @Environment(LightStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var isOpenHovered = false
    @State private var isQuitHovered = false
    @State private var isRefreshHovered = false

    init(dismiss: @escaping () -> Void = {}) {
        self.dismiss = dismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 3) {
                    ForEach(store.devices) { device in
                        Image(systemName: headerSymbol(for: device))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color.secondary)
                            .frame(height: 18)
                    }
                }
                .font(.body)
                .frame(width: MenuLayout.iconColumnWidth, alignment: .leading)
                Text("Tüm Lambalar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                CommandErrorIndicator(hasError: visibleDevices.contains { store.connectionFeedback[$0.id]?.isError == true })
                MixedPowerToggle(state: allPowerState, colors: visibleDevices.filter(\.isOn).map { activeColor(for: $0) }, action: {
                    Task { await store.setPower(allPowerState != .on, ids: visibleDevices.map(\.id)) }
                }, compact: true)
                .disabled(visibleDevices.isEmpty)
            }
            .padding(.horizontal, MenuLayout.horizontalInset)
            .frame(height: MenuLayout.headerHeight)

            Divider().opacity(0.55)
            ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, device in
                MenuBarLightRow(device: device)
                if index < store.devices.count - 1 {
                    Divider().opacity(0.55).padding(.horizontal, MenuLayout.horizontalInset)
                }
            }

            Divider().opacity(0.55)
            HStack(spacing: MenuLayout.columnSpacing) {
                Button(action: openMainWindow) {
                    Text("Lumos’u aç")
                        .frame(maxWidth: .infinity)
                        .frame(height: MenuLayout.footerButtonHeight)
                        .background(
                            Color.primary.opacity(isOpenHovered ? 0.12 : 0.055),
                            in: RoundedRectangle(cornerRadius: MenuLayout.footerCornerRadius)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardActivatable(RoundedRectangle(cornerRadius: MenuLayout.footerCornerRadius), action: openMainWindow)
                .onHover { isOpenHovered = $0 }
                RefreshButton(width: 34, height: MenuLayout.footerButtonHeight)
                    .background(
                        Color.primary.opacity(isRefreshHovered ? 0.12 : 0.055),
                        in: RoundedRectangle(cornerRadius: MenuLayout.footerCornerRadius)
                    )
                    .onHover { isRefreshHovered = $0 }
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .frame(width: 34, height: MenuLayout.footerButtonHeight)
                        .background(
                            Color.primary.opacity(isQuitHovered ? 0.12 : 0.055),
                            in: RoundedRectangle(cornerRadius: MenuLayout.footerCornerRadius)
                        )
                }
                .buttonStyle(.plain)
                .keyboardActivatable(RoundedRectangle(cornerRadius: MenuLayout.footerCornerRadius)) { NSApp.terminate(nil) }
                .foregroundStyle(.primary)
                .onHover { isQuitHovered = $0 }
                .help("Lumos’tan Çık")
            }
            .font(.subheadline)
            .controlSize(.small)
            .padding(.horizontal, MenuLayout.horizontalInset)
            .frame(height: MenuLayout.footerHeight)
        }
        .frame(width: MenuLayout.width)
        .fontDesign(.default)
        .environment(\.controlActiveState, .key)
    }

    private func openMainWindow() {
        dismiss()
        DispatchQueue.main.async { MainWindowPresenter.shared.show(store: store) }
    }

    private var allPowerState: MixedPowerState {
        let count = visibleDevices.filter(\.isOn).count
        if count == 0 { return .off }
        if count == visibleDevices.count { return .on }
        return .mixed
    }

    private var visibleDevices: [LightDevice] { store.devices.filter(\.isReachable) }

    private func activeColor(for device: LightDevice) -> Color {
        let color = device.isColorMode == true ? device.color : whiteTemperatureColor(device.temperature)
        return interfaceAccentColor(color, for: colorScheme)
    }

    private func headerSymbol(for device: LightDevice) -> String {
        let base = device.name == "Çalışma Masası Lambası" ? "lamp.desk" : "lightbulb.led"
        return device.isReachable && device.isOn ? "\(base).fill" : base
    }
}

private struct MenuBarLightRow: View {
    @Environment(LightStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let device: LightDevice
    @State private var brightness: Double
    @State private var brightnessPreviewTask: Task<Void, Never>?
    @State private var isDraggingBrightness = false

    init(device: LightDevice) {
        self.device = device
        _brightness = State(initialValue: Double(device.brightness))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MenuLayout.rowSpacing) {
            HStack(spacing: MenuLayout.columnSpacing) {
                Image(systemName: symbol).frame(width: MenuLayout.iconColumnWidth, height: 18)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).font(.subheadline.weight(.medium))
                    LightStatusText(status: store.status(for: device))
                }
                Spacer()
                MixedPowerToggle(state: device.isReachable && device.isOn ? .on : .off, colors: [activeColor], action: {
                    Task { await store.setPower(!device.isOn, ids: [device.id]) }
                }, compact: true)
                .disabled(!device.isReachable)
                .opacity(device.isReachable ? 1 : 0.48)
            }

            // Dim only the controls so the name and connection status stay legible.
            Group {
                HStack(spacing: MenuLayout.columnSpacing) {
                    Image(systemName: "sun.min")
                        .foregroundStyle(.secondary)
                        .frame(width: MenuLayout.iconColumnWidth, height: 18)
                    BrightnessSlider(value: $brightness, activeColor: activeColor, commit: {
                        brightnessPreviewTask?.cancel()
                        Task { await store.setBrightness(Int(brightness), id: device.id) }
                    }, liveChange: { value in
                        brightnessPreviewTask?.cancel()
                        let previewValue = Int(value)
                        brightnessPreviewTask = Task {
                            try? await Task.sleep(for: .milliseconds(45))
                            guard !Task.isCancelled else { return }
                            await store.previewBrightness(previewValue, id: device.id)
                        }
                    }, editingChanged: { isDraggingBrightness = $0 }, compact: true)
                        // The circular thumb is inset by half its diameter. Compensate
                        // optically so the visible track starts on the shared content grid.
                        .padding(.leading, -MenuLayout.compactThumbRadius)
                    Text("\(Int(brightness))%")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.primary.opacity(0.58))
                        .frame(width: MenuLayout.valueColumnWidth, alignment: .trailing)
                }

                if !store.favoriteColors.isEmpty || !store.favoriteTemperatures.isEmpty {
                    HStack(spacing: MenuLayout.columnSpacing) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: MenuLayout.iconColumnWidth, height: 18)
                        ForEach(store.favoriteTemperatures.prefix(5), id: \.self) { kelvin in
                            Button { applyTemperature(kelvin) } label: {
                                Circle().fill(whiteColor(for: kelvin)).frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected(kelvin: kelvin) ? Color.primary : .primary.opacity(0.15), lineWidth: isSelected(kelvin: kelvin) ? 1.5 : 1)
                                            .frame(width: isSelected(kelvin: kelvin) ? 19 : 16, height: isSelected(kelvin: kelvin) ? 19 : 16)
                                    )
                            }
                            .buttonStyle(.plain)
                            .keyboardActivatable(Circle()) { applyTemperature(kelvin) }
                            .help("\(kelvin) K")
                        }
                        ForEach(store.favoriteColors.prefix(5), id: \.self) { hex in
                            Button { applyColor(hex) } label: {
                                Circle().fill(color(from: hex) ?? .white).frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected(hex: hex) ? Color.primary : .primary.opacity(0.15), lineWidth: isSelected(hex: hex) ? 1.5 : 1)
                                            .frame(width: isSelected(hex: hex) ? 19 : 16, height: isSelected(hex: hex) ? 19 : 16)
                                    )
                            }
                            .buttonStyle(.plain)
                            .keyboardActivatable(Circle()) { applyColor(hex) }
                            .help("#\(hex.uppercased())")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .disabled(!device.isReachable)
            .opacity(device.isReachable ? 1 : 0.48)
        }
        .padding(.horizontal, MenuLayout.horizontalInset)
        .padding(.vertical, MenuLayout.rowVerticalInset)
        .onDisappear { brightnessPreviewTask?.cancel() }
        .onChange(of: device.brightness) { _, value in
            guard !isDraggingBrightness else { return }
            brightness = Double(value)
        }
    }

    private var symbol: String {
        let base = device.name == "Çalışma Masası Lambası" ? "lamp.desk" : "lightbulb.led"
        return device.isReachable && device.isOn ? "\(base).fill" : base
    }

    private var activeColor: Color {
        interfaceAccentColor(
            device.isColorMode == true ? device.color : whiteColor(for: device.temperature),
            for: colorScheme
        )
    }

    private func whiteColor(for kelvin: Int) -> Color {
        whiteTemperatureColor(kelvin)
    }

    private func applyTemperature(_ kelvin: Int) {
        Task { await store.setTemperature(kelvin, id: device.id) }
    }

    private func applyColor(_ hex: String) {
        guard let value = color(from: hex) else { return }
        Task { await store.setColor(value, id: device.id) }
    }

    private func color(from hex: String) -> Color? {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }

    private func isSelected(kelvin: Int) -> Bool {
        device.isColorMode != true && device.temperature == kelvin
    }

    private func isSelected(hex: String) -> Bool {
        guard device.isColorMode == true else { return false }
        let current = String(format: "%02X%02X%02X", device.red, device.green, device.blue)
        return current.caseInsensitiveCompare(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) == .orderedSame
    }
}

@MainActor
final class MainWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = MainWindowPresenter()
    private var window: NSWindow?

    func show(store: LightStore) {
        // Keep the accessory policy stable while opening and closing windows.
        // Switching policy here needlessly rebuilds Dock and application-menu state.
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 466),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.title = "Lumos"
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.titlebarSeparatorStyle = .none
            created.isOpaque = false
            created.backgroundColor = .clear
            created.level = .normal
            created.collectionBehavior = []
            created.isMovableByWindowBackground = true
            created.isReleasedWhenClosed = false
            let content = ContentView()
                .environment(store)
            created.contentView = NSHostingView(rootView: content)
            created.center()
            created.delegate = self
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

}
