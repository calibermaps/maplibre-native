import SwiftUI
import MapLibre
import CoreLocation

/// What the last tap found.
struct TapResult: Equatable {
    var title: String
    var detail: String
    var elevation: String
}

/// One leg of the flyover.
struct Leg {
    let center: CLLocationCoordinate2D
    let zoom: Double
    let pitch: CGFloat
    let heading: CLLocationDirection
    let duration: TimeInterval
}

/// Owns the map view and everything the example does with it.
final class MapController: NSObject, ObservableObject, MLNMapViewDelegate {
    // Looking south-west from above Zermatt at the Matterhorn.
    static let start = Leg(center: CLLocationCoordinate2D(latitude: 45.9800, longitude: 7.6660),
                           zoom: 12.7, pitch: 60, heading: 225, duration: 2)
    static let terrainSourceID = "terrain-dem"
    static let tapLayers: Set<String> = ["peaks", "road", "road-names", "path"]

    @Published var terrainOn = true
    @Published var exaggeration = 1.5
    @Published var isFlying = false
    @Published var tap: TapResult?
    @Published var showAbout = false

    private weak var mapView: MLNMapView?
    private var styleLoaded = false
    private var flightToken = 0
    private let pin = MLNPointAnnotation()

    func attach(_ view: MLNMapView) {
        mapView = view
        // Keep the camera above the ground when it tilts over tall terrain.
        view.isCenterClampedToGround = true
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        // Let a double tap zoom without also reporting a tap.
        for recognizer in view.gestureRecognizers ?? [] {
            if let t = recognizer as? UITapGestureRecognizer, t.numberOfTapsRequired == 2 {
                tapRecognizer.require(toFail: t)
            }
        }
        view.addGestureRecognizer(tapRecognizer)
    }

