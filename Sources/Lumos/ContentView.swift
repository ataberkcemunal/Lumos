import AppKit
import SwiftUI

private enum MainLayout {
    static let contentWidth: CGFloat = 772
    static let sectionSpacing: CGFloat = 24
    static let cardSpacing: CGFloat = 24
    static let cardWidth: CGFloat = 374
    static let cardHeight: CGFloat = 350
    static let cardPadding: CGFloat = 20
    static let headerHeight: CGFloat = 44
    static let headerHorizontalInset: CGFloat = 20
    static let cardContentSpacing: CGFloat = 19
    static let controlIconWidth: CGFloat = 22
    static let controlSpacing: CGFloat = 12
    static let controlHeight: CGFloat = 26
    static let controlTitleHeight: CGFloat = 18
    static let detailSectionHeight: CGFloat = 92
}

struct ContentView: View {
    @Environment(LightStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var isWindowFocused = false

    var body: some View {
        ZStack {
            LumosWindowBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                LumosGlassContainer {
                    VStack(spacing: MainLayout.sectionSpacing) {
                        allLightsCard
                        HStack(alignment: .top, spacing: MainLayout.cardSpacing) {
                            ForEach(store.devices) {
                                MinimalLightCard(device: $0)
                                    .frame(width: MainLayout.cardWidth)
                            }
                        }
                    }
                }
                .frame(width: MainLayout.contentWidth)
                .padding(.bottom, MainLayout.sectionSpacing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 76)
                WindowDragRegion()
            }
            // Title bar strip only; any taller and it swallows clicks on the header toggle.
            .frame(height: 28)
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { if let toast = store.toast { ToastView(text: toast).padding(.bottom, 22) } }
        .fontDesign(.default)
        .environment(\.controlActiveState, isWindowFocused ? .key : .inactive)
        .onAppear {
            isWindowFocused = NSApp.isActive && NSApp.keyWindow?.title == "Lumos"
            if isWindowFocused { Task { await store.refreshAll() } }
        }
        .task {
            while !Task.isCancelled {
                if isWindowFocused {
                    await store.refreshAll()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window.title == "Lumos" else { return }
            isWindowFocused = true
            Task { await store.refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window.title == "Lumos" else { return }
            isWindowFocused = false
        }
        // Restarts with each message, so an older timer cannot hide a newer toast.
        .task(id: store.toast) {
            guard store.toast != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { store.toast = nil }
        }
    }

    private var allLightsCard: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(store.devices) { device in
                    Image(systemName: topSymbol(for: device))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.secondary)
                }
            }
            .font(.title3)
            Text("Tüm Lambalar").font(.body.weight(.semibold))
            Text("•").foregroundStyle(.tertiary)
            Text(allLightsStatus).font(.callout).foregroundStyle(.secondary)
            Spacer()
            aggregateErrorStatus
            RefreshButton()
            MixedPowerToggle(state: allPowerState, colors: visibleDevices.filter(\.isOn).map { topIndicatorColor(for: $0) }) {
                Task { await store.setPower(allPowerState != .on, ids: visibleDevices.map(\.id)) }
            }
            .disabled(visibleDevices.isEmpty)
        }
        .padding(.horizontal, MainLayout.headerHorizontalInset)
        .frame(height: MainLayout.headerHeight)
        .lumosGlassOnly(in: RoundedRectangle(cornerRadius: 16))
    }

    private var allPowerState: MixedPowerState {
        let onCount = visibleDevices.filter(\.isOn).count
        if onCount == 0 { return .off }
        if onCount == visibleDevices.count { return .on }
        return .mixed
    }

    private var visibleDevices: [LightDevice] { store.devices.filter(\.isReachable) }

    @ViewBuilder private var aggregateErrorStatus: some View {
        let hasError = visibleDevices.contains { store.connectionFeedback[$0.id]?.isError == true }
        CommandErrorIndicator(hasError: hasError)
    }

    private var allLightsStatus: String {
        if visibleDevices.isEmpty { return "Lambalara ulaşılamıyor" }
        let power: String
        if visibleDevices.count == 1, let only = visibleDevices.first { power = "\(only.name) \(only.isOn ? "açık" : "kapalı")" }
        else if visibleDevices.allSatisfy({ !$0.isOn }) { power = "Tüm lambalar kapalı" }
        else if visibleDevices.allSatisfy(\.isOn) { power = "Tüm lambalar açık" }
        else { power = "\(visibleDevices.first(where: \.isOn)?.name ?? "Bir lamba") açık" }
        let missing = store.devices.count - visibleDevices.count
        return missing > 0 ? "\(power) · \(missing) lamba yanıt vermiyor" : power
    }

