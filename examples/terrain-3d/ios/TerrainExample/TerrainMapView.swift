import SwiftUI
import MapLibre

/// Wraps `MLNMapView` for SwiftUI. All map behavior lives in `MapController`.
struct TerrainMapView: UIViewRepresentable {
    let controller: MapController

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "style", withExtension: "json")
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = controller
        controller.attach(mapView)
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}
}
