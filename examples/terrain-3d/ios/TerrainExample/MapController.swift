import SwiftUI
import MapLibre
import CoreLocation

/// What the last tap found.
struct TapResult: Equatable {
    var title: String
    var detail: String
    var elevation: String
}

/// The counters shown by the stats overlay.
struct Stats: Equatable {
    var framesPerSecond = 0.0
    var drawCalls = 0
    var drapesDeferred = 0
    var tileBuildsDeferred = 0
    var coverPendingFrames = 0
    var textures = 0
    var textureMegabytes = 0
}

/// Owns the map view and everything the example does with it.
final class MapController: NSObject, ObservableObject, MLNMapViewDelegate {
    static let terrainSourceID = "dem"
    static let tapLayers: Set<String> = ["peaks", "road-hit", "road-names", "road", "path"]

    @Published var demo: Demo
    @Published var terrainOn = true
    @Published var exaggeration = 1.5
    @Published var isFlying = false
    @Published var tap: TapResult?
    @Published var showAbout = false
    @Published var visible: Set<String>
    @Published var hillshadeStrength = 0.3
    @Published var heatMode = HeatMode.heatmap
    @Published var skyOn = false
    @Published var skirtsNone = false
    @Published var loadMode = MLNTerrainLoadMode.quality
    @Published var clamped = true
    @Published var theme = Theme.kit
    @Published var statsOn = false
    @Published var stats = Stats()

    private weak var mapView: MLNMapView?
    private var styleLoaded = false
    private var flightToken = 0
    private let pin = MLNPointAnnotation()
    private var lastStatsTime = Date.distantPast
    private var lastFrameCount = 0
    /// The basemap's own colors, kept so `Theme.kit` can put them back.
    private var originalColors: [String: NSExpression] = [:]

    override init() {
        let launched = UserDefaults.standard.string(forKey: "demo").flatMap { Demo(rawValue: $0) } ?? .peaks
        demo = launched
        visible = launched.layers
        exaggeration = launched.exaggeration
        hillshadeStrength = launched.hillshadeStrength
        super.init()
    }

    func attach(_ view: MLNMapView) {
        mapView = view
        view.isCenterClampedToGround = clamped
        view.backgroundColor = .clear
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        // Let a double tap zoom without also reporting a tap.
        for recognizer in view.gestureRecognizers ?? [] {
            if let t = recognizer as? UITapGestureRecognizer, t.numberOfTapsRequired == 2 {
                tapRecognizer.require(toFail: t)
            }
        }
        view.addGestureRecognizer(tapRecognizer)
        // The delegate is set by now, so it hears about this style loading.
        view.styleJSON = StyleBuilder.merged(base: StyleBuilder.bundledJSON("style"))
    }