    private func topSymbol(for device: LightDevice) -> String {
        let base = device.name == "Çalışma Masası Lambası" ? "lamp.desk" : "lightbulb.led"
        return device.isReachable && device.isOn ? "\(base).fill" : base
    }

    private func topIndicatorColor(for device: LightDevice) -> Color {
        let color = device.isColorMode == true ? device.color : whiteTemperatureColor(device.temperature)
        return interfaceAccentColor(color, for: colorScheme)
    }

}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Lets the system move the window. A manual performDrag here would run
    /// alongside the window's own background dragging.
    private final class DraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

enum MixedPowerState { case off, mixed, on }

struct MixedPowerToggle: View {
    let state: MixedPowerState
    let colors: [Color]
    let action: () -> Void
    var compact = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule().fill(Color.secondary.opacity(0.28))
                Capsule().fill(LinearGradient(colors: colors.isEmpty ? [.orange] : colors, startPoint: .top, endPoint: .bottom))
                    .opacity(state != .off ? 0.78 : 0)
                Circle().fill(Color.white).frame(width: compact ? 19 : 22, height: compact ? 19 : 22)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(x: state == .off ? (compact ? -10 : -12) : state == .mixed ? 0 : (compact ? 10 : 12))
            }
            .frame(width: compact ? 44 : 52, height: compact ? 24 : 28)
        }
        .buttonStyle(.plain)
        .hoverOutline(Capsule())
        .keyboardActivatable(Capsule(), action: action)
        .help(state == .on ? "Kapat" : "Aç")
    }
}

struct CommandErrorIndicator: View {
    let hasError: Bool

