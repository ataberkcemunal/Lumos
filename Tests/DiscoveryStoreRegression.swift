import Foundation
@main struct StoreRegression {
 @MainActor static func main() async {
   let store = LightStore()
   store.devices[0].ip = "192.168.1.197"
   await store.refreshAll()
   precondition(store.devices[0].ip == "192.168.1.196")
   precondition(store.devices.allSatisfy { $0.isReachable && $0.mac != nil })
   let restored = LightStore()
   precondition(restored.devices[0].ip == "192.168.1.196")
   precondition(restored.devices[0].mac == "9877d5c890f8")
   print("PASS: store recovers stale address, both lamps online, saved address and identity reload")
 }
}