    // MARK: Style

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        let firstLoad = !styleLoaded
        styleLoaded = true
        applyTerrain()
        applyLayers()
        rememberOriginalColors()
        if firstLoad { placeFirstCamera() }
    }

    /// Puts the camera at the first demo once the map view has a size, then runs a launch script if there is one.
    private func placeFirstCamera() {
        guard let mapView, mapView.bounds.width > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.placeFirstCamera() }
            return
        }
        moveCamera(to: demo.camera, animated: false)
        runDemoIfRequested()
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

    /// Applies which layers are on, the hillshade strength and the sky.
    private func applyLayers() {
        guard styleLoaded, let style = mapView?.style else { return }
        var ids = visible
        if demo == .heat {
            ids.remove("peak-heat"); ids.remove("peak-circles")
            if heatMode != .circles { ids.insert("peak-heat") }
            if heatMode != .heatmap { ids.insert("peak-circles") }
        }
        for id in Demo.switchable {
            style.layer(withIdentifier: id)?.isVisible = ids.contains(id)
        }
        if let hill = style.layer(withIdentifier: "hillshade") as? MLNHillshadeStyleLayer {
            hill.hillshadeExaggeration = NSExpression(forConstantValue: hillshadeStrength)
        }
        // With the background and the basemap's fills hidden the map is transparent, and the sky
        // shows through everywhere the hillshade, roads and labels do not draw.
        for layer in style.layers where (layer is MLNBackgroundStyleLayer || layer is MLNFillStyleLayer)
            && !Demo.switchable.contains(layer.identifier) {
            layer.isVisible = !skyOn
        }
    }

    // MARK: Demos

    func select(_ next: Demo, animated: Bool = true) {
        cancelFlight()
        tap = nil
        if theme != .kit { setTheme(.kit) }
        skyOn = false
        setSkirts(none: false)
        demo = next
        visible = next.layers
        exaggeration = next.exaggeration
        hillshadeStrength = next.hillshadeStrength
        if next == .loadModes { statsOn = true; setStats(true) }
        terrainOn = true
        applyTerrain()
        applyLayers()
        if mapView != nil {
            moveCamera(to: next.camera, animated: animated)
        }
    }

    private func moveCamera(to leg: Leg, animated: Bool) {
        guard let mapView else { return }
        let camera = makeCamera(mapView, leg)
        if animated {
            mapView.fly(to: camera, withDuration: 3.5, completionHandler: nil)
        } else {
            mapView.setCamera(camera, animated: false)
        }
    }

    func isOn(_ ids: Set<String>) -> Bool { !ids.isDisjoint(with: visible) }

    func set(_ ids: Set<String>, on: Bool) {
        if on { visible.formUnion(ids) } else { visible.subtract(ids) }
        applyLayers()
    }

    // MARK: 2D and 3D

    /// Switches terrain on or off and tilts the camera to match.
    func setTerrain(_ on: Bool) {
        terrainOn = on
        applyTerrain()
        guard let mapView else { return }
        cancelFlight()
        let leg = Leg(mapView.centerCoordinate.latitude, mapView.centerCoordinate.longitude,
                      zoom: mapView.zoomLevel, pitch: on ? 60 : 0, heading: mapView.direction)
        mapView.setCamera(makeCamera(mapView, leg), withDuration: 1.5,
                          animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                          completionHandler: nil)
    }

    func setExaggeration(_ value: Double) {
        exaggeration = value
        applyTerrain()
    }

    func setHillshadeStrength(_ value: Double) {
        hillshadeStrength = value
        applyLayers()
    }

    func setHeatMode(_ mode: HeatMode) {
        heatMode = mode
        applyLayers()
    }

    func setSky(_ on: Bool) {
        skyOn = on
        applyLayers()
    }

    func setSkirts(none: Bool) {
        skirtsNone = none
        mapView?.terrainSkirtLength = none ? .none : .auto
    }

    func setLoadMode(_ mode: MLNTerrainLoadMode) {
        loadMode = mode
        mapView?.terrainLoadMode = mode
    }

    func setClamped(_ on: Bool) {
        clamped = on
        mapView?.isCenterClampedToGround = on
    }

    func setStats(_ on: Bool) {
        statsOn = on
        lastFrameCount = 0
        lastStatsTime = .distantPast
    }

    /// Changes the colors of the basemap layers while the map stays where it is. Each change is a paint
    /// property set on a layer that is already draped, so the drape re-renders in place.
    func setTheme(_ choice: Theme) {
        theme = choice
        guard let style = mapView?.style else { return }
        for id in ["background", "landcover", "park", "landuse", "water", "waterway", "road-casing", "road", "path", "building-flat"] {
            guard let layer = style.layer(withIdentifier: id) else { continue }
            let color = choice.colors?[id].map { NSExpression(forConstantValue: $0) } ?? originalColors[id]
            guard let color else { continue }
            switch layer {
            case let l as MLNBackgroundStyleLayer: l.backgroundColor = color
            case let l as MLNFillStyleLayer: l.fillColor = color
            case let l as MLNLineStyleLayer: l.lineColor = color
            default: break
            }
        }
    }

    private func rememberOriginalColors() {
        guard originalColors.isEmpty, let style = mapView?.style else { return }
        for id in ["background", "landcover", "park", "landuse", "water", "waterway", "road-casing", "road", "path", "building-flat"] {
            switch style.layer(withIdentifier: id) {
            case let l as MLNBackgroundStyleLayer: originalColors[id] = l.backgroundColor
            case let l as MLNFillStyleLayer: originalColors[id] = l.fillColor
            case let l as MLNLineStyleLayer: originalColors[id] = l.lineColor
            default: break
            }
        }
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

    // MARK: Camera tours

    /// A scripted tour: down the Mattertal toward Täsch, a turn to look back, then up to
    /// Zermatt and the Matterhorn, and home.
    private var flyoverLegs: [Leg] {
        [
            Leg(46.0330, 7.7480, zoom: 14.0, heading: 20, duration: 4),
            Leg(46.0720, 7.7800, zoom: 13.4, pitch: 58, heading: 25, duration: 7),
            Leg(46.0720, 7.7800, zoom: 12.2, pitch: 50, heading: 200, duration: 6),
            Leg(46.0100, 7.7400, zoom: 13.4, heading: 215, duration: 8),
            Demo.peaks.camera.withDuration(2),
        ]
    }

    /// A slow turn around one spot, so labels pass behind ridges.
    private var sweepLegs: [Leg] {
        let c = demo.camera
        return [
            Leg(c.center.latitude, c.center.longitude, zoom: c.zoom, heading: c.heading - 45, duration: 4),
            Leg(c.center.latitude + 0.02, c.center.longitude + 0.02, zoom: c.zoom, heading: c.heading + 50, duration: 5),
            c.withDuration(3),
        ]
    }

    /// Zooms out over new ground and back in, so tiles load while the camera moves.
    private var loadLegs: [Leg] {
        [
            Leg(46.0500, 7.7800, zoom: 10.8, heading: 200, duration: 2.5),
            Leg(45.9600, 7.6500, zoom: 13.2, heading: 250, duration: 2.5),
            Leg(46.0200, 7.8300, zoom: 12.0, heading: 150, duration: 2.5),
            Demo.loadModes.camera.withDuration(2.5),
        ]
    }

    /// From the valley floor at Zermatt up over the Gornergrat ridge and back.
    private var panLegs: [Leg] {
        [
            Leg(45.9840, 7.7850, zoom: 14.2, heading: 140, duration: 6),
            Leg(46.0150, 7.7550, zoom: 14.2, heading: 140, duration: 6),
        ]
    }

    func toggleFlyover() {
        if isFlying { cancelFlight() } else { run(flyoverLegs) }
    }

    func sweep() { run(demo == .loadModes ? loadLegs : sweepLegs) }
    func panAcrossValley() { run(panLegs) }

    private func run(_ legs: [Leg], done: (() -> Void)? = nil) {
        guard let mapView else { return }
        if !terrainOn { terrainOn = true; applyTerrain() }
        flightToken += 1
        isFlying = true
        fly(mapView, legs, 0, flightToken, done)
    }

    private func fly(_ mapView: MLNMapView, _ legs: [Leg], _ index: Int, _ token: Int, _ done: (() -> Void)?) {
        guard token == flightToken else { return }
        guard index < legs.count else {
            isFlying = false
            done?()
            return
        }
        let leg = legs[index]
        mapView.setCamera(makeCamera(mapView, leg), withDuration: leg.duration,
                          animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut)) { [weak self, weak mapView] in
            guard let self, let mapView else { return }
            self.fly(mapView, legs, index + 1, token, done)
        }
    }

    /// Stops a flight in progress by holding the camera where it is.
    private func cancelFlight() {
        guard isFlying, let mapView else { return }
        flightToken += 1
        isFlying = false
        mapView.setCamera(mapView.camera, animated: false)
    }

    private func makeCamera(_ mapView: MLNMapView, _ leg: Leg) -> MLNMapCamera {
        let altitude = MLNAltitudeForZoomLevel(leg.zoom, leg.pitch, leg.center.latitude, mapView.bounds.size)
        return MLNMapCamera(lookingAtCenter: leg.center, altitude: altitude, pitch: leg.pitch, heading: leg.heading)
    }

    // MARK: Rendering stats

    func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool, renderingStats: MLNRenderingStats) {
        guard statsOn else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastStatsTime)
        guard elapsed >= 0.5 else { return }
        var next = Stats()
        if lastStatsTime != .distantPast, elapsed < 5 {
            next.framesPerSecond = Double(Int(renderingStats.numFrames) - lastFrameCount) / elapsed
        }
        next.drawCalls = Int(renderingStats.numDrawCalls)
        next.drapesDeferred = Int(renderingStats.numDrapeTargetsDeferred)
        next.tileBuildsDeferred = Int(renderingStats.numNewTileBuildsDeferred)
        next.coverPendingFrames = Int(renderingStats.numTerrainCoverPendingFrames)
        next.textures = Int(renderingStats.numActiveTextures)
        next.textureMegabytes = Int(renderingStats.memTextures) / 1_048_576
        lastFrameCount = Int(renderingStats.numFrames)
        lastStatsTime = now
        DispatchQueue.main.async { self.stats = next }
    }
}

