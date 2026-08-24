import SwiftUI

struct AddDeviceView: View {
    @Environment(LightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Yeni Işık"
    @State private var ip = "192.168.1."
    @State private var room = "Çalışma Odası"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Image(systemName: "lightbulb.led.fill").font(.largeTitle).foregroundStyle(.purple); VStack(alignment: .leading) { Text("Işık Ekle").font(.title2.bold()); Text("WiZ ışığının yerel IP adresini girin.").foregroundStyle(.secondary) } }
            Form { TextField("Ad", text: $name); TextField("IP adresi", text: $ip); TextField("Oda", text: $room) }
            HStack { Spacer(); Button("Vazgeç") { dismiss() }; Button("Ekle") { store.add(name: name, ip: ip, room: room); dismiss(); Task { await store.refreshAll() } }.buttonStyle(.borderedProminent).tint(.purple).disabled(name.isEmpty || ip.split(separator: ".").count != 4) }
        }.padding(28).frame(width: 440)
    }
}

struct SettingsView: View {
    @Environment(LightStore.self) private var store
    var body: some View {
        Form {
            Section("Cihazlar") {
                ForEach(store.devices) { device in
                    HStack { VStack(alignment: .leading) { Text(device.name); Text(device.ip).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { store.remove(device) } label: { Image(systemName: "trash") } }
                }
            }
            Section("Ağ") { Text("Lumos, WiZ ışıklarınızla yerel ağda UDP 38899 portu üzerinden doğrudan iletişim kurar.").font(.callout).foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 540, height: 400)
    }
}
