import Foundation
import Network

actor WizClient {
    static let shared = WizClient()
    private let port: NWEndpoint.Port = 38899

    func command(ip: String, method: String, params: [String: JSONValue] = [:], expectsReply: Bool = false) async throws -> PilotState? {
        guard IPv4Address(ip) != nil else { throw WizError.invalidAddress }
        let data = try JSONEncoder().encode(WizRequest(method: method, params: params))
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .udp)
        defer { connection.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    })
                case .failed(let error): continuation.resume(throwing: error)
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
