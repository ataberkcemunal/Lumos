// Live read-only integration test for the two configured home lamps.
import Foundation

@main struct Regression {
    static func main() async {
        precondition(normalizedMAC("98:77:D5:C8:90:F8") == "9877d5c890f8")
        precondition(normalizedMAC("invalid") == nil)
        let legacy = Data(#"{"result":{"state":true}}"#.utf8)
        precondition((try! JSONDecoder().decode(WizReply.self, from: legacy)).result?.mac == nil)
        let desk = await WizClient.shared.resolve(ip: "192.168.1.197", mac: "9877d5c890f8")
        precondition(desk?.ip == "192.168.1.196", "Stale address must recover by identity")
        let swapped = await WizClient.shared.resolve(ip: "192.168.1.195", mac: "9877d5c890f8")
        precondition(swapped?.ip == "192.168.1.196", "Must reject another lamp at the saved address")
        let unknown = await WizClient.shared.resolve(ip: "192.168.1.195", mac: "000000000000")
        precondition(unknown == nil, "Must not adopt an unrelated lamp")
        let learned = await WizClient.shared.resolve(ip: "192.168.1.196", mac: nil)
        precondition(normalizedMAC(learned?.state.mac) == "9877d5c890f8")
        print("PASS: normalization, legacy replies, stale IP recovery, reassigned IP safety, unknown identity, first identity learning")
    }
}
