import AppKit
import SwiftUI

struct ConnectionFeedback: Equatable {
    let message: String
    let isError: Bool
}

private struct RefreshTarget: Sendable {
    let id: UUID
    let ip: String
    let wasReachable: Bool
}

private struct RefreshResult: Sendable {
    let target: RefreshTarget
    let state: PilotState?
}

@MainActor @Observable
final class LightStore {
    var devices: [LightDevice]
    var selection: NavigationItem? = .home
    var selectedDeviceID: UUID?
    var isRefreshing = false
    var toast: String?
    var favoriteColors: [String] = []
    var favoriteTemperatures: [Int] = []
    var connectionFeedback: [UUID: ConnectionFeedback] = [:]
    private var lastBrightnessPreview: [UUID: TimeInterval] = [:]
    private var lastTemperaturePreview: [UUID: TimeInterval] = [:]
    private var lastColorPreview: [UUID: TimeInterval] = [:]
    private var consecutiveRefreshFailures: [UUID: Int] = [:]

    init() {
        let saved = UserDefaults.standard.data(forKey: "lumos.devices")
            .flatMap { try? JSONDecoder().decode([LightDevice].self, from: $0) } ?? []
        let desk = saved.first { $0.name == "Çalışma Masası Lambası" }
        let room = saved.first { $0.name == "Oda Lambası" }
        devices = [
            LightDevice(
                id: desk?.id ?? UUID(), name: "Çalışma Masası Lambası", ip: "192.168.1.197", room: "",
                isOn: desk?.isOn ?? false, brightness: desk?.brightness ?? 100,
                temperature: desk?.temperature ?? 3000, red: desk?.red ?? 255,
                green: desk?.green ?? 187, blue: desk?.blue ?? 110,
                sceneID: nil, speed: 100, isReachable: desk?.isReachable ?? true
            ),
            LightDevice(
                id: room?.id ?? UUID(), name: "Oda Lambası", ip: "192.168.1.196", room: "",
                isOn: room?.isOn ?? false, brightness: room?.brightness ?? 100,
                temperature: room?.temperature ?? 3000, red: room?.red ?? 255,
                green: room?.green ?? 187, blue: room?.blue ?? 110,
                sceneID: nil, speed: 100, isReachable: room?.isReachable ?? true
            )
        ]
        favoriteColors = Array((UserDefaults.standard.stringArray(forKey: "lumos.favoriteColors") ?? ["FFF83D", "63F33F", "1967FF", "F13B2D"]).suffix(5))
        favoriteTemperatures = Array((UserDefaults.standard.array(forKey: "lumos.favoriteTemperatures") as? [Int] ?? [2700, 3000, 4000, 6500]).suffix(5))
        persist()
    }

    var allOn: Bool { !devices.isEmpty && devices.allSatisfy(\.isOn) }
    var onlineCount: Int { devices.filter(\.isReachable).count }