    var body: some View {
        Group {
            if hasError {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .help("Komut gönderilemedi")
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(!hasError)
    }
}

/// Connection state under a lamp's name: errors stay until resolved, successes fade.
struct LightStatusText: View {
    let status: ConnectionFeedback?

    var body: some View {
        if let status {
            Text(status.message)
                .font(.caption)
                .foregroundStyle(status.isError ? Color.red : Color.secondary)
                .lineLimit(1)
        }
    }
}

/// Re-queries every lamp, rescanning for missing ones without waiting out the backoff.
struct RefreshButton: View {
    @Environment(LightStore.self) private var store
    var width: CGFloat = 28
    var height: CGFloat = 28

    var body: some View {
        Button(action: refresh) {
            ZStack {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardActivatable(RoundedRectangle(cornerRadius: 7), action: refresh)
        .keyboardShortcut("r")
        .foregroundStyle(.secondary)
        .disabled(store.isRefreshing)
        .help(store.isRefreshing ? "Lambalar yenileniyor" : "Yenile ve yeniden dene (⌘R)")
    }

    private func refresh() {
        guard !store.isRefreshing else { return }
        Task { await store.refreshAll(retry: true) }
    }
}

private struct MinimalLightCard: View {
    @Environment(LightStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let device: LightDevice
    @State private var brightness: Double
    @State private var brightnessPreviewTask: Task<Void, Never>?
    @State private var colorPreviewTask: Task<Void, Never>?
    @State private var temperature: Double
    @State private var kelvinInput: String
    @State private var color: Color

    private var indicatorColor: Color {
        interfaceAccentColor(
            device.isColorMode == true ? color : whiteColor(for: Int(temperature)),
            for: colorScheme
        )
    }

    private var colorModeToggle: Binding<Bool> {
        Binding(
            get: { device.isColorMode == true },
            set: { isColor in
                if isColor { Task { await store.setColor(color, id: device.id) } }
                else { Task { await store.setTemperature(Int(temperature), id: device.id) } }
            }
        )
    }

    init(device: LightDevice) {
        self.device = device
        _brightness = State(initialValue: Double(device.brightness))
        _temperature = State(initialValue: Double(device.temperature))
        _kelvinInput = State(initialValue: String(device.temperature))
        _color = State(initialValue: device.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MainLayout.cardContentSpacing) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(device.isReachable && device.isOn ? indicatorColor.opacity(0.20) : Color.secondary.opacity(0.08))
                    Image(systemName: cardSymbol)
                        .symbolRenderingMode(.monochrome)
                        .font(.title2)
                        .foregroundStyle(Color.secondary)
                }.frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.body.weight(.semibold))
                    LightStatusText(status: store.status(for: device))
                }
                Spacer()
                MixedPowerToggle(state: device.isReachable && device.isOn ? .on : .off, colors: [indicatorColor]) {
                    Task { await store.setPower(!device.isOn, ids: [device.id]) }
                }
                .disabled(!device.isReachable)
                .opacity(device.isReachable ? 1 : 0.48)
            }
            // Dim only the controls so the name and connection status stay legible.
            Group {
                Divider()
                controlTitle("Parlaklık", value: "\(Int(brightness))%")
                HStack(spacing: MainLayout.controlSpacing) {
                    Image(systemName: "sun.min")
                        .foregroundStyle(.secondary)
                        .frame(width: MainLayout.controlIconWidth)
                    BrightnessSlider(value: $brightness, activeColor: indicatorColor) {
                        brightnessPreviewTask?.cancel()
                        Task { await store.setBrightness(Int(brightness), id: device.id) }
                    } liveChange: { value in
                        brightnessPreviewTask?.cancel()
                        let previewValue = Int(value)
                        brightnessPreviewTask = Task {
                            try? await Task.sleep(for: .milliseconds(45))
                            guard !Task.isCancelled else { return }
                            await store.previewBrightness(previewValue, id: device.id)
                        }
                    }
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: MainLayout.controlIconWidth)
                }
                .frame(height: MainLayout.controlHeight)
                HStack(spacing: 10) {
                    Spacer()
                    Text("Beyaz").font(.subheadline.weight(device.isColorMode == true ? .regular : .semibold))
                        .foregroundStyle(device.isColorMode == true ? Color.secondary : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture { if device.isColorMode == true { colorModeToggle.wrappedValue = false } }
                    NeutralModeToggle(isOn: colorModeToggle)
                    Text("Renkli").font(.subheadline.weight(device.isColorMode == true ? .semibold : .regular))
                        .foregroundStyle(device.isColorMode == true ? Color.primary : Color.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { if device.isColorMode != true { colorModeToggle.wrappedValue = true } }
                    Spacer()
                }

                if device.isColorMode == true {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Renk").font(.subheadline.weight(.medium))
                            .frame(height: MainLayout.controlTitleHeight, alignment: .leading)
                        InlineColorControl(color: $color) { value in
                            colorPreviewTask?.cancel()
                            Task { await store.setColor(value, id: device.id) }
                        } live: { value in
                            store.stageColorPreview(value, id: device.id)
                            colorPreviewTask?.cancel()
                            colorPreviewTask = Task {
                                try? await Task.sleep(for: .milliseconds(45))
                                guard !Task.isCancelled else { return }
                                await store.previewColor(value, id: device.id)
                            }
                        }
                    }
                    .frame(height: MainLayout.detailSectionHeight, alignment: .top)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("Beyaz Sıcaklığı").font(.subheadline.weight(.medium))
                        .frame(height: MainLayout.controlTitleHeight, alignment: .leading)
                    HStack(spacing: MainLayout.controlSpacing) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: MainLayout.controlIconWidth)
                        KelvinSlider(value: $temperature) {
                            Task { await store.setTemperature(Int(temperature), id: device.id) }
                        } liveChange: { value in
                            Task { await store.previewTemperature(Int(value), id: device.id) }
                        }
                        Image(systemName: "snowflake")
                            .foregroundStyle(.secondary)
                            .frame(width: MainLayout.controlIconWidth)
                    }
                    .frame(height: MainLayout.controlHeight)
                    HStack(spacing: 9) {
                        Button { store.toggleFavoriteTemperature(Int(temperature)) } label: {
                            Image(systemName: isFavoriteTemperature ? "heart.fill" : "heart").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .keyboardActivatable(Circle()) { store.toggleFavoriteTemperature(Int(temperature)) }
                        .foregroundStyle(.secondary)
                        .disabled(!isFavoriteTemperature && !store.canAddFavoriteTemperature)
                        .help(isFavoriteTemperature || store.canAddFavoriteTemperature ? "Favoriye ekle veya çıkar" : LightStore.fullFavoritesHelp)
                        ForEach(store.favoriteTemperatures.prefix(LightStore.maximumFavoritesPerKind), id: \.self) { value in
                            Circle().fill(whiteColor(for: value)).frame(width: 25, height: 25)
                                .overlay(
                                    Circle().stroke(
                                        Int(temperature) == value ? Color.primary : .primary.opacity(0.15),
                                        lineWidth: Int(temperature) == value ? 1.5 : 1
                                    )
                                    .frame(
                                        width: Int(temperature) == value ? 28 : 25,
                                        height: Int(temperature) == value ? 28 : 25
                                    )
                                )
                                .contentShape(Circle())
                                .onTapGesture { applyFavoriteTemperature(value) }
                                .hoverGrow()
                                .keyboardActivatable(Circle()) { applyFavoriteTemperature(value) }
                                .help("\(value) K")
                                .contextMenu { Button("Favoriden çıkar", role: .destructive) { store.removeFavoriteTemperature(value) } }
                        }
                        Spacer()
                        Text("K").font(.caption.bold()).foregroundStyle(.secondary)
                        ValidatedTextField(text: $kelvinInput, filter: { oldValue, value in
                            let filtered = String(value.filter { $0.isNumber }.prefix(4))
                            return filtered.isEmpty || isViableKelvinPrefix(filtered) ? filtered : oldValue
                        }, onCommit: applyKelvinInput)
                            .padding(.horizontal, 8)
                            .frame(width: 76, height: 22)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    }
                    }
                    .frame(height: MainLayout.detailSectionHeight, alignment: .top)
                }
            }
            .disabled(!device.isReachable)
            .opacity(device.isReachable ? 1 : 0.48)
        }
        .padding(MainLayout.cardPadding)
        .frame(height: MainLayout.cardHeight, alignment: .center)
            .onChange(of: device.brightness) { _, value in brightness = Double(value) }
            .onChange(of: device.temperature) { _, value in
                temperature = Double(value)
                kelvinInput = String(value)
            }
            .onChange(of: temperature) { _, value in kelvinInput = String(Int(value)) }
            .onChange(of: device.color) { _, value in color = value }
            .lumosGlassSurface(
                tint: device.isReachable && device.isOn ? indicatorColor.opacity(0.12) : nil,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .lumosLegacyBorder(
                RoundedRectangle(cornerRadius: 20),
                color: device.isReachable && device.isOn
                    ? indicatorColor.opacity(0.14)
                    : .primary.opacity(0.05)
            )
    }

    private func controlTitle(_ title: String, value: String) -> some View {
        HStack { Text(title).font(.subheadline.weight(.medium)); Spacer(); Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            .frame(height: MainLayout.controlTitleHeight)
    }

    private var cardSymbol: String {
        let base = device.name == "Çalışma Masası Lambası" ? "lamp.desk" : "lightbulb.led"
        return device.isReachable && device.isOn ? "\(base).fill" : base
    }

    private func whiteColor(for kelvin: Int) -> Color {
        whiteTemperatureColor(kelvin)
    }

    private var isFavoriteTemperature: Bool { store.favoriteTemperatures.contains(Int(temperature)) }

    private func applyFavoriteTemperature(_ value: Int) {
        temperature = Double(value)
        Task { await store.setTemperature(value, id: device.id) }
    }

    private func applyKelvinInput() {
        guard let value = Int(kelvinInput), (2200...6500).contains(value) else {
            kelvinInput = String(Int(temperature))
            return
        }
        temperature = Double(value)
        kelvinInput = String(value)
        Task { await store.setTemperature(value, id: device.id) }
    }

    private func isViableKelvinPrefix(_ candidate: String) -> Bool {
        guard candidate.count <= 4 else { return false }
        if candidate.count == 4 {
            return Int(candidate).map { (2200...6500).contains($0) } ?? false
        }
        return (2200...6500).contains { String($0).hasPrefix(candidate) }
    }
}

