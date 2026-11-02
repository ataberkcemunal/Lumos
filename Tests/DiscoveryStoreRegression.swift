// Live read-only: the store recovers a stale address by MAC and persists it.
import Foundation
@main struct StoreRegression {
 @MainActor static func main() async {
   let lights = await Task.detached { discoverWizLights() }.value
   guard let deskIP = lights.first(where: { normalizedMAC($0.state.mac) == "9877d5c890f8" })?.ip else {
     fatalError("Desk lamp must be on the network")
   }
   let store = LightStore()
   store.devices[0].ip = deskIP == "192.168.1.197" ? "192.168.1.198" : "192.168.1.197"
   await store.refreshAll()
   precondition(store.devices[0].ip == deskIP)
   precondition(store.devices.allSatisfy { $0.isReachable && $0.mac != nil })
   let restored = LightStore()
   precondition(restored.devices[0].ip == deskIP)
   precondition(restored.devices[0].mac == "9877d5c890f8")
   print("PASS: store recovers stale address, both lamps online, saved address and identity reload")
 }
}
