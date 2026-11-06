#include <mln/test/util.hpp>
#include <mln/test/stub_file_source.hpp>
#include <mln/test/map_adapter.hpp>

#include <mln/gfx/headless_frontend.hpp>
#include <mln/map/camera.hpp>
#include <mln/map/map_options.hpp>
#include <mln/style/style.hpp>
#include <mln/util/image.hpp>
#include <mln/util/run_loop.hpp>

#include <memory>
#include <string>

using namespace mln;

namespace {

// A solid green background is the whole drape, so any pixel that is not exactly that green was
// shaded by the terrain pass itself.
const char* cliffStyle = R"STYLE({
  "version": 8,
  "sources": {
    "dem": {
      "type": "raster-dem",
      "tiles": ["http://example.com/dem/{z}-{x}-{y}.png"],
      "encoding": "mapbox",
      "maxzoom": 11,
      "tileSize": 256
    }
  },
  "terrain": {"source": "dem", "exaggeration": 1.0},
  "layers": [{"id": "ground", "type": "background", "paint": {"background-color": "rgb(0, 200, 0)"}}]
})STYLE";

constexpr uint32_t demSize = 256;
constexpr double faceTexel = 96.0; // west edge of the mesa, in texels of its DEM tile
constexpr int demTileX = 1080;     // z11 tile holding longitude 10 degrees

// Flat ground at sea level with a 1000 m mesa between texels 96 and 160 of every tile: a step
// of two texels (about 100 m) up 1000 m is steeper than 80 degrees. The same image answers every
// DEM request, so the mesa repeats tile after tile and the tile edges stay flat.
std::string cliffTile() {
    PremultipliedImage image({demSize, demSize});
    for (uint32_t y = 0; y < demSize; ++y) {
        for (uint32_t x = 0; x < demSize; ++x) {
            uint8_t* px = image.data.get() + (y * demSize + x) * 4;
            const bool mesa = x >= 96 && x < 160;
            // Terrain-RGB: (elevation + 10000) / 0.1 = 100000 (sea level) or 110000 (1000 m)
            px[0] = 1;
            px[1] = mesa ? 173 : 134;
            px[2] = mesa ? 176 : 160;
            px[3] = 255;
        }
    }
    return encodePNG(image);
}

PremultipliedImage renderCliff() {
    util::RunLoop loop;
    auto fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(), ClientOptions());
    const std::string dem = cliffTile();
    fileSource->tileResponse = [&](const Resource&) {
        Response res;
        res.data = std::make_shared<std::string>(dem);
        return res;
    };
    HeadlessFrontend frontend{{512, 512}, 1};
    MapAdapter map(frontend,
                   MapObserver::nullObserver(),
                   fileSource,
                   MapOptions().withMapMode(MapMode::Static).withSize(frontend.getSize()));
    map.getStyle().loadJSON(cliffStyle);

    // Stand west of the mesa, on the flat, and look east at its west face.
    const double faceLon = (demTileX + faceTexel / demSize) / 2048.0 * 360.0 - 180.0;
    map.jumpTo(CameraOptions().withCenter(LatLng{46.0, faceLon - 0.006}).withZoom(13.0).withBearing(90.0).withPitch(60.0));

    PremultipliedImage image;
    for (int i = 0; i < 4; ++i) {
        loop.runOnce();
        image = frontend.render(map).image;
    }
    return image;
}

} // namespace

// Ground steeper than about 60 degrees is a face the top-down drape only smears across, so the
// terrain pass fades it toward a lit rock tone; gentle ground keeps the drape untouched.
TEST(TerrainCliffShading, SteepFacesTakeTheRockToneAndFlatGroundKeepsTheDrape) {
    const PremultipliedImage image = renderCliff();
    const auto at = [&](uint32_t x, uint32_t y) { return image.data.get() + (y * image.size.width + x) * 4; };
    const auto drape = [&](uint32_t x, uint32_t y) {
        const uint8_t* px = at(x, y);
        return px[0] == 0 && px[1] == 200 && px[2] == 0 && px[3] == 255;
    };

    // Flat ground in the foreground (bottom of the view) is exactly the drape.
    int flat = 0;
    for (uint32_t y = 480; y < 512; ++y) {
        for (uint32_t x = 0; x < 512; ++x) flat += drape(x, y) ? 1 : 0;
    }
    EXPECT_EQ(flat, 32 * 512);

    // The face fills part of the view: its pixels are neither the drape green nor empty space,
    // and carry red, which the pure green drape has none of.
    int face = 0;
    for (uint32_t y = 0; y < 512; ++y) {
        for (uint32_t x = 0; x < 512; ++x) {
            const uint8_t* px = at(x, y);
            if (px[3] == 255 && px[0] > 30 && px[1] < 190) ++face;
        }
    }
    EXPECT_GT(face, 5000);
}
