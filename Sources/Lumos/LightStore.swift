import AppKit
import SwiftUI

struct ConnectionFeedback: Equatable {
    let message: String
    let isError: Bool
}

private struct RefreshTarget: Sendable {
    let id: UUID
    let ip: String
    let mac: String?
    let wasReachable: Bool
}

private struct RefreshResult: Sendable {
    let target: RefreshTarget
    let state: PilotState?
    let resolvedIP: String?
}

@MainActor @Observable
final class LightStore {
    var devices: [LightDevice]
    var isRefreshing = false
    var toast: String?
    var favoriteColors: [String] = []
    var favoriteTemperatures: [Int] = []
    var connectionFeedback: [UUID: ConnectionFeedback] = [:]
    private var lastBrightnessPreview: [UUID: TimeInterval] = [:]
    private var lastTemperaturePreview: [UUID: TimeInterval] = [:]
    private var lastColorPreview: [UUID: TimeInterval] = [:]
    private var consecutiveRefreshFailures: [UUID: Int] = [:]
    private let client: WizClient
    /// Uptime of each lamp's last confirmed MAC identity at its saved address.
    private var verifiedAt: [UUID: TimeInterval] = [:]
    private var commandTails: [UUID: Task<Bool, Never>] = [:]
    private var commandTickets: [UUID: Int] = [:]
    /// Commands queued or in flight, and when the last one was requested. A refresh
    /// must not overwrite a lamp the user changed while its query was out.
    private var pendingCommands: [UUID: Int] = [:]
    private var lastCommandRequest: [UUID: TimeInterval] = [:]
    /// Lamps switched on implicitly by a slider or swatch; the sound plays
    /// once a command to the lamp actually succeeds.
    private var powerOnSoundPending: Set<UUID> = []
    private static let identityLifetime: TimeInterval = 60

    init(client: WizClient = .shared) {
        self.client = client
        let saved = UserDefaults.standard.data(forKey: "lumos.devices")
            .flatMap { try? JSONDecoder().decode([LightDevice].self, from: $0) } ?? []
        let desk = saved.first { $0.name == "Çalışma Masası Lambası" }
        let room = saved.first { $0.name == "Oda Lambası" }
        devices = [
            LightDevice(
                id: desk?.id ?? UUID(), name: "Çalışma Masası Lambası", ip: desk?.ip ?? "192.168.1.196", room: "",
                mac: desk?.mac ?? "9877d5c890f8",
                isOn: desk?.isOn ?? false, brightness: desk?.brightness ?? 100,
                temperature: desk?.temperature ?? 3000, red: desk?.red ?? 255,
                green: desk?.green ?? 187, blue: desk?.blue ?? 110,
                sceneID: nil, speed: 100, isReachable: desk?.isReachable ?? true
            ),
            LightDevice(
                id: room?.id ?? UUID(), name: "Oda Lambası", ip: room?.ip ?? "192.168.1.195", room: "",
                mac: room?.mac ?? "d8a011732cf0",
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


    /// The connection message to show under a lamp's name, if any.
    func status(for device: LightDevice) -> ConnectionFeedback? {
        if let feedback = connectionFeedback[device.id] { return feedback }
        return device.isReachable ? nil : ConnectionFeedback(message: "Bağlantı yok", isError: true)
    }

    func persist() { if let data = try? JSONEncoder().encode(devices) { UserDefaults.standard.set(data, forKey: "lumos.devices") } }

    /// The menu bar row fits eight swatches in total; a card row fits five of
    /// one kind beside its input field. A full list never drops a favorite.
    static let maximumFavorites = 8
    static let maximumFavoritesPerKind = 5
    static let fullFavoritesHelp = "Favoriler dolu — eklemek için birini sağ tıklayıp çıkarın"

    private var hasFavoriteRoom: Bool { favoriteColors.count + favoriteTemperatures.count < Self.maximumFavorites }
    var canAddFavoriteColor: Bool { hasFavoriteRoom && favoriteColors.count < Self.maximumFavoritesPerKind }
    var canAddFavoriteTemperature: Bool { hasFavoriteRoom && favoriteTemperatures.count < Self.maximumFavoritesPerKind }

    func toggleFavoriteColor(_ hex: String) {
        let value = hex.uppercased()
        if let index = favoriteColors.firstIndex(of: value) { favoriteColors.remove(at: index) }
        else if canAddFavoriteColor { favoriteColors.append(value) }
        else { return }
        UserDefaults.standard.set(favoriteColors, forKey: "lumos.favoriteColors")
    }

    func toggleFavoriteTemperature(_ value: Int) {
        if let index = favoriteTemperatures.firstIndex(of: value) { favoriteTemperatures.remove(at: index) }
        else if canAddFavoriteTemperature { favoriteTemperatures.append(value) }
        else { return }
        favoriteTemperatures.sort()
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
        // An explicit power command plays its own sound below.
        powerOnSoundPending.subtract(targets)
        let previousStates = Dictionary(uniqueKeysWithValues: devices
            .filter { targets.contains($0.id) }
            .map { ($0.id, $0) })
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
        var successfulTargets: [UUID] = []
        for id in targets {
            let params: [String: JSONValue] = on
                ? ["state": .bool(true), "dimming": .int(100), "temp": .int(3000)]
                : ["state": .bool(false)]
            if await send(id: id, params: params, waitForAcknowledgement: true) {
                successfulTargets.append(id)
            } else if let previous = previousStates[id] {
                update(id) {
                    $0.isOn = previous.isOn
                    $0.brightness = previous.brightness
                    $0.temperature = previous.temperature
                    $0.isColorMode = previous.isColorMode
                    $0.sceneID = previous.sceneID
                }
            }
        }
        if !successfulTargets.isEmpty { playPowerSound(isOn: on) }
        persist()
    }

    func setBrightness(_ value: Int, id: UUID) async {
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.brightness = value; $0.sceneID = nil }
        if wasOff { powerOnSoundPending.insert(id) }
        await send(id: id, params: ["state": .bool(true), "dimming": .int(value)]); persist()
    }

    func previewBrightness(_ value: Int, id: UUID) async {
        guard shouldPreview(id: id, timestamps: &lastBrightnessPreview) else { return }
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.brightness = value; $0.sceneID = nil }
        if wasOff { powerOnSoundPending.insert(id) }
        await send(id: id, params: ["state": .bool(true), "dimming": .int(value)], isPreview: true)
    }

    func setTemperature(_ value: Int, id: UUID) async {
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.temperature = value; $0.sceneID = nil; $0.isColorMode = false }
        if wasOff { powerOnSoundPending.insert(id) }
        await send(id: id, params: ["state": .bool(true), "temp": .int(value)]); persist()
    }