private struct NeutralModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.30))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.6))
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .frame(width: 19, height: 19)
                    .offset(x: isOn ? 9 : -9)
            }
            .frame(width: 40, height: 22)
        }
        .buttonStyle(.plain)
        .keyboardActivatable(Capsule()) { isOn.toggle() }
        .accessibilityLabel("Beyaz ve renkli mod")
        .accessibilityValue(isOn ? "Renkli" : "Beyaz")
    }
}

extension View {
    /// Tab focus, a visible ring and Space/Return activation for a custom button,
    /// independent of the system's keyboard-navigation setting.
    func keyboardActivatable<S: Shape>(_ shape: S, action: @escaping () -> Void) -> some View {
        modifier(KeyboardActivatable(shape: shape, action: action))
    }

    /// Tab focus and arrow-key stepping for a custom slider. Each step previews
    /// on the lamp; one commit follows once the keys go quiet.
    fileprivate func keyboardAdjustable(
        value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
        live: @escaping (Double) -> Void, commit: @escaping () -> Void
    ) -> some View {
        modifier(KeyboardAdjustable(value: value, range: range, step: step, live: live, commit: commit))
    }
}

/// Tracks whether the user is navigating with the keyboard, so focus rings
/// appear for Tab and arrow keys but not after a mouse click.
@MainActor @Observable
private final class KeyboardFocusTracker {
    static let shared = KeyboardFocusTracker()
    private(set) var isKeyboardNavigating = false
    @ObservationIgnored private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                let navigating = event.type == .keyDown
                if KeyboardFocusTracker.shared.isKeyboardNavigating != navigating {
                    KeyboardFocusTracker.shared.isKeyboardNavigating = navigating
                }
            }
            return event
        }
    }
}