    // MARK: Style

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        let firstLoad = !styleLoaded
        styleLoaded = true
        if firstLoad {
            let s = Self.start
            mapView.setCamera(makeCamera(mapView, center: s.center, zoom: s.zoom,
                                         pitch: s.pitch, heading: s.heading), animated: false)
        }
        applyTerrain()
        if firstLoad { runDemoIfRequested() }
    }

    /// Sets or clears `MLNStyle.terrain`. Terrain objects are immutable, so a change of
    /// exaggeration sets a new one.
    private func applyTerrain() {
        guard styleLoaded, let style = mapView?.style else { return }
        if terrainOn {
            style.terrain = MLNTerrain(sourceIdentifier: Self.terrainSourceID,
                                       exaggeration: CGFloat(exaggeration))
        } else {
            style.terrain = nil
        }
    }

    // MARK: 2D and 3D

    /// Switches terrain on or off and tilts the camera to match.
    func setTerrain(_ on: Bool) {
        terrainOn = on
        applyTerrain()
        guard let mapView else { return }
        cancelFlight()
        let camera = makeCamera(mapView, center: mapView.centerCoordinate,
                                zoom: mapView.zoomLevel, pitch: on ? 60 : 0,
                                heading: mapView.direction)
        mapView.setCamera(camera, withDuration: 1.5,
                          animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                          completionHandler: nil)
    }

    func setExaggeration(_ value: Double) {
        exaggeration = value
        applyTerrain()
    }

    // MARK: Taps

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let mapView else { return }
        select(at: recognizer.location(in: mapView))
    }

    /// Reports what is under a point of the map view: a peak or road if there is one, and always
    /// the ground height.
    func select(at point: CGPoint) {
        guard let mapView else { return }
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

        var features = mapView.visibleFeatures(at: point, styleLayerIdentifiers: Self.tapLayers)
        if features.isEmpty {
            // Thin roads are hard to hit with a fingertip, so look a little wider.
            let box = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
            features = mapView.visibleFeatures(in: box, styleLayerIdentifiers: Self.tapLayers)
        }

        var title = "Ground"
        var detail = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        if let peak = features.first(where: { $0.attribute(forKey: "ele") != nil && $0.attribute(forKey: "class") as? String == "peak" })
            ?? features.first(where: { $0.attribute(forKey: "ele") != nil }) {
            title = text(peak, "name_en") ?? text(peak, "name") ?? "Peak"
            let ele = text(peak, "ele").map { ", listed at \($0) m" } ?? ""
            detail = "Peak\(ele)"
        } else if !features.isEmpty {
            let named = features.compactMap { text($0, "name_en") ?? text($0, "name") }.first
            let kind = features.compactMap { text($0, "class") }.first ?? "road"
            title = named ?? "Unnamed road"
            detail = "Road, class: \(kind)"
        }

        tap = TapResult(title: title, detail: detail, elevation: elevationText(at: coordinate))

        if pin.coordinate.latitude != 0 { mapView.removeAnnotation(pin) }
        pin.coordinate = coordinate
        mapView.addAnnotation(pin)
    }

    private func text(_ feature: MLNFeature, _ key: String) -> String? {
        switch feature.attribute(forKey: key) {
        case let s as String where !s.isEmpty: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// `terrainElevation(at:)` returns meters with the exaggeration applied,
    /// so divide it out to show the true ground height.
    private func elevationText(at coordinate: CLLocationCoordinate2D) -> String {
        guard terrainOn else { return "Turn terrain on to read the ground height" }
        guard let drawn = mapView?.terrainElevation(at: coordinate)?.doubleValue else {
            return "Ground height not loaded yet"
        }
        let factor = max(exaggeration, 0.001)
        return String(format: "Ground %.0f m (drawn at %.0f m, %.1f× exaggeration)",
                      drawn / factor, drawn, exaggeration)
    }

    // MARK: Flyover

    /// A scripted tour: down the Mattertal toward Täsch, a turn to look back, then up to
    /// Zermatt and the Matterhorn, and home.
    private let tour: [Leg] = [
        Leg(center: CLLocationCoordinate2D(latitude: 46.0330, longitude: 7.7480), zoom: 14.0, pitch: 60, heading: 20, duration: 4),
        Leg(center: CLLocationCoordinate2D(latitude: 46.0720, longitude: 7.7800), zoom: 13.4, pitch: 58, heading: 25, duration: 7),
        Leg(center: CLLocationCoordinate2D(latitude: 46.0720, longitude: 7.7800), zoom: 12.2, pitch: 50, heading: 200, duration: 6),
        Leg(center: CLLocationCoordinate2D(latitude: 46.0100, longitude: 7.7400), zoom: 13.4, pitch: 60, heading: 215, duration: 8),
        MapController.start,
    ]

    func toggleFlyover() {
        if isFlying {
            cancelFlight()
        } else {
            startFlyover()
        }
    }

    private func startFlyover() {
        guard let mapView else { return }
        if !terrainOn {
            terrainOn = true
            applyTerrain()
        }
        flightToken += 1
        isFlying = true
        fly(mapView, leg: 0, token: flightToken)
    }

    private func fly(_ mapView: MLNMapView, leg index: Int, token: Int) {
        guard token == flightToken, index < tour.count else {
            if token == flightToken { isFlying = false }
            return
        }
        let leg = tour[index]
        let camera = makeCamera(mapView, center: leg.center, zoom: leg.zoom,
                                pitch: leg.pitch, heading: leg.heading)
        mapView.setCamera(camera, withDuration: leg.duration,
                          animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut)) { [weak self, weak mapView] in
            guard let self, let mapView else { return }
            self.fly(mapView, leg: index + 1, token: token)
        }
    }

    /// Stops a flight in progress by holding the camera where it is.
    private func cancelFlight() {
        guard isFlying, let mapView else { return }
        flightToken += 1
        isFlying = false
        mapView.setCamera(mapView.camera, animated: false)
    }

    // MARK: Helpers

    private func makeCamera(_ mapView: MLNMapView, center: CLLocationCoordinate2D, zoom: Double,
                            pitch: CGFloat, heading: CLLocationDirection) -> MLNMapCamera {
        let altitude = MLNAltitudeForZoomLevel(zoom, pitch, center.latitude, mapView.bounds.size)
        return MLNMapCamera(lookingAtCenter: center, altitude: altitude, pitch: pitch, heading: heading)
    }
}

// MARK: Scripted states

extension MapController {
    /// Launching with `-demo <name>` puts the app in one state after the map has loaded, so the
    /// preview pictures can be reproduced without touching the screen. Names: `2d-3d` (the
    /// switch, both ways), `exaggeration`, `tap-peak`, `tap-road`, `about`, `attribution`, `flyover`.
    /// Normal launches do not use this.
    fileprivate func runDemoIfRequested() {
        guard let name = UserDefaults.standard.string(forKey: "demo") else { return }
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        switch name {
        case "2d-3d":
            after(10) { self.setTerrain(false) }
            after(16) { self.setTerrain(true) }
        case "exaggeration":
            after(10) { self.setExaggeration(3.5) }
        case "tap-peak":
            after(12) { self.select(at: CGPoint(x: 215, y: 233)) }
        case "tap-road":
            if let mapView {
                let z = Leg(center: CLLocationCoordinate2D(latitude: 46.0207, longitude: 7.7491),
                            zoom: 13.2, pitch: 60, heading: 225, duration: 0)
                mapView.setCamera(MLNMapCamera(lookingAtCenter: z.center,
                                               altitude: MLNAltitudeForZoomLevel(z.zoom, z.pitch, z.center.latitude, mapView.bounds.size),
                                               pitch: z.pitch, heading: z.heading), animated: false)
            }
            after(12) { self.select(at: CGPoint(x: 300, y: 480)) }
        case "attribution":
            after(8) { if let v = self.mapView { v.showAttribution(v.attributionButton) } }
        case "about":
            after(8) { self.showAbout = true }
        case "flyover":
            after(10) { self.toggleFlyover() }
        default:
            break
        }
    }
}