    func previewTemperature(_ value: Int, id: UUID) async {
        guard shouldPreview(id: id, timestamps: &lastTemperaturePreview) else { return }
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.temperature = value; $0.sceneID = nil; $0.isColorMode = false }
        if wasOff { powerOnSoundPending.insert(id) }
        await send(id: id, params: ["state": .bool(true), "temp": .int(value)], isPreview: true)
    }

    func setColor(_ color: Color, id: UUID) async {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.red = r; $0.green = g; $0.blue = b; $0.sceneID = nil; $0.isColorMode = true }
        if wasOff { powerOnSoundPending.insert(id) }
        await send(id: id, params: ["state": .bool(true), "r": .int(r), "g": .int(g), "b": .int(b)]); persist()
    }

    func stageColorPreview(_ color: Color, id: UUID) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.red = r; $0.green = g; $0.blue = b; $0.sceneID = nil; $0.isColorMode = true }
        if wasOff { powerOnSoundPending.insert(id) }
    }

    func previewColor(_ color: Color, id: UUID) async {
        guard shouldPreview(id: id, timestamps: &lastColorPreview),
              let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
        let r = Int((srgb.redComponent * 255).rounded()), g = Int((srgb.greenComponent * 255).rounded()), b = Int((srgb.blueComponent * 255).rounded())
        let wasOff = devices.first(where: { $0.id == id })?.isOn == false
        update(id) { $0.isOn = true; $0.red = r; $0.green = g; $0.blue = b; $0.sceneID = nil; $0.isColorMode = true }
        if wasOff { powerOnSoundPending.insert(id) }
        await send(id: id, params: ["state": .bool(true), "r": .int(r), "g": .int(g), "b": .int(b)], isPreview: true)
    }

    /// A user-requested refresh (`retry`) rescans for missing lamps immediately
    /// instead of waiting out the discovery backoff.
    func refreshAll(retry: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; persist() }
        let startedAt = ProcessInfo.processInfo.systemUptime
        let targets = devices.map { RefreshTarget(id: $0.id, ip: $0.ip, mac: $0.mac, wasReachable: $0.isReachable) }
        let client = self.client
        let results = await withTaskGroup(of: RefreshResult.self, returning: [RefreshResult].self) { group in
            for target in targets {
                group.addTask {
                    let located = await client.resolve(ip: target.ip, mac: target.mac, ignoreBackoff: retry)
                    return RefreshResult(target: target, state: located?.state, resolvedIP: located?.ip)
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
                if let ip = response.resolvedIP { refreshedDevices[index].ip = ip }
                refreshedDevices[index].mac = normalizedMAC(result.mac)
                verifiedAt[response.target.id] = ProcessInfo.processInfo.systemUptime
                consecutiveRefreshFailures[response.target.id] = 0
                refreshedDevices[index].isReachable = true
                let id = response.target.id
                let changedDuringQuery = (pendingCommands[id] ?? 0) > 0 || (lastCommandRequest[id] ?? -.infinity) >= startedAt
                if !changedDuringQuery {
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
                }
                // A successful query also clears a stale "command failed" message.
                if !response.target.wasReachable || connectionFeedback[response.target.id]?.isError == true {
                    feedbackEvents.append((response.target.id, "Yeniden bağlandı", false, true))
                }
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

    /// Sends one command per lamp at a time, in request order. A queued preview
    /// is dropped once a newer command for the same lamp has been requested.
    @discardableResult
    private func send(
        id: UUID,
        params: [String: JSONValue],
        waitForAcknowledgement: Bool = false,
        isPreview: Bool = false
    ) async -> Bool {
        let ticket = (commandTickets[id] ?? 0) + 1
        commandTickets[id] = ticket
        lastCommandRequest[id] = ProcessInfo.processInfo.systemUptime
        pendingCommands[id, default: 0] += 1
        defer { pendingCommands[id, default: 1] -= 1 }
        let previous = commandTails[id]
        let command = Task { @MainActor [weak self] () -> Bool in
            _ = await previous?.value
            guard let self, !isPreview || self.commandTickets[id] == ticket else { return false }
            return await self.deliver(id: id, params: params, waitForAcknowledgement: waitForAcknowledgement, isPreview: isPreview)
        }
        commandTails[id] = command
        return await command.value
    }

    private func deliver(
        id: UUID,
        params: [String: JSONValue],
        waitForAcknowledgement: Bool,
        isPreview: Bool
    ) async -> Bool {
        guard var device = devices.first(where: { $0.id == id }) else { return false }
        // Verify identity before writing: DHCP can assign the old IP to another
        // lamp. A recent confirmation is reused so each write costs one packet,
        // and previews never wait for a subnet scan.
        let lastVerified = verifiedAt[id] ?? -.infinity
        if ProcessInfo.processInfo.systemUptime - lastVerified > Self.identityLifetime {
            guard let located = await client.resolve(ip: device.ip, mac: device.mac, allowDiscovery: !isPreview) else {
                if !isPreview {
                    update(id) { $0.isReachable = false }
                    showFeedback(id: id, message: "Bağlantı yok", isError: true, autoHide: false)
                }
                return false
            }
            device.ip = located.ip
            verifiedAt[id] = ProcessInfo.processInfo.systemUptime
            update(id) { $0.ip = located.ip; $0.mac = normalizedMAC(located.state.mac) }
            persist()
        }
        let attemptCount = waitForAcknowledgement ? 2 : 1

        for attempt in 0..<attemptCount {
            do {
                let wasReachable = device.isReachable
                _ = try await client.command(
                    ip: device.ip,
                    method: "setPilot",
                    params: params,
                    expectsReply: waitForAcknowledgement
                )
                update(id) { $0.isReachable = true }
                if !wasReachable || connectionFeedback[id]?.isError == true {
                    showFeedback(id: id, message: "Yeniden bağlandı", isError: false, autoHide: true)
                }
                if powerOnSoundPending.remove(id) != nil { playPowerSound(isOn: true) }
                return true
            } catch {
                if attempt + 1 < attemptCount {
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
            }
        }

        // A single missed UDP acknowledgement should not label an otherwise
        // healthy lamp offline. Periodic getPilot refreshes own reachability;
        // the next write re-verifies identity in case the address moved.
        verifiedAt[id] = nil
        showFeedback(id: id, message: "Komut gönderilemedi", isError: true)
        toast = "\(device.name) komuta yanıt vermedi"
        return false
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