extension View {
    /// Pointer feedback for small click targets such as favorite swatches.
    func hoverGrow(_ scale: CGFloat = 1.15) -> some View {
        modifier(HoverGrow(scale: scale))
    }

    /// Pointer feedback for toggles: a faint outline in the control's shape.
    func hoverOutline<S: Shape>(_ shape: S) -> some View {
        modifier(HoverOutline(shape: shape))
    }
}

private struct HoverGrow: ViewModifier {
    let scale: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct HoverOutline<S: Shape>: ViewModifier {
    let shape: S
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay(shape.stroke(Color.primary.opacity(isHovered ? 0.35 : 0), lineWidth: 1).allowsHitTesting(false))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct KeyboardFocusRing<S: Shape>: ViewModifier {
    let shape: S
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay(
                shape.stroke(Color.primary.opacity(0.55), lineWidth: 1.5)
                    .padding(-3)
                    .opacity(isFocused && KeyboardFocusTracker.shared.isKeyboardNavigating ? 1 : 0)
                    .allowsHitTesting(false)
            )
    }
}

private struct KeyboardActivatable<S: Shape>: ViewModifier {
    let shape: S
    let action: () -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .modifier(KeyboardFocusRing(shape: shape, isFocused: isFocused))
            .onKeyPress(keys: [.space, .return]) { _ in
                action()
                return .handled
            }
    }
}

private struct KeyboardAdjustable: ViewModifier {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let live: (Double) -> Void
    let commit: () -> Void
    @FocusState private var isFocused: Bool
    @State private var commitTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .modifier(KeyboardFocusRing(shape: Capsule(), isFocused: isFocused))
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let direction: Double = press.key == .leftArrow || press.key == .downArrow ? -1 : 1
                let next = min(range.upperBound, max(range.lowerBound, value + direction * step))
                guard next != value else { return .handled }
                value = next
                live(next)
                commitTask?.cancel()
                commitTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    commitTask = nil
                    commit()
                }
                return .handled
            }
            // Closing the panel mid-adjustment must still deliver the final value.
            .onDisappear {
                guard let pending = commitTask else { return }
                pending.cancel()
                commitTask = nil
                commit()
            }
    }
}

struct BrightnessSlider: View {
    @Binding var value: Double
    @State private var isDragging = false
    @State private var isHovered = false
    let activeColor: Color
    let commit: () -> Void
    let liveChange: (Double) -> Void
    var editingChanged: (Bool) -> Void = { _ in }
    var compact = false
    private let minimum = 10.0
    private let maximum = 100.0
    private var thumbSize: Double { compact ? 19 : 22 }

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - thumbSize)
            let progress = min(1, max(0, (value - minimum) / (maximum - minimum)))
            let thumbX = thumbSize / 2 + trackWidth * progress
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                    .frame(width: trackWidth, height: compact ? 6 : 8)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                LinearGradient(colors: [activeColor.opacity(0.18), activeColor.opacity(0.62), activeColor], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(4, trackWidth * progress), height: compact ? 6 : 8)
                    .clipShape(Capsule())
                    .position(x: thumbSize / 2 + (trackWidth * progress) / 2, y: geometry.size.height / 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .scaleEffect(isHovered || isDragging ? 1.12 : 1)
                    .animation(.easeOut(duration: 0.12), value: isHovered || isDragging)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            editingChanged(true)
                        }
                        let raw = min(1, max(0, (gesture.location.x - thumbSize / 2) / trackWidth))
                        value = (minimum + raw * (maximum - minimum)).rounded()
                        liveChange(value)
                    }
                    .onEnded { _ in
                        commit()
                        isDragging = false
                        editingChanged(false)
                    }
            )
        }
        .frame(height: compact ? 22 : 26)
        .keyboardAdjustable(value: $value, in: minimum...maximum, step: 5, live: liveChange, commit: commit)
        .accessibilityLabel("Parlaklık")
        .accessibilityValue("Yüzde \(Int(value))")
    }
}

