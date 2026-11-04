#include <mln/test/util.hpp>
#include <mln/test/stub_file_source.hpp>
#include <mln/test/map_adapter.hpp>

#include <mln/gfx/backend_scope.hpp>
#include <mln/gfx/headless_frontend.hpp>
#include <mln/map/camera.hpp>
#include <mln/map/map_options.hpp>
#include <mln/style/image.hpp>
#include <mln/style/style.hpp>
#include <mln/style/transition_options.hpp>
#include <mln/util/image.hpp>
#include <mln/util/run_loop.hpp>

#include <chrono>
#include <memory>
#include <string>
#include <thread>

using namespace mln;

namespace {

// Flat ground under a fill-pattern polygon that covers the whole view. The pattern is eight pixels
// across, four red and four blue: a different scale puts the stripes elsewhere, so a pixel says
// which scale it was drawn at.
const char* styleJSON = R"STYLE({
  "version": 8,
  "sources": {
    "dem": {
      "type": "raster-dem",
      "tiles": ["http://example.com/dem/{z}-{x}-{y}.png"],
      "encoding": "mapbox",
      "maxzoom": 11,
      "tileSize": 256
    },
    "ground": {
      "type": "geojson",
      "data": {
        "type": "Feature",
        "properties": {},
        "geometry": {
          "type": "Polygon",
          "coordinates": [[[9.9, 45.9], [10.1, 45.9], [10.1, 46.1], [9.9, 46.1], [9.9, 45.9]]]
        }
      }
    }
  },
  "terrain": {"source": "dem", "exaggeration": 1.0},
  "layers": [{"id": "ground", "type": "fill", "source": "ground",
              "paint": {"fill-pattern": "stripes", "fill-antialias": false}}]
})STYLE";

std::string demTile() {
    PremultipliedImage image({256, 256});
    for (uint32_t i = 0; i < 256 * 256; ++i) {
        uint8_t* px = image.data.get() + i * 4;
        px[0] = 1; // sea level in Terrain-RGB
        px[1] = 134;
        px[2] = 160;
        px[3] = 255;
    }
    return encodePNG(image);
}

std::unique_ptr<style::Image> stripes() {
    PremultipliedImage image({8, 8});
    for (uint32_t y = 0; y < 8; ++y) {
        for (uint32_t x = 0; x < 8; ++x) {
            uint8_t* px = image.data.get() + (y * 8 + x) * 4;
            px[0] = x < 4 ? 255 : 0;
            px[1] = 0;
            px[2] = x < 4 ? 0 : 255;
            px[3] = 255;
        }
    }
    return std::make_unique<style::Image>("stripes", std::move(image), 1.0f);
}

// A continuous map at `startZoom`, moved to `zoom` (across a whole zoom level when they differ), then
// drawn for `seconds` more; the last frame.
PremultipliedImage drawnAt(double startZoom, double zoom, double seconds, int fadeMs = 2500) {
    util::RunLoop loop;
    auto fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(), ClientOptions());
    const std::string dem = demTile();
    fileSource->tileResponse = [&](const Resource&) {
        Response res;
        res.data = std::make_shared<std::string>(dem);
        return res;
    };
    HeadlessFrontend frontend{{256, 256}, 1};
    MapAdapter map(frontend,
                   MapObserver::nullObserver(),
                   fileSource,
                   MapOptions().withMapMode(MapMode::Continuous).withSize(frontend.getSize()));
    map.getStyle().loadJSON(styleJSON);
    // A slow fade, so the frames of a slow software renderer stay inside it, as a phone's do inside 300 ms.
    map.getStyle().setTransitionOptions(style::TransitionOptions{std::chrono::milliseconds(fadeMs), std::nullopt, false});
    map.getStyle().addImage(stripes());
    const auto frames = [&](double forSeconds) {
        const auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(int(forSeconds * 1000));
        do {
            loop.runOnce();
            frontend.renderFrame();
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        } while (std::chrono::steady_clock::now() < end);
    };
    map.jumpTo(CameraOptions().withCenter(LatLng{46.0, 10.0}).withZoom(startZoom).withPitch(0.0));
    frames(1.5);
    if (zoom != startZoom) {
        map.jumpTo(CameraOptions().withCenter(LatLng{46.0, 10.0}).withZoom(zoom).withPitch(0.0));
        frames(seconds);
    }
    gfx::BackendScope guard{*frontend.getBackend()};
    return frontend.readStillImage();
}

int differing(const PremultipliedImage& a, const PremultipliedImage& b) {
    int count = 0;
    for (uint32_t y = 64; y < 192; ++y) {
        for (uint32_t x = 64; x < 192; ++x) {
            const uint8_t* pa = a.data.get() + (y * a.size.width + x) * 4;
            const uint8_t* pb = b.data.get() + (y * b.size.width + x) * 4;
            if (std::abs(int(pa[0]) - int(pb[0])) > 40 || std::abs(int(pa[2]) - int(pb[2])) > 40) ++count;
        }
    }
    return count;
}

} // namespace

// A pattern is drawn at two scales that cross-fade over the 300 ms after the view crosses a zoom level.
// A drape target keeps what it was baked with until its tiles change, so a target baked in those 300 ms
// kept the blend for good: the hatch of one tile was finer than its neighbours'.
TEST(TerrainDrape, APatternDrapedDuringAZoomLevelFadeSettlesOnTheFinalScale) {
    const PremultipliedImage settled = drawnAt(16.1, 16.1, 0.0); // never crossed a level: the final scale
    const PremultipliedImage crossed = drawnAt(15.9, 16.1, 5.0); // baked inside the fade, then frames to well past its end
    EXPECT_LT(differing(settled, crossed), 128 * 128 / 20);
}
