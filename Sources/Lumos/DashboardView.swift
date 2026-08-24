import SwiftUI

struct DashboardView: View {
    @Environment(LightStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HeaderView(title: greeting, subtitle: "Evinin atmosferini tek dokunuşla değiştir.")
                HeroCard()
                sectionTitle("Işıklar", action: "Tümünü Gör") { store.selection = .lights }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 16)], spacing: 16) {
                    ForEach(store.devices) { device in LightCard(device: device) }
                }
                sectionTitle("Hızlı Sahneler", action: "Tüm Sahneler") { store.selection = .scenes }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) { ForEach(wizScenes.prefix(5)) { SceneCard(scene: $0) } }
                }
            }.padding(.bottom, 20)
        }
    }

    private var greeting: String { Calendar.current.component(.hour, from: .now) < 18 ? "İyi günler" : "İyi akşamlar" }
    private func sectionTitle(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack { Text(text).font(.title2.bold()); Spacer(); Button(action, action: perform).buttonStyle(.plain).foregroundStyle(.purple) }
    }
}

struct HeaderView: View {
    let title: String, subtitle: String
    @Environment(LightStore.self) private var store
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 32, weight: .bold, design: .rounded)); Text(subtitle).foregroundStyle(.secondary) }
            Spacer()
            Button { Task { await store.refreshAll() } } label: { Image(systemName: "arrow.clockwise").rotationEffect(.degrees(store.isRefreshing ? 360 : 0)).animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing) }
                .buttonStyle(.bordered).clipShape(Circle()).disabled(store.isRefreshing)
        }
    }
}

struct HeroCard: View {
    @Environment(LightStore.self) private var store
    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().fill(.white.opacity(0.15)).frame(width: 92, height: 92)
                Image(systemName: store.allOn ? "lightbulb.led.fill" : "lightbulb.led").font(.system(size: 42)).foregroundStyle(.white).symbolEffect(.bounce, value: store.allOn)
            }
            VStack(alignment: .leading, spacing: 5) { Text(store.allOn ? "Her yer aydınlık" : "Işıklar hazır").font(.title2.bold()); Text("\(store.devices.count) ışık • \(store.onlineCount) çevrimiçi").foregroundStyle(.white.opacity(0.75)) }
            Spacer()
            Button { Task { await store.setPower(!store.allOn) } } label: { Label(store.allOn ? "Tümünü Kapat" : "Tümünü Aç", systemImage: "power").padding(.horizontal, 8) }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.purple).controlSize(.large)
        }
        .padding(26).foregroundStyle(.white)
        .background(LinearGradient(colors: [.purple, .indigo, .blue.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .purple.opacity(0.22), radius: 22, y: 10)
    }
}

struct LightCard: View {
    @Environment(LightStore.self) private var store
    let device: LightDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(device.isOn ? device.color.opacity(0.18) : Color.secondary.opacity(0.1)); Image(systemName: device.isOn ? "lightbulb.led.fill" : "lightbulb.led").font(.title2).foregroundStyle(device.isOn ? device.color : .secondary) }.frame(width: 50, height: 50)
                Spacer()
                Toggle("", isOn: Binding(get: { device.isOn }, set: { value in Task { await store.setPower(value, ids: [device.id]) } })).labelsHidden().toggleStyle(.switch).tint(.purple)
            }
            VStack(alignment: .leading, spacing: 3) { Text(device.name).font(.headline); Text("\(device.room) • \(device.ip)").font(.caption).foregroundStyle(.secondary) }
            HStack { Image(systemName: "sun.min.fill").foregroundStyle(.secondary); Slider(value: Binding(get: { Double(device.brightness) }, set: { value in Task { await store.setBrightness(Int(value), id: device.id) } }), in: 10...100); Text("\(device.brightness)%").font(.caption.monospacedDigit()).frame(width: 34) }
        }.padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }
}

struct SceneCard: View {
    @Environment(LightStore.self) private var store
    let scene: LightScene
    var body: some View {
        Button { Task { await store.applyScene(scene) } } label: {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: scene.symbol).font(.title2)
                Text(scene.name).font(.headline)
            }.frame(width: 120, alignment: .leading).padding(18).foregroundStyle(.white)
                .background(LinearGradient(colors: scene.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
