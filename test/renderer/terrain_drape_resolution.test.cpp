#include <mln/test/util.hpp>
#include <mln/test/stub_file_source.hpp>
#include <mln/test/map_adapter.hpp>

#include <mln/gfx/headless_frontend.hpp>
#include <mln/map/bound_options.hpp>
#include <mln/map/camera.hpp>
#include <mln/map/map_options.hpp>
#include <mln/style/style.hpp>
#include <mln/util/constants.hpp>
#include <mln/util/image.hpp>
#include <mln/util/run_loop.hpp>

#include <cmath>
#include <numbers>
#include <string>

using namespace mln;

namespace {

// In Quality (the default load mode) the terrain mesh and its drape targets follow the view past the
// DEM source's maxzoom, so a low-maxzoom DEM does not soften the draped map. Flat ground from a DEM
// that stops at z9, under a raster of 2 px black and white stripes, seen straight down at zoom 16:
// the stripes must still be black and white on screen. A mesh held at the DEM's z9, or three levels
// past it at z12, drapes each 1024 px target over a tile 4096 px or more across in the view, and the
// stripes render as flat grey.
const char* drapeStyle = R"STYLE({
  "version": 8,
  "sources": {
    "dem": {
      "type": "raster-dem",
      "tiles": ["http://example.com/dem/{z}-{x}-{y}.png"],
      "encoding": "mapbox",
      "maxzoom": 9,
      "tileSize": 256
    },
    "stripes": {
      "type": "raster",
      "tiles": ["http://example.com/stripes/{z}-{x}-{y}.png"],
      "maxzoom": 22,
      "tileSize": 256
    }
  },
  "terrain": {"source": "dem", "exaggeration": 1.0},
  "layers": [{"id": "stripes", "type": "raster", "source": "stripes", "paint": {"raster-fade-duration": 0}}]
})STYLE";

std::string makeTile(bool dem, bool high = false, uint32_t stripe = 2) {
    PremultipliedImage image({256, 256});
    for (uint32_t y = 0; y < 256; ++y) {
        for (uint32_t x = 0; x < 256; ++x) {
            uint8_t* px = image.data.get() + (y * 256 + x) * 4;
            if (dem && high) {
                // 2,600 m in Terrain-RGB: (2600 + 10000) / 0.1 = 126000 = 1 * 65536 + 236 * 256 + 48
                px[0] = 1;
                px[1] = 236;
                px[2] = 48;
            } else if (dem) {
                // Sea level in Terrain-RGB: (0 + 10000) / 0.1 = 100000 = 1 * 65536 + 134 * 256 + 160
                px[0] = 1;
                px[1] = 134;
                px[2] = 160;
            } else {
                const uint8_t v = (x / stripe) % 2 ? 255 : 0;
                px[0] = px[1] = px[2] = v;
            }
            px[3] = 255;
        }
    }
    return encodePNG(image);
}

} // namespace

TEST(TerrainDrape, QualityFollowsTheViewPastTheDEMMaxzoom) {
    util::RunLoop loop;
    auto fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(), ClientOptions());
    const std::string demTile = makeTile(true);
    const std::string stripesTile = makeTile(false);
    fileSource->tileResponse = [&](const Resource& resource) {
        Response res;
        res.data = std::make_shared<std::string>(resource.url.find("/dem/") != std::string::npos ? demTile
                                                                                                 : stripesTile);
        return res;
    };
    HeadlessFrontend frontend{{256, 256}, 1};
    MapAdapter map(frontend,
                   MapObserver::nullObserver(),
                   fileSource,
                   MapOptions().withMapMode(MapMode::Static).withSize(frontend.getSize()));
    map.getStyle().loadJSON(drapeStyle);
    map.jumpTo(CameraOptions().withCenter(LatLng{46.0, 10.0}).withZoom(16.0).withPitch(0.0));

    PremultipliedImage image;
    for (int i = 0; i < 4; ++i) {
        loop.runOnce();
        image = frontend.render(map).image;
    }

    // In the middle 64 x 64 pixels, count the near-black and near-white ones: the stripes, when the
    // drape resolves them (an eighth each at least: pixels on a stripe edge come out grey). Blurred
    // into one another they are all mid grey.
    int dark = 0;
    int light = 0;
    for (uint32_t y = 96; y < 160; ++y) {
        for (uint32_t x = 96; x < 160; ++x) {
            const uint8_t r = image.data[(y * image.size.width + x) * 4];
            dark += r < 60 ? 1 : 0;
            light += r > 195 ? 1 : 0;
        }
    }
    EXPECT_GT(dark, 64 * 64 / 8) << "light " << light;
    EXPECT_GT(light, 64 * 64 / 8) << "dark " << dark;
}

