import SwiftUI
import MapLibre

struct ContentView: View {
    @StateObject private var controller = MapController()
    @State private var exaggerationSlider = 1.5
    @State private var shadeSlider = 0.3

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // The sky shows through the map when the demo makes the map transparent.
                LinearGradient(colors: [Color(red: 0.25, green: 0.47, blue: 0.82), Color(red: 0.78, green: 0.88, blue: 0.97)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                TerrainMapView(controller: controller)
                    .ignoresSafeArea(edges: .top)
                VStack(spacing: 6) {
                    if let tap = controller.tap {
                        TapCard(result: tap) { controller.tap = nil }
                    }
                    if controller.statsOn {
                        StatsView(stats: controller.stats, mode: controller.loadMode)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            controls
        }
        .sheet(isPresented: $controller.showAbout) { AboutView() }
        .onReceive(controller.$exaggeration) { exaggerationSlider = $0 }
        .onReceive(controller.$hillshadeStrength) { shadeSlider = $0 }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    ForEach(Demo.allCases) { demo in
                        Button(demo.title) { controller.select(demo) }
                    }
                } label: {
                    Label(controller.demo.title, systemImage: "list.bullet")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.borderedProminent)
                Spacer(minLength: 4)
                Toggle("Stats", isOn: Binding(get: { controller.statsOn }, set: { controller.setStats($0) }))
                    .toggleStyle(.button)
                Button(controller.isFlying ? "Stop" : "Flyover") { controller.toggleFlyover() }
                    .buttonStyle(.bordered)
                Button("About") { controller.showAbout = true }
                    .buttonStyle(.bordered)
            }
            Text(controller.demo.blurb)
                .font(.footnote).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Toggle("3D terrain", isOn: Binding(get: { controller.terrainOn }, set: { controller.setTerrain($0) }))
            HStack {
                Text("Exaggeration")
                Slider(value: $exaggerationSlider, in: 0.5...4, step: 0.1) { editing in
                    // Commit when the finger lifts: each change rebuilds the terrain.
                    if !editing { controller.setExaggeration(exaggerationSlider) }
                }
                .disabled(!controller.terrainOn)
                Text(String(format: "%.1f×", exaggerationSlider)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Divider()
            demoControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func layerToggle(_ title: String, _ ids: Set<String>) -> some View {
        Toggle(title, isOn: Binding(get: { controller.isOn(ids) }, set: { controller.set(ids, on: $0) }))
    }

    private var shadeRow: some View {
        HStack {
            Text("Hillshade")
            Slider(value: $shadeSlider, in: 0...1) { editing in
                if !editing { controller.setHillshadeStrength(shadeSlider) }
            }
            Text(String(format: "%.1f", shadeSlider)).monospacedDigit().frame(width: 30, alignment: .trailing)
        }
    }

    @ViewBuilder private var demoControls: some View {
        switch controller.demo {
        case .peaks:
            layerToggle("Peak symbols", ["peaks"])
        case .relief:
            layerToggle("Hillshade", ["hillshade"])
            layerToggle("Color relief", ["color-relief"])
            shadeRow
        case .buildings:
            layerToggle("Buildings", ["buildings"])
        case .overlays:
            layerToggle("Overlays", Demo.overlayLayers)
        case .occlusion:
            Button(controller.isFlying ? "Stop" : "Sweep the view") { controller.isFlying ? controller.toggleFlyover() : controller.sweep() }
                .buttonStyle(.borderedProminent)
        case .heat:
            Picker("Layer", selection: Binding(get: { controller.heatMode }, set: { controller.setHeatMode($0) })) {
                ForEach(HeatMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        case .sky:
            Toggle("Sky (transparent map)", isOn: Binding(get: { controller.skyOn }, set: { controller.setSky($0) }))
            Picker("Skirts", selection: Binding(get: { controller.skirtsNone }, set: { controller.setSkirts(none: $0) })) {
                Text("Skirts: Auto").tag(false)
                Text("Skirts: None").tag(true)
            }
            .pickerStyle(.segmented)
        case .loadModes:
            Picker("Load mode", selection: Binding(get: { controller.loadMode }, set: { controller.setLoadMode($0) })) {
                Text("Quality").tag(MLNTerrainLoadMode.quality)
                Text("Balanced").tag(MLNTerrainLoadMode.balanced)
                Text("Performance").tag(MLNTerrainLoadMode.performance)
            }
            .pickerStyle(.segmented)
            Button(controller.isFlying ? "Stop" : "Move over new ground") { controller.isFlying ? controller.toggleFlyover() : controller.sweep() }
                .buttonStyle(.borderedProminent)
        case .restyle:
            Picker("Colors", selection: Binding(get: { controller.theme }, set: { controller.setTheme($0) })) {
                ForEach(Theme.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            shadeRow
        case .clamp:
            Toggle("Camera follows the ground", isOn: Binding(get: { controller.clamped }, set: { controller.setClamped($0) }))
            Button(controller.isFlying ? "Stop" : "Pan across the valley") { controller.isFlying ? controller.toggleFlyover() : controller.panAcrossValley() }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct StatsView: View {
    let stats: Stats
    let mode: MLNTerrainLoadMode

    private var modeName: String {
        switch mode {
        case .quality: return "Quality"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        @unknown default: return "?"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Load mode \(modeName)")
            Text(String(format: "%.0f frames/s, %d draw calls", stats.framesPerSecond, stats.drawCalls))
            Text("Deferred: \(stats.drapesDeferred) drapes, \(stats.tileBuildsDeferred) tile builds")
            Text("Cover retries \(stats.coverPendingFrames), textures \(stats.textures) (\(stats.textureMegabytes) MB)")
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
