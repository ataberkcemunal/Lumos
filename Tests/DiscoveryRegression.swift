// Live read-only integration test for the two configured home lamps.
// Addresses are looked up by MAC first, so DHCP reassignments do not break it.
import Foundation

@main struct Regression {
    static func main() async {
        precondition(normalizedMAC("98:77:D5:C8:90:F8") == "9877d5c890f8")
        precondition(normalizedMAC("invalid") == nil)
        let legacy = Data(#"{"result":{"state":true}}"#.utf8)
        precondition((try! JSONDecoder().decode(WizReply.self, from: legacy)).result?.mac == nil)

        let deskMAC = "9877d5c890f8", roomMAC = "d8a011732cf0"
        let lights = await Task.detached { discoverWizLights() }.value
        guard let deskIP = lights.first(where: { normalizedMAC($0.state.mac) == deskMAC })?.ip,
              let roomIP = lights.first(where: { normalizedMAC($0.state.mac) == roomMAC })?.ip else {
            fatalError("Both lamps must be on the network: found \(lights.map { "\($0.ip) \($0.state.mac ?? "?")" })")
        }
        let staleIP = deskIP == "192.168.1.197" ? "192.168.1.198" : "192.168.1.197"

        let desk = await WizClient.shared.resolve(ip: staleIP, mac: deskMAC)
        precondition(desk?.ip == deskIP, "Stale address must recover by identity")
        let swapped = await WizClient.shared.resolve(ip: roomIP, mac: deskMAC)
        precondition(swapped?.ip == deskIP, "Must reject another lamp at the saved address")
        let unknown = await WizClient.shared.resolve(ip: roomIP, mac: "000000000000")
        precondition(unknown == nil, "Must not adopt an unrelated lamp")
        let learned = await WizClient.shared.resolve(ip: deskIP, mac: nil)
        precondition(normalizedMAC(learned?.state.mac) == deskMAC)
        print("PASS: normalization, legacy replies, stale IP recovery, reassigned IP safety, unknown identity, first identity learning (desk \(deskIP), room \(roomIP))")
    }
}
