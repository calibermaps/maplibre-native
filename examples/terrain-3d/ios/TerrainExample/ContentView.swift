import SwiftUI

struct ContentView: View {
    @StateObject private var controller = MapController()
    @State private var sliderValue = 1.5

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                TerrainMapView(controller: controller)
                    .ignoresSafeArea(edges: .top)
                if let tap = controller.tap {
                    TapCard(result: tap) { controller.tap = nil }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
            controls
        }
        .sheet(isPresented: $controller.showAbout) { AboutView() }
        .onReceive(controller.$exaggeration) { sliderValue = $0 }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Toggle("3D terrain", isOn: Binding(get: { controller.terrainOn },
                                                set: { controller.setTerrain($0) }))
            HStack {
                Text("Exaggeration")
                Slider(value: $sliderValue, in: 0.5...4, step: 0.1) { editing in
                    // Commit when the finger lifts: each change rebuilds the terrain.
                    if !editing { controller.setExaggeration(sliderValue) }
                }
                .disabled(!controller.terrainOn)
                Text(String(format: "%.1f×", sliderValue))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            HStack {
                Button(controller.isFlying ? "Stop flyover" : "Start flyover") {
                    controller.toggleFlyover()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("About") { controller.showAbout = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

private struct TapCard: View {
    let result: TapResult
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.headline)
                Text(result.detail).font(.subheadline)
                Text(result.elevation).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
