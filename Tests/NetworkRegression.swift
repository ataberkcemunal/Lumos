import Foundation

/// Offline checks for telling "the Mac is on another network" apart from
/// "the lamp is off". Lamps use TEST-NET addresses that never answer.
@main
enum NetworkRegression {
    @MainActor
    static func main() async {
        let hotspot = LocalNetwork(address: ipv4Value("172.20.10.2")!, mask: ipv4Value("255.255.255.240")!)
        let home = LocalNetwork(address: ipv4Value("192.0.2.7")!, mask: ipv4Value("255.255.255.0")!)
        precondition(home.contains("192.0.2.200") && !home.contains("192.0.3.1"), "/24 membership")
        precondition(hotspot.contains("172.20.10.14") && !hotspot.contains("172.20.10.17"), "/28 membership")
        precondition(ipv4Value("192.168.1.256") == nil && ipv4Value("lamp") == nil, "Invalid addresses are rejected")

        let store = LightStore(client: WizClient(discover: { [] }))
        store.devices = [LightDevice(name: "Test", ip: "192.0.2.10", room: "", mac: "aabbccddeeff")]
        store.devices[0].isReachable = false

        store.localNetworks = { [hotspot] }
        await store.refreshAll(retry: true)
        precondition(store.isAwayFromLampNetwork, "No lamp answers and the Mac is on another network")
        precondition(store.status(for: store.devices[0])?.message == "Mac ev ağında değil", "Away status")
        precondition(store.lampNetworkHint == "192.0.2.x", "Network hint, got \(store.lampNetworkHint ?? "nil")")

        store.localNetworks = { [hotspot, home] }
        await store.refreshAll(retry: true)
        precondition(!store.isAwayFromLampNetwork, "On the lamps' network, an unanswered lamp is just unreachable")
        precondition(store.status(for: store.devices[0])?.message == "Bağlantı yok", "Plain unreachable status")
        print("PASS: network — away from the lamps' network is told apart from an unreachable lamp")
    }
}
