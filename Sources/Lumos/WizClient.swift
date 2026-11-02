import Foundation
import Network
import Darwin

actor WizClient {
    static let shared = WizClient()
    private let port: NWEndpoint.Port = 38899

    /// Only a matching hardware identity may replace a saved address.
    func resolve(ip: String, mac: String?) async -> LocatedLight? {
        if let state = try? await command(ip: ip, method: "getPilot", expectsReply: true),
           state.state != nil, let identity = normalizedMAC(state.mac),
           mac == nil || normalizedMAC(mac) == identity {
            return LocatedLight(ip: ip, state: state)
        }
        guard let identity = normalizedMAC(mac) else { return nil }
        let lights = await Task.detached { discoverWizLights() }.value
        return lights.first { normalizedMAC($0.state.mac) == identity }
    }

    func command(ip: String, method: String, params: [String: JSONValue] = [:], expectsReply: Bool = false) async throws -> PilotState? {
        guard IPv4Address(ip) != nil else { throw WizError.invalidAddress }
        let data = try JSONEncoder().encode(WizRequest(method: method, params: params))
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .udp)
        defer { connection.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                gate.run { continuation.resume(throwing: WizError.timeout) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        gate.run {
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    })
                case .failed(let error): gate.run { continuation.resume(throwing: error) }
                case .cancelled: break
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        guard expectsReply else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            connection.receiveMessage { data, _, _, error in
                gate.run {
                    if let error { continuation.resume(throwing: error); return }
                    guard let data, let reply = try? JSONDecoder().decode(WizReply.self, from: data) else {
                        continuation.resume(returning: nil); return
                    }
                    continuation.resume(returning: reply.result)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.2) {
                gate.run { continuation.resume(throwing: WizError.timeout) }
            }
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func run(_ action: () -> Void) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        action()
    }
}

struct WizReply: Decodable, Sendable { let result: PilotState? }
struct WizRequest: Encodable, Sendable { let method: String; let params: [String: JSONValue] }
enum JSONValue: Encodable, Sendable {
    case bool(Bool), int(Int), string(String)
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .bool(let value): try container.encode(value); case .int(let value): try container.encode(value); case .string(let value): try container.encode(value) }
    }
}
struct PilotState: Decodable, Sendable {
    let mac: String?
    let state: Bool?
    let dimming: Int?
    let temp: Int?
    let r: Int?
    let g: Int?
    let b: Int?
    let sceneId: Int?
    let speed: Int?
}

enum WizError: LocalizedError {
    case invalidAddress, timeout
    var errorDescription: String? { switch self { case .invalidAddress: "Geçersiz IP adresi"; case .timeout: "Lambadan yanıt alınamadı" } }
}

struct LocatedLight: Sendable {
    let ip: String
    let state: PilotState
}

func normalizedMAC(_ value: String?) -> String? {
    guard let value else { return nil }
    let compact = value.lowercased().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
    guard compact.count == 12, compact.allSatisfy({ $0.isHexDigit }) else { return nil }
    return compact
}

/// Runs off the main actor; all sockets close after a bounded discovery window.
func discoverWizLights() -> [LocatedLight] {
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard fd >= 0 else { return [] }
    defer { close(fd) }
    var enabled: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0 else { return [] }
    var broadcasts: Set<String> = ["255.255.255.255"]
    var localAddresses: Set<String> = []
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    if getifaddrs(&interfaces) == 0 {
        defer { freeifaddrs(interfaces) }
        var current = interfaces
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let flags = entry.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_BROADCAST) != 0,
                  let address = entry.pointee.ifa_dstaddr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            // Some lamps ignore broadcast packets. Probe directly on small local
            // subnets as a fallback, never scanning unrelated or oversized networks.
            if let ownAddress = entry.pointee.ifa_addr, let netmask = entry.pointee.ifa_netmask,
               ownAddress.pointee.sa_family == UInt8(AF_INET) {
                let own = UnsafeRawPointer(ownAddress).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
                let mask = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr.bigEndian
                let hostMask = ~mask
                if hostMask > 1 && hostMask <= 1023 {
                    let network = own & mask
                    for host in 1..<hostMask where (network | host) != own {
                        let ip = network | host
                        localAddresses.insert("\(ip >> 24).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)")
                    }
                }
            }
            let ipv4 = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
            var addr = ipv4.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count)) != nil {
                broadcasts.insert(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
    }
    let request = Array(#"{"method":"getPilot","params":{}}"#.utf8)
    var found: [String: LocatedLight] = [:]
    for round in 0..<2 {
        for broadcast in (round == 0 ? broadcasts : localAddresses.union(broadcasts)) {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = UInt16(38899).bigEndian
            guard inet_pton(AF_INET, broadcast, &destination.sin_addr) == 1 else { continue }
            if round == 1 { usleep(2000) }
            _ = withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    request.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            var sender = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = withUnsafeMutablePointer(to: &sender) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    buffer.withUnsafeMutableBytes { recvfrom(fd, $0.baseAddress, $0.count, MSG_DONTWAIT, address, &length) }
                }
            }
            guard count > 0, sender.sin_port == UInt16(38899).bigEndian,
                  let reply = try? JSONDecoder().decode(WizReply.self, from: Data(buffer.prefix(count))),
                  let state = reply.result, state.state != nil, let mac = normalizedMAC(state.mac) else { continue }
            var address = sender.sin_addr
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &address, &text, socklen_t(text.count)) != nil {
                found[mac] = LocatedLight(ip: String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), state: state)
            }
        }
    }
    return Array(found.values)
}
