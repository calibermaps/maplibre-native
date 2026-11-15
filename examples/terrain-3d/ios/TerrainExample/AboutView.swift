import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Map data") {
                    Text("[© OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Roads, water, land cover, places and peaks come from OpenStreetMap, under the Open Database License.")
                    Text("Vector tiles, fonts and icons from [OpenFreeMap](https://openfreemap.org), in the [© OpenMapTiles](https://www.openmaptiles.org/) schema.")
                }
                Section("Elevation") {
                    Text("Terrain tiles from [Mapterhorn](https://mapterhorn.com/attribution). Around Zermatt they are built from swissALTI3D by the Federal Office of Topography swisstopo. The full list of source datasets is on Mapterhorn's [attribution page](https://mapterhorn.com/attribution).")
                }
                Section("Software") {
                    Text("Maps drawn by [MapLibre Native](https://github.com/maplibre/maplibre-native), © MapLibre contributors, BSD-2-Clause license. This app uses the feature/terrain-3d branch.")
                }
                Section {
                    Text("These are free community services, so please keep use light. The map's attribution button (i) shows the credits each data source asks for.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