namespace {

// A camera on the ground: a photo preview at a person's eye, 1.5 m over flat ground at 2,600 m,
// looking almost level with a 107 degree field of view, in the Balanced load mode. The view
// reaches to the horizon, so the cover runs from z20 under the camera to tiles thousands of
// kilometers away, over twice the Balanced cap. The ground in the bottom of the view is a few
// meters away and must show the z17 raster's 1 px stripes (0.9 m wide here). Merged down to the
// DEM's z13 to keep the far tiles (z14 under the camera, meshZoomForEveryDEMPixel), its drape has
// a texel per 2 to 4 m and the stripes are flat grey.
const char* groundEyeStyle = R"STYLE({
  "version": 8,
  "sources": {
    "dem": {
      "type": "raster-dem",
      "tiles": ["http://example.com/dem/{z}-{x}-{y}.png"],
      "encoding": "mapbox",
      "maxzoom": 13,
      "tileSize": 256
    },
    "stripes": {
      "type": "raster",
      "tiles": ["http://example.com/stripes/{z}-{x}-{y}.png"],
      "maxzoom": 17,
      "tileSize": 256
    }
  },
  "terrain": {"source": "dem", "exaggeration": 1.0},
  "layers": [{"id": "stripes", "type": "raster", "source": "stripes", "paint": {"raster-fade-duration": 0}}]
})STYLE";

} // namespace

TEST(TerrainDrape, AGroundEyeKeepsTheGroundBeforeItSharp) {
    util::RunLoop loop;
    auto fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(), ClientOptions());
    const std::string demTile = makeTile(true, true);
    const std::string stripesTile = makeTile(false, false, 1);
    fileSource->tileResponse = [&](const Resource& resource) {
        Response res;
        res.data = std::make_shared<std::string>(resource.url.find("/dem/") != std::string::npos ? demTile
                                                                                                 : stripesTile);
        return res;
    };
    constexpr uint32_t width = 390;
    constexpr uint32_t height = 844;
    HeadlessFrontend frontend{{width, height}, 1};
    MapAdapter map(frontend,
                   MapObserver::nullObserver(),
                   fileSource,
                   MapOptions().withMapMode(MapMode::Static).withSize(frontend.getSize()));
    map.getStyle().loadJSON(groundEyeStyle);
    map.setBounds(BoundOptions().withMaxPitch(179));
    map.setTerrainLoadMode(TerrainLoadMode::Balanced);

    // The center 33 m ahead on the ground, the eye 1.5 m over it: the zoom that puts the eye
    // there, as MLNMapView's eye camera works it out.
    constexpr double fieldOfView = 107.0;
    constexpr double ahead = 33.0;
    constexpr double eyeHeight = 1.5;
    constexpr double latitude = 38.5;
    const double metersPerPixelAtZ0 = util::EARTH_RADIUS_M * 2 * std::numbers::pi *
                                      std::cos(latitude * std::numbers::pi / 180) / util::tileSize_D;
    const double cameraToCenter = 0.5 * height / std::tan(fieldOfView * std::numbers::pi / 360);
    const double zoom = std::log2(cameraToCenter * metersPerPixelAtZ0 / std::hypot(ahead, eyeHeight));
    map.jumpTo(CameraOptions().withFov(fieldOfView));
    map.jumpTo(CameraOptions()
                   .withCenter(LatLng{latitude + ahead / 111320.0, -119.0})
                   .withCenterAltitude(2600.0)
                   .withZoom(zoom)
                   .withPitch(std::atan2(ahead, eyeHeight) * 180 / std::numbers::pi)
                   .withBearing(0.0));

    PremultipliedImage image;
    for (int i = 0; i < 4; ++i) {
        loop.runOnce();
        image = frontend.render(map).image;
    }

    // In the bottom 100 rows, the ground nearest the camera, count the near-black and near-white
    // pixels, as in QualityFollowsTheViewPastTheDEMMaxzoom.
    int dark = 0;
    int light = 0;
    for (uint32_t y = height - 100; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            const uint8_t r = image.data[(y * width + x) * 4];
            dark += r < 60 ? 1 : 0;
            light += r > 195 ? 1 : 0;
        }
    }
    EXPECT_GT(dark, static_cast<int>(width * 100 / 8)) << "light " << light;
    EXPECT_GT(light, static_cast<int>(width * 100 / 8)) << "dark " << dark;
}
