import CoreLocation
import MapLibre
import UIKit

/// A camera position and how long to take getting there.
struct Leg {
    let center: CLLocationCoordinate2D
    let zoom: Double
    let pitch: CGFloat
    let heading: CLLocationDirection
    let duration: TimeInterval

    init(_ lat: Double, _ lon: Double, zoom: Double, pitch: CGFloat = 60, heading: CLLocationDirection, duration: TimeInterval = 0) {
        center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.zoom = zoom
        self.pitch = pitch
        self.heading = heading
        self.duration = duration
    }
}

/// One thing the example shows. Choosing it moves the camera and turns on the layers it needs.
enum Demo: String, CaseIterable, Identifiable {
    case peaks, relief, buildings, overlays, occlusion, heat, sky, loadModes, restyle, clamp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peaks: return "Peaks and basemap"
        case .relief: return "Hillshade and color relief"
        case .buildings: return "3D buildings"
        case .overlays: return "Draped overlays"
        case .occlusion: return "Labels behind ridges"
        case .heat: return "Heatmap and circles"
        case .sky: return "Sky and skirts"
        case .loadModes: return "Load modes and stats"
        case .restyle: return "Restyle on terrain"
        case .clamp: return "Camera follows the ground"
        }
    }

    var blurb: String {
        switch self {
        case .peaks: return "The Matterhorn. Peak symbols stand on the ground."
        case .relief: return "Mount Rainier. Terrain, hillshade and color relief share one elevation source."
        case .buildings: return "Innsbruck below the Nordkette. Buildings are raised onto the slope."
        case .overlays: return "Yosemite Valley. Made-up shapes and routes that follow the ground."
        case .occlusion: return "Labels that fall behind a ridge fade out. Sweep the view to watch."
        case .heat: return "OpenStreetMap peaks as a heatmap or circles. The ground hides them behind ridges."
        case .sky: return "The basemap is hidden, so the map is transparent over a gradient sky. Compare skirts Auto and None."
        case .loadModes: return "How much work each frame does while tiles load."
        case .restyle: return "Change basemap colors and the hillshade strength in place. The map does not move."
        case .clamp: return "Pan from the valley up over a ridge, with the camera following the ground or not."
        }
    }

    var camera: Leg {
        switch self {
        case .peaks: return Leg(45.9800, 7.6660, zoom: 12.7, heading: 225)
        case .relief: return Leg(46.8523, -121.7603, zoom: 11.2, heading: 25)
        case .buildings: return Leg(47.2800, 11.4020, zoom: 14.4, heading: 200)
        case .overlays: return Leg(37.7440, -119.5850, zoom: 12.0, heading: 30)
        case .occlusion: return Leg(45.9850, 7.7900, zoom: 11.3, heading: 262)
        case .heat: return Leg(46.0500, 7.7500, zoom: 11.0, heading: 200)
        case .sky: return Leg(45.9900, 7.7300, zoom: 12.2, heading: 225)
        case .loadModes: return Leg(45.9800, 7.6660, zoom: 12.7, heading: 225)
        case .restyle: return Leg(46.0140, 7.7480, zoom: 14.2, pitch: 55, heading: 215)
        case .clamp: return Leg(46.0150, 7.7550, zoom: 14.2, heading: 140)
        }
    }

    /// The layers (from `extras.json`) that are switched on for this demo.
    var layers: Set<String> {
        switch self {
        case .peaks, .occlusion, .sky, .loadModes, .clamp: return ["hillshade", "peaks"]
        case .relief: return ["hillshade", "color-relief", "peaks"]
        case .buildings: return ["hillshade", "buildings"]
        case .overlays: return Demo.overlayLayers.union(["hillshade"])
        case .heat: return ["hillshade"]
        case .restyle: return ["hillshade"]
        }
    }

    var exaggeration: Double { self == .relief ? 1.3 : (self == .clamp ? 2.5 : 1.5) }
    var hillshadeStrength: Double { self == .relief ? 0.5 : (self == .sky ? 0.8 : 0.3) }

    static let overlayLayers: Set<String> = ["zones-fill", "zones-outline", "trail", "valley-route", "waypoints", "waypoint-labels"]
    /// Every layer from `extras.json` that the app switches on and off.
    static let switchable: [String] = ["color-relief", "hillshade", "buildings", "peak-heat", "peak-circles", "peaks"]
        + Array(overlayLayers)
}

/// A set of basemap colors that the app applies in place, with no style reload.
enum Theme: String, CaseIterable, Identifiable {
    case kit = "Kit", dusk = "Dusk", sepia = "Sepia", mono = "Mono"
    var id: String { rawValue }

    /// Layer id to color. The layers are in the bundled basemap style. `nil` for `kit`, which restores the original.
    var colors: [String: UIColor]? {
        func c(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        switch self {
        case .kit: return nil
        case .dusk: return ["background": c(0x1b2230), "landcover": c(0x27384a), "park": c(0x2c4a45), "landuse": c(0x2a3040),
                            "water": c(0x0f3a5c), "waterway": c(0x2f6f9f), "road-casing": c(0x0e1218), "road": c(0xf2b36b),
                            "path": c(0xc98a5a), "building-flat": c(0x56607a)]
        case .sepia: return ["background": c(0xeadfc8), "landcover": c(0xd9c9a3), "park": c(0xc9c28f), "landuse": c(0xe0d2b4),
                             "water": c(0xa9b9b5), "waterway": c(0x8fa6a2), "road-casing": c(0x8a7457), "road": c(0xfff6df),
                             "path": c(0x7a5a3a), "building-flat": c(0xb89572)]
        case .mono: return ["background": c(0xf2f2f2), "landcover": c(0xe2e2e2), "park": c(0xd8d8d8), "landuse": c(0xe8e8e8),
                            "water": c(0xbfc6cc), "waterway": c(0xaab2b9), "road-casing": c(0x9a9a9a), "road": c(0xffffff),
                            "path": c(0x6a6a6a), "building-flat": c(0xb5b5b5)]
        }
    }
}

enum HeatMode: String, CaseIterable, Identifiable {
    case heatmap = "Heatmap", circles = "Circles", both = "Both"
    var id: String { rawValue }
}

/// Joins a base style and `extras.json` into one style JSON string.
enum StyleBuilder {
    static func bundledJSON(_ name: String) -> [String: Any] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// Adds the extras' sources, puts the draped layers under the first label layer and the rest on top.
    static func merged(base: [String: Any]) -> String {
        let extras = bundledJSON("extras")
        var style = base
        for key in ["center", "zoom", "pitch", "bearing", "terrain"] { style.removeValue(forKey: key) }

        var sources = style["sources"] as? [String: Any] ?? [:]
        for (key, value) in (extras["sources"] as? [String: Any] ?? [:]) where sources[key] == nil {
            sources[key] = value
        }
        style["sources"] = sources

        var layers = style["layers"] as? [[String: Any]] ?? []
        let firstSymbol = layers.firstIndex { ($0["type"] as? String) == "symbol" } ?? layers.count
        layers.insert(contentsOf: extras["draped"] as? [[String: Any]] ?? [], at: firstSymbol)
        layers.append(contentsOf: extras["top"] as? [[String: Any]] ?? [])
        style["layers"] = layers

        guard let data = try? JSONSerialization.data(withJSONObject: style),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