extension Leg {
    func withDuration(_ seconds: TimeInterval) -> Leg {
        Leg(center.latitude, center.longitude, zoom: zoom, pitch: pitch, heading: heading, duration: seconds)
    }
}

// MARK: Scripted states

extension MapController {
    /// Launching with `-demo <id>` opens that demo, and `-sub <name>` then does one more thing after
    /// the map has loaded, so the preview pictures can be reproduced without touching the screen.
    /// Demo ids are the `Demo` cases. Sub names: `2d-3d`, `exaggeration`, `tap-peak`, `tap-road`,
    /// `about`, `attribution`, `flyover`, `sweep`, `sky`, `sky-auto`, `sky-none`, `stats`,
    /// `circles`, `both`, `modes-compare`, `styles`, `clamp-compare`, `dusk`, `sepia`, `mono`, `strong-shade`.
    /// Normal launches do not use this.
    fileprivate func runDemoIfRequested() {
        guard let name = UserDefaults.standard.string(forKey: "sub") ?? legacyDemoName() else { return }
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
            after(12) { self.select(at: CGPoint(x: 215, y: 200)) }
        case "tap-road":
            if let mapView { mapView.setCamera(makeCamera(mapView, Leg(46.0207, 7.7491, zoom: 13.2, heading: 225)), animated: false) }
            after(12) { self.select(at: CGPoint(x: 300, y: 436)) }
        case "about":
            after(8) { self.showAbout = true }
        case "attribution":
            after(8) { if let v = self.mapView { v.showAttribution(v.attributionButton) } }
        case "flyover":
            after(10) { self.toggleFlyover() }
        case "sweep":
            after(10) { self.sweep() }
        case "sky":
            after(8) { self.setSky(true) }
        case "sky-auto":
            after(8) { self.setSky(true); self.setSkirts(none: false) }
        case "sky-none":
            after(8) { self.setSky(true); self.setSkirts(none: true) }
        case "stats":
            after(8) { self.setStats(true) }
        case "modes-compare":
            after(8) { self.setStats(true); self.setLoadMode(.quality); self.run(self.loadLegs) {
                self.setLoadMode(.performance); self.run(self.loadLegs) } }
        case "styles":
            after(8) { self.setTheme(.dusk) }
            after(14) { self.setTheme(.sepia) }
            after(20) { self.setTheme(.mono) }
            after(26) { self.setTheme(.kit); self.setHillshadeStrength(0.9) }
            after(30) { self.setHillshadeStrength(0.1) }
        case "clamp-compare":
            // One pass with the clamp off, then the same pass with it on.
            after(8) {
                self.setClamped(false)
                self.run(self.panLegs) {
                    self.setClamped(true)
                    after(3) { self.run(self.panLegs) }
                }
            }
        case "circles": after(6) { self.setHeatMode(.circles) }
        case "both": after(6) { self.setHeatMode(.both) }
        case "dusk": after(6) { self.setTheme(.dusk) }
        case "sepia": after(6) { self.setTheme(.sepia) }
        case "mono": after(6) { self.setTheme(.mono) }
        case "strong-shade": after(6) { self.setHillshadeStrength(0.9) }
        default: break
        }
    }

    /// Older launch argument: `-demo <sub name>` when the value is not a demo id.
    private func legacyDemoName() -> String? {
        guard let value = UserDefaults.standard.string(forKey: "demo"), Demo(rawValue: value) == nil else { return nil }
        return value
    }
}