    func persist() { if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: "lumos.devices") } }

    func add(name: String, ip: String, room: String) {
        devices.append(LightDevice(name: name, ip: ip, room: room)); persist()
    }

    func remove(_ device: LightDevice) { devices.removeAll { $0.id == device.id }; persist() }

    func toggleFavoriteColor(_ hex: String) {
        let value = hex.uppercased()
        if let index = favoriteColors.firstIndex(of: value) { favoriteColors.remove(at: index) }
        else { favoriteColors.append(value) }
        if favoriteColors.count > 5 { favoriteColors.removeFirst(favoriteColors.count - 5) }
        UserDefaults.standard.set(favoriteColors, forKey: "lumos.favoriteColors")
    }

    func toggleFavoriteTemperature(_ value: Int) {
        if let index = favoriteTemperatures.firstIndex(of: value) { favoriteTemperatures.remove(at: index) }
        else { favoriteTemperatures.append(value) }
        favoriteTemperatures.sort()
        if favoriteTemperatures.count > 5 { favoriteTemperatures.removeFirst(favoriteTemperatures.count - 5) }
        UserDefaults.standard.set(favoriteTemperatures, forKey: "lumos.favoriteTemperatures")
    }

    func removeFavoriteColor(_ value: String) {
        favoriteColors.removeAll { $0 == value }
        UserDefaults.standard.set(favoriteColors, forKey: "lumos.favoriteColors")
    }

    func removeFavoriteTemperature(_ value: Int) {
        favoriteTemperatures.removeAll { $0 == value }
        UserDefaults.standard.set(favoriteTemperatures, forKey: "lumos.favoriteTemperatures")
    }

    func setPower(_ on: Bool, ids: [UUID]? = nil) async {
        let targets = ids ?? devices.map(\.id)
        // Publish the requested power state once so the aggregate toggle never
        // walks through an intermediate mixed state while commands are sent.
        for index in devices.indices where targets.contains(devices[index].id) {
            devices[index].isOn = on
            if on {
                devices[index].brightness = 100
                devices[index].temperature = 3000
                devices[index].isColorMode = false
                devices[index].sceneID = nil
            }
        }
        persist()
        for id in targets {
            let params: [String: JSONValue] = on
                ? ["state": .bool(true), "dimming": .int(100), "temp": .int(3000)]
                : ["state": .bool(false)]
            await send(id: id, params: params)
        }
        playPowerSound(isOn: on)
        persist()
    }

    func setBrightness(_ value: Int, id: UUID) async {
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.brightness = value; $0.sceneID = nil }
        if wasOff { playPowerSound(isOn: true) }
        await send(id: id, params: ["state": .bool(true), "dimming": .int(value)]); persist()
    }

    func previewBrightness(_ value: Int, id: UUID) async {
        guard shouldPreview(id: id, timestamps: &lastBrightnessPreview) else { return }
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.brightness = value; $0.sceneID = nil }
        if wasOff { playPowerSound(isOn: true) }
        await send(id: id, params: ["state": .bool(true), "dimming": .int(value)])
    }

    func setTemperature(_ value: Int, id: UUID) async {
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.temperature = value; $0.sceneID = nil; $0.isColorMode = false }
        if wasOff { playPowerSound(isOn: true) }
        await send(id: id, params: ["state": .bool(true), "temp": .int(value)]); persist()
    }

    func previewTemperature(_ value: Int, id: UUID) async {
        guard shouldPreview(id: id, timestamps: &lastTemperaturePreview) else { return }
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.temperature = value; $0.sceneID = nil; $0.isColorMode = false }
        if wasOff { playPowerSound(isOn: true) }
        await send(id: id, params: ["state": .bool(true), "temp": .int(value)])
    }

    func setColor(_ color: Color, id: UUID) async {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.red = r; $0.green = g; $0.blue = b; $0.sceneID = nil; $0.isColorMode = true }
        if wasOff { playPowerSound(isOn: true) }
        await send(id: id, params: ["state": .bool(true), "r": .int(r), "g": .int(g), "b": .int(b)]); persist()
    }

    func stageColorPreview(_ color: Color, id: UUID) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.red = r; $0.green = g; $0.blue = b; $0.sceneID = nil; $0.isColorMode = true }
        if wasOff { playPowerSound(isOn: true) }
    }

    func previewColor(_ color: Color, id: UUID) async {
        guard shouldPreview(id: id, timestamps: &lastColorPreview),
              let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded()), g = Int((srgb.greenComponent * 255).rounded()), b = Int((srgb.blueComponent * 255).rounded())
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.red = r; $0.green = g; $0.blue = b; $0.sceneID = nil; $0.isColorMode = true }
        if wasOff { playPowerSound(isOn: true) }
        await send(id: id, params: ["state": .bool(true), "r": .int(r), "g": .int(g), "b": .int(b)])
    }

    func applyScene(_ scene: LightScene) async {
        for device in devices {
            await send(id: device.id, params: ["state": .bool(true), "sceneId": .int(scene.id), "speed": .int(device.speed)])
            update(device.id) { $0.isOn = true; $0.sceneID = scene.id }
        }
        toast = "\(scene.name) sahnesi etkin"; persist()
    }

    func setSpeed(_ value: Int, id: UUID) async {
        update(id) { $0.speed = value }
        await send(id: id, params: ["speed": .int(value)]); persist()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; persist() }
        let targets = devices.map { RefreshTarget(id: $0.id, ip: $0.ip, wasReachable: $0.isReachable) }
        let results = await withTaskGroup(of: RefreshResult.self, returning: [RefreshResult].self) { group in
            for target in targets {
                group.addTask {
                    var state: PilotState?
                    for attempt in 0..<2 {
                        state = try? await WizClient.shared.command(ip: target.ip, method: "getPilot", expectsReply: true)
                        if state != nil { break }
                        if attempt == 0 { try? await Task.sleep(for: .milliseconds(120)) }
                    }
                    return RefreshResult(target: target, state: state)
                }
            }
            var collected: [RefreshResult] = []
            for await result in group { collected.append(result) }
            return collected
        }

        // Build a complete snapshot first. Publishing the array once prevents the
        // aggregate toggle from briefly stepping through off/mixed/on at launch.
        var refreshedDevices = devices
        var feedbackEvents: [(UUID, String, Bool, Bool)] = []
        for response in results {
            guard let index = refreshedDevices.firstIndex(where: { $0.id == response.target.id }) else { continue }
            if let result = response.state {
                consecutiveRefreshFailures[response.target.id] = 0
                refreshedDevices[index].isReachable = true
                refreshedDevices[index].isOn = result.state ?? refreshedDevices[index].isOn
                refreshedDevices[index].brightness = result.dimming ?? refreshedDevices[index].brightness
                refreshedDevices[index].temperature = result.temp ?? refreshedDevices[index].temperature
                refreshedDevices[index].red = result.r ?? refreshedDevices[index].red
                refreshedDevices[index].green = result.g ?? refreshedDevices[index].green
                refreshedDevices[index].blue = result.b ?? refreshedDevices[index].blue
                if result.r != nil || result.g != nil || result.b != nil { refreshedDevices[index].isColorMode = true }
                else if result.temp != nil { refreshedDevices[index].isColorMode = false }
                refreshedDevices[index].sceneID = result.sceneId
                refreshedDevices[index].speed = result.speed ?? refreshedDevices[index].speed
                if !response.target.wasReachable { feedbackEvents.append((response.target.id, "Yeniden bağlandı", false, true)) }
            } else {
                let failures = (consecutiveRefreshFailures[response.target.id] ?? 0) + 1
                consecutiveRefreshFailures[response.target.id] = failures
                if failures >= 3 {
                    refreshedDevices[index].isReachable = false
                    feedbackEvents.append((response.target.id, "Bağlantı yok", true, false))
                }
            }
        }
        if refreshedDevices != devices {
            devices = refreshedDevices
        }
        for event in feedbackEvents {
            showFeedback(id: event.0, message: event.1, isError: event.2, autoHide: event.3)
        }
    }

    private func send(id: UUID, params: [String: JSONValue]) async {
        guard let device = devices.first(where: { $0.id == id }) else { return }
        do {
            let wasReachable = device.isReachable
            _ = try await WizClient.shared.command(
                ip: device.ip,
                method: "setPilot",
                params: params
            )
            update(id) { $0.isReachable = true }
            if !wasReachable || connectionFeedback[id]?.isError == true {
                showFeedback(id: id, message: "Yeniden bağlandı", isError: false, autoHide: true)
            }
        } catch {
            update(id) { $0.isReachable = false }
            showFeedback(id: id, message: "Komut gönderilemedi", isError: true)
            toast = "\(device.name) erişilemiyor"
        }
    }

    private func update(_ id: UUID, _ body: (inout LightDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }; body(&devices[index])
    }

    private func shouldPreview(id: UUID, timestamps: inout [UUID: TimeInterval]) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - (timestamps[id] ?? 0) >= 0.08 else { return false }
        timestamps[id] = now
        return true
    }

    private func showFeedback(id: UUID, message: String, isError: Bool, autoHide: Bool = false) {
        let feedback = ConnectionFeedback(message: message, isError: isError)
        connectionFeedback[id] = feedback
        guard autoHide else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.connectionFeedback[id] == feedback { self?.connectionFeedback[id] = nil }
        }
    }

    private func playPowerSound(isOn: Bool) {
        let path = isOn ? "/System/Library/Sounds/Glass.aiff" : "/System/Library/Sounds/Blow.aiff"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