private struct KelvinSlider: View {
    @Environment(LightStore.self) private var store
    @Binding var value: Double
    let commit: () -> Void
    let liveChange: (Double) -> Void
    private let minimum = 2200.0
    private let maximum = 6500.0
    private let thumbSize = 22.0

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - thumbSize)
            let thumbX = thumbSize / 2 + trackWidth * fraction(value)
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: whiteTemperatureColor(2200), location: 0),
                        .init(color: whiteTemperatureColor(3000), location: fraction(3000)),
                        .init(color: whiteTemperatureColor(4000), location: fraction(4000)),
                        .init(color: whiteTemperatureColor(6500), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: trackWidth, height: 8)
                .clipShape(Capsule())
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = min(1, max(0, (gesture.location.x - thumbSize / 2) / trackWidth))
                        var candidate = minimum + raw * (maximum - minimum)
                        candidate = (candidate / 25).rounded() * 25
                        // A firm detent that still leaves values 125 K from a favorite reachable.
                        if let favorite = nearestFavorite(to: candidate), abs(candidate - favorite) <= 100 {
                            candidate = favorite
                        }
                        value = candidate
                        liveChange(value)
                    }
                    .onEnded { _ in commit() }
            )
        }
        .frame(height: 26)
        .keyboardAdjustable(value: $value, in: minimum...maximum, step: 100, live: liveChange, commit: commit)
        .accessibilityLabel("Beyaz sıcaklığı")
        .accessibilityValue("\(Int(value)) Kelvin")
    }

    private func fraction(_ kelvin: Double) -> Double {
        min(1, max(0, (kelvin - minimum) / (maximum - minimum)))
    }

    private func nearestFavorite(to value: Double) -> Double? {
        store.favoriteTemperatures
            .map(Double.init)
            .min { abs($0 - value) < abs($1 - value) }
    }
}

