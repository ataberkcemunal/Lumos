// Offline: a fake WiZ lamp on 127.0.0.1 and an injected discovery. No real lamps are contacted.
import Darwin
import Foundation

private final class FakeLamp: @unchecked Sendable {
    let mac = "aabbccddeeff"
    private let lock = NSLock()
    private var getPilots = 0
    private var dimmings: [Int] = []
    private let fd: Int32

    init() {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(38899).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        precondition(bound == 0, "127.0.0.1:38899 is busy")
        Thread.detachNewThread { [self] in serve() }
    }

    var snapshot: (getPilots: Int, dimmings: [Int]) {
        lock.lock(); defer { lock.unlock() }
        return (getPilots, dimmings)
    }

    private func serve() {
        while true {
            var buffer = [UInt8](repeating: 0, count: 2048)
            var sender = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    buffer.withUnsafeMutableBytes { recvfrom(fd, $0.baseAddress, $0.count, 0, address, &length) }
                }
            }
            guard count > 0,
                  let request = try? JSONSerialization.jsonObject(with: Data(buffer.prefix(count))) as? [String: Any],
                  let method = request["method"] as? String else { continue }
            let reply: String
            if method == "getPilot" {
                lock.lock(); getPilots += 1; lock.unlock()
                usleep(400_000)
                reply = #"{"method":"getPilot","result":{"mac":"\#(mac)","state":true,"dimming":50,"temp":3000}}"#
            } else {
                if let dimming = (request["params"] as? [String: Any])?["dimming"] as? Int {
                    lock.lock(); dimmings.append(dimming); lock.unlock()
                }
                reply = #"{"method":"setPilot","result":{"success":true}}"#
            }
            let bytes = Array(reply.utf8)
            _ = withUnsafePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, bytes, bytes.count, 0, $0, length) }
            }
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@main struct CommandPathRegression {
    @MainActor static func main() async {
        // Discovery: never for previews, shared by concurrent callers, backed off while missing.
        // 127.0.0.1 has no listener yet, so the direct identity check fails.
        let scans = Counter()
        let missing = WizClient(discover: { scans.increment(); usleep(300_000); return [] })
        let preview = await missing.resolve(ip: "127.0.0.1", mac: "aabbccddeeff", allowDiscovery: false)
        precondition(preview == nil)
        precondition(scans.count == 0, "Previews must not scan the subnet")
        async let first = missing.resolve(ip: "127.0.0.1", mac: "aabbccddeeff")
        async let second = missing.resolve(ip: "127.0.0.1", mac: "aabbccddeeff")
        _ = await (first, second)
        precondition(scans.count == 1, "Concurrent callers must share one scan, got \(scans.count)")
        _ = await missing.resolve(ip: "127.0.0.1", mac: "aabbccddeeff")
        precondition(scans.count == 1, "A missing lamp must back off before scanning again")

        let lamp = FakeLamp()
        let found = WizClient(discover: { [LocatedLight(ip: "127.0.0.1", state: PilotState(
            mac: "aabbccddeeff", state: true, dimming: nil, temp: nil, r: nil, g: nil, b: nil, sceneId: nil, speed: nil))] })
        let moved = await found.resolve(ip: "127.0.0.9", mac: "aabbccddeeff")
        precondition(moved?.ip == "127.0.0.1", "A moved lamp must still be recovered by identity")

        // Writes: identity checked once, commands reach the lamp in request order, final value wins.
        let store = LightStore(client: WizClient(discover: { scans.increment(); return [] }))
        store.devices = [LightDevice(name: "Test", ip: "127.0.0.1", room: "", mac: lamp.mac, isOn: true)]
        let id = store.devices[0].id
        var commands: [Task<Void, Never>] = []
        for value in [20, 30, 35] {
            commands.append(Task { await store.previewBrightness(value, id: id) })
            try? await Task.sleep(for: .milliseconds(90))
        }
        commands.append(Task { await store.setBrightness(40, id: id) })
        for command in commands { await command.value }
        let result = lamp.snapshot
        precondition(result.getPilots == 1, "Identity should be verified once, got \(result.getPilots)")
        // 20 waits on the slow identity check; 30 and 35 queue behind it and are superseded.
        precondition(result.dimmings == [20, 40], "Expected [20, 40], got \(result.dimmings)")
        precondition(scans.count == 1, "Writes to a reachable lamp must not scan")
        print("PASS: command path — no preview scans, shared/backed-off discovery, identity cached, ordered writes \(result.dimmings)")
    }
}
