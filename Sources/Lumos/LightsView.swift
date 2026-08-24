import SwiftUI

struct LightsView: View {
    @Environment(LightStore.self) private var store
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HeaderView(title: "Işıklar", subtitle: "Her ışığın tüm özelliklerini ayrı ayrı yönet.")
            HStack(spacing: 18) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.devices) { device in
                            Button { selectedID = device.id } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: device.isOn ? "lightbulb.fill" : "lightbulb").foregroundStyle(device.isOn ? device.color : .secondary).frame(width: 28)
                                    VStack(alignment: .leading) { Text(device.name).font(.headline); Text(device.ip).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Circle().fill(device.isReachable ? .green : .red).frame(width: 7, height: 7)
                                }.padding(15).background(selectedID == device.id ? Color.purple.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(width: 260)
                Divider()
                if let id = selectedID ?? store.devices.first?.id, let device = store.devices.first(where: { $0.id == id }) {
                    DeviceControls(device: device).id(device)
                } else { ContentUnavailableView("Henüz ışık yok", systemImage: "lightbulb.slash", description: Text("Sol alttaki + düğmesiyle bir cihaz ekleyin.")) }
            }
        }.onAppear { selectedID = selectedID ?? store.devices.first?.id }
    }
}

private struct DeviceControls: View {
    @Environment(LightStore.self) private var store
    let device: LightDevice
    @State private var draftBrightness: Double
    @State private var draftTemperature: Double
    @State private var draftColor: Color
    @State private var draftSpeed: Double

    init(device: LightDevice) {
        self.device = device
        _draftBrightness = State(initialValue: Double(device.brightness))
        _draftTemperature = State(initialValue: Double(device.temperature))
        _draftColor = State(initialValue: device.color)
        _draftSpeed = State(initialValue: Double(device.speed))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading) { Text(device.name).font(.title.bold()); Text(device.room).foregroundStyle(.secondary) }
                    Spacer(); Toggle("Güç", isOn: Binding(get: { device.isOn }, set: { value in Task { await store.setPower(value, ids: [device.id]) } })).toggleStyle(.switch).tint(.purple)
                }
                controlCard("Parlaklık", icon: "sun.max.fill") {
                    HStack { Slider(value: $draftBrightness, in: 10...100, step: 1) { editing in if !editing { Task { await store.setBrightness(Int(draftBrightness), id: device.id) } } }; Text("\(Int(draftBrightness))%").monospacedDigit().frame(width: 48) }
                }
                controlCard("Beyaz Sıcaklığı", icon: "thermometer.medium") {
                    VStack(spacing: 8) {
                        Slider(value: $draftTemperature, in: 2200...6500, step: 50) { editing in if !editing { Task { await store.setTemperature(Int(draftTemperature), id: device.id) } } }.tint(.orange)
                        HStack { Text("Sıcak"); Spacer(); Text("\(Int(draftTemperature)) K").monospacedDigit(); Spacer(); Text("Soğuk") }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                controlCard("Renk", icon: "paintpalette.fill") {
                    HStack { ColorPicker("Işık rengi", selection: $draftColor, supportsOpacity: false); Spacer(); Button("Uygula") { Task { await store.setColor(draftColor, id: device.id) } }.buttonStyle(.borderedProminent).tint(.purple) }
                }
                controlCard("Dinamik Sahne Hızı", icon: "speedometer") {
                    HStack { Slider(value: $draftSpeed, in: 10...200, step: 5) { editing in if !editing { Task { await store.setSpeed(Int(draftSpeed), id: device.id) } } }; Text("\(Int(draftSpeed))").monospacedDigit().frame(width: 42) }
                }
            }.padding(.horizontal, 6)
        }
    }

    private func controlCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Label(title, systemImage: icon).font(.headline); content() }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ScenesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HeaderView(title: "Sahneler", subtitle: "Hazır atmosferleri tüm ışıklara uygula.")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                    ForEach(wizScenes) { SceneCard(scene: $0).frame(maxWidth: .infinity) }
                }.padding(.bottom)
            }
        }
    }
}