private struct InlineColorControl: View {
    @Environment(LightStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Binding var color: Color
    let commit: (Color) -> Void
    let live: (Color) -> Void
    @State private var hue: Double
    @State private var saturation: Double
    @State private var hex: String
    @State private var externallySetHue: Double?

    init(color: Binding<Color>, commit: @escaping (Color) -> Void, live: @escaping (Color) -> Void) {
        _color = color
        self.commit = commit
        self.live = live
        let source = NSColor(color.wrappedValue).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        source.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        _hue = State(initialValue: Double(h))
        _saturation = State(initialValue: Double(s))
        _hex = State(initialValue: Self.hexString(color.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: MainLayout.controlSpacing) {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: MainLayout.controlIconWidth)
                ColorComponentSlider(value: $hue, colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]) {
                    saturation = 1
                    updateColor(commitChange: true)
                }
                // Keep the same trailing icon column used by brightness and Kelvin.
                Color.clear.frame(width: MainLayout.controlIconWidth)
            }
            .frame(height: MainLayout.controlHeight)
            HStack(spacing: 9) {
                Button { store.toggleFavoriteColor(hex) } label: {
                    Image(systemName: isFavoriteColor ? "heart.fill" : "heart").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .keyboardActivatable(Circle()) { store.toggleFavoriteColor(hex) }
                .foregroundStyle(.secondary)
                .disabled(!isFavoriteColor && !store.canAddFavoriteColor)
                .help(isFavoriteColor || store.canAddFavoriteColor ? "Favoriye ekle veya çıkar" : LightStore.fullFavoritesHelp)
                ForEach(store.favoriteColors.prefix(LightStore.maximumFavoritesPerKind), id: \.self) { value in
                    Circle().fill(Self.color(from: value) ?? .white).frame(width: 25, height: 25)
                        .overlay(
                            Circle().stroke(
                                Self.hexString(color).caseInsensitiveCompare(value) == .orderedSame ? Color.primary : .primary.opacity(0.15),
                                lineWidth: Self.hexString(color).caseInsensitiveCompare(value) == .orderedSame ? 1.5 : 1
                            )
                            .frame(
                                width: Self.hexString(color).caseInsensitiveCompare(value) == .orderedSame ? 28 : 25,
                                height: Self.hexString(color).caseInsensitiveCompare(value) == .orderedSame ? 28 : 25
                            )
                        )
                        .contentShape(Circle())
                        .onTapGesture { apply(hex: value, shouldCommit: true) }
                        .hoverGrow()
                        .keyboardActivatable(Circle()) { apply(hex: value, shouldCommit: true) }
                        .help("#\(value)")
                        .contextMenu { Button("Favoriden çıkar", role: .destructive) { store.removeFavoriteColor(value) } }
                }
                Spacer()
                Text("HEX").font(.caption.bold()).foregroundStyle(.secondary)
                ValidatedTextField(text: $hex, filter: { oldValue, value in
                    String(value.uppercased().filter { $0.isHexDigit }.prefix(6))
                }, onCommit: { apply(hex: hex, shouldCommit: true) })
                    .padding(.horizontal, 8)
                    .frame(width: 76, height: 22)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }
        }
        // A color applied elsewhere (menu bar, refresh) moves the slider and HEX
        // field without echoing a command back to the lamp.
        .onChange(of: color) { _, value in
            guard Self.hexString(value) != hex else { return }
            let source = NSColor(value).usingColorSpace(.deviceRGB) ?? .white
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            source.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            hex = Self.hexString(value)
            saturation = Double(s)
            if hue != Double(h) {
                externallySetHue = Double(h)
                hue = Double(h)
            }
        }
        .onChange(of: hue) { _, value in
            if value == externallySetHue {
                externallySetHue = nil
                return
            }
            saturation = 1
            if let snapped = snappedHue(value), circularDistance(value, snapped) > 0.0005 {
                hue = snapped
            } else {
                updateColor(commitChange: false, liveChange: true)
            }
        }
    }

    private var isFavoriteColor: Bool { store.favoriteColors.contains(hex.uppercased()) }

    private var favoriteComponents: [(hue: Double, saturation: Double)] {
        store.favoriteColors.compactMap { value in
            guard let favorite = Self.color(from: value) else { return nil }
            let source = NSColor(favorite).usingColorSpace(.deviceRGB) ?? .white
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            source.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return (Double(h), Double(s))
        }
    }

    private func snappedHue(_ value: Double) -> Double? {
        favoriteComponents
            .map { visualHueTarget($0.hue, near: value) }
            .filter { abs(value - $0) <= 0.018 }
            .min { abs(value - $0) < abs(value - $1) }
    }

    private func visualHueTarget(_ favorite: Double, near value: Double) -> Double {
        // Hue 0 and 1 are both red. Keep the detent at the end of the
        // visible slider that the pointer is actually approaching.
        if favorite <= 0.018 || favorite >= 0.982 {
            return value > 0.5 ? 1 : 0
        }
        return favorite
    }

    private func circularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let distance = abs(lhs - rhs)
        return min(distance, 1 - distance)
    }

    private func updateColor(commitChange: Bool, liveChange: Bool = false) {
        let value = spectrumColor(hue: hue, saturation: saturation)
        color = value
        hex = Self.hexString(value)
        if liveChange { live(value) }
        if commitChange { commit(value) }
    }

    private func apply(hex value: String, shouldCommit: Bool) {
        let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard clean.count == 6 else {
            hex = Self.hexString(color)
            return
        }
        guard let adjusted = Self.fullIntensityHex(clean), let selected = Self.color(from: adjusted) else {
            hex = Self.hexString(color)
            store.toast = "#\(clean) uygulanamadı: siyah bir renk değil, kapalı ışıktır"
            return
        }
        if adjusted != clean {
            store.toast = "#\(clean) → #\(adjusted) olarak uygulandı; koyuluğu parlaklıkla ayarlayın"
        }
        let source = NSColor(selected).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        source.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); saturation = Double(s); color = selected; hex = Self.hexString(selected)
        if shouldCommit { commit(selected) }
    }

    private static func hexString(_ color: Color) -> String {
        guard let value = NSColor(color).usingColorSpace(.sRGB) else { return "FFFFFF" }
        return String(format: "%02X%02X%02X", Int((value.redComponent * 255).rounded()), Int((value.greenComponent * 255).rounded()), Int((value.blueComponent * 255).rounded()))
    }

    private static func color(from hex: String) -> Color? {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    /// Brightness has its own slider, so a color always runs at full intensity:
    /// scale the channels until the strongest reaches 255. Black has no hue.
    private static func fullIntensityHex(_ hex: String) -> String? {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let channels = [(value >> 16) & 255, (value >> 8) & 255, value & 255]
        guard let peak = channels.max(), peak > 0 else { return nil }
        let scaled = channels.map { Int((Double($0) * 255 / Double(peak)).rounded()) }
        return String(format: "%02X%02X%02X", scaled[0], scaled[1], scaled[2])
    }
}

private struct ValidatedTextField: NSViewRepresentable {
    @Binding var text: String
    let filter: (_ oldValue: String, _ proposedValue: String) -> String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .default
        field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        context.coordinator.field = field
        context.coordinator.installOutsideClickMonitor()
        return field
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.removeOutsideClickMonitor()
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ValidatedTextField
        weak var field: NSTextField?
        private var outsideClickMonitor: Any?
        private var hasUserEdits = false

        init(_ parent: ValidatedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let accepted = parent.filter(parent.text, field.stringValue)
            if field.stringValue != accepted { field.stringValue = accepted }
            if accepted != parent.text { hasUserEdits = true }
            parent.text = accepted
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            commitUserEdits()
        }

        // Focus changes (including initial window activation) are not edits.
        // Clear the flag before committing so duplicate end-editing events cannot resend.
        private func commitUserEdits() {
            guard hasUserEdits else { return }
            hasUserEdits = false
            syncFieldValue()
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                syncFieldValue()
                control.window?.endEditing(for: nil)
                return true
            }
            return false
        }

        private func syncFieldValue() {
            guard let field else { return }
            let accepted = parent.filter(parent.text, field.stringValue)
            field.stringValue = accepted
            parent.text = accepted
        }

        func installOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let field = self.field, field.currentEditor() != nil else { return }
                    let fieldRectOnScreen: NSRect
                    if let window = field.window {
                        let rectInWindow = field.convert(field.bounds, to: nil)
                        fieldRectOnScreen = window.convertToScreen(rectInWindow)
                    } else {
                        return
                    }
                    if !fieldRectOnScreen.contains(NSEvent.mouseLocation) {
                        self.commitUserEdits()
                        field.abortEditing()
                        field.window?.makeFirstResponder(nil)
                    }
                }
                return event
            }
        }

        func removeOutsideClickMonitor() {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
        }
    }
}

private struct ColorComponentSlider: View {
    @Binding var value: Double
    let colors: [Color]
    let commit: () -> Void
    private let thumbSize = 22.0

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - thumbSize)
            let thumbX = thumbSize / 2 + trackWidth * min(1, max(0, value))
            ZStack(alignment: .leading) {
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .frame(width: trackWidth, height: 8).clipShape(Capsule())
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = min(1, max(0, (gesture.location.x - thumbSize / 2) / trackWidth))
                    }
                    .onEnded { _ in commit() }
            )
        }
        .frame(height: MainLayout.controlHeight)
        // 10° steps stay outside the 0.018 favorite detent, so a step can leave a snapped hue.
        // The parent previews hue changes itself.
        .keyboardAdjustable(value: $value, in: 0...1, step: 1.0 / 36, live: { _ in }, commit: commit)
    }
}

private func spectrumColor(hue: Double, saturation: Double) -> Color {
    let rgb = hsvRGB(hue: hue, saturation: saturation)
    return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
}

private func hsvRGB(hue: Double, saturation: Double) -> (r: Double, g: Double, b: Double) {
    let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let c = min(1, max(0, saturation))
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
    let rgb: (Double, Double, Double)
    switch h {
    case 0..<1: rgb = (c, x, 0)
    case 1..<2: rgb = (x, c, 0)
    case 2..<3: rgb = (0, c, x)
    case 3..<4: rgb = (0, x, c)
    case 4..<5: rgb = (x, 0, c)
    default: rgb = (c, 0, x)
    }
    let m = 1 - c
    return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
}

struct ToastView: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill").font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial, in: Capsule()).shadow(radius: 10)
    }
}
