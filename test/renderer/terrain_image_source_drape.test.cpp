#include <mln/test/util.hpp>
#include <mln/test/stub_file_source.hpp>
#include <mln/test/map_adapter.hpp>

#include <mln/gfx/headless_frontend.hpp>
#include <mln/map/camera.hpp>
#include <mln/map/map_options.hpp>
#include <mln/style/sources/image_source.hpp>
#include <mln/style/style.hpp>
#include <mln/util/image.hpp>
#include <mln/util/run_loop.hpp>

#include <array>
#include <memory>
#include <string>

using namespace mln;

namespace {

// Flat ground under an image source and a raster layer that cover the whole view.
const char* drapeStyle = R"STYLE({
  "version": 8,
  "sources": {
    "dem": {
      "type": "raster-dem",
      "tiles": ["http://example.com/dem/{z}-{x}-{y}.png"],
      "encoding": "mapbox",
      "maxzoom": 11,
      "tileSize": 256
    },
    "field": {
      "type": "image",
      "url": "http://example.com/unused.png",
      "coordinates": [[9.98, 46.02], [10.02, 46.02], [10.02, 45.98], [9.98, 45.98]]
    }
  },
  "terrain": {"source": "dem", "exaggeration": 1.0},
  "layers": [{"id": "field", "type": "raster", "source": "field", "paint": {"raster-fade-duration": 0}}]
})STYLE";

std::string demTile() {
    PremultipliedImage image({256, 256});
    for (uint32_t i = 0; i < 256 * 256; ++i) {
        uint8_t* px = image.data.get() + i * 4;
        // Sea level in Terrain-RGB: (0 + 10000) / 0.1 = 100000 = 1 * 65536 + 134 * 256 + 160
        px[0] = 1;
        px[1] = 134;
        px[2] = 160;
        px[3] = 255;
    }
    return encodePNG(image);
}

PremultipliedImage solid(uint8_t r, uint8_t g, uint8_t b) {
    PremultipliedImage image({8, 8});
    for (uint32_t i = 0; i < 8 * 8; ++i) {
        uint8_t* px = image.data.get() + i * 4;
        px[0] = r;
        px[1] = g;
        px[2] = b;
        px[3] = 255;
    }
    return image;
}

struct Rig {
    util::RunLoop loop;
    std::shared_ptr<StubFileSource> fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(),
                                                                                  ClientOptions());
    std::string dem = demTile();
    HeadlessFrontend frontend{{256, 256}, 1};
    MapAdapter map;

    explicit Rig(double pitch)
        : map(frontend,
              MapObserver::nullObserver(),
              (
                  fileSource->tileResponse =
                      [this](const Resource&) {
                          Response res;
                          res.data = std::make_shared<std::string>(dem);
                          return res;
                      },
                  fileSource),
              MapOptions().withMapMode(MapMode::Static).withSize(frontend.getSize())) {
        map.getStyle().loadJSON(drapeStyle);
        map.jumpTo(CameraOptions().withCenter(LatLng{46.0, 10.0}).withZoom(14.0).withPitch(pitch));
    }

    style::ImageSource& source() { return *map.getStyle().getSource("field")->as<style::ImageSource>(); }

    // The center pixel after a few frames.
    std::array<uint8_t, 3> render() {
        PremultipliedImage image;
        for (int i = 0; i < 4; ++i) {
            loop.runOnce();
            image = frontend.render(map).image;
        }
        const uint8_t* px = image.data.get() + (128 * image.size.width + 128) * 4;
        return {px[0], px[1], px[2]};
    }
};

} // namespace

// A drape bakes an image source's layer once and serves the bake until something marks it stale.
// A new image on the same source did not: the drape kept the first image, while the same image
// source without terrain showed every update.
TEST(TerrainDrape, ANewImageOnAnImageSourceReachesTheDrape) {
    for (const double pitch : {0.0, 60.0}) {
        Rig rig(pitch);
        rig.source().setImage(solid(255, 0, 0));
        const auto first = rig.render();
        ASSERT_GT(first[0], 150) << "pitch " << pitch;
        ASSERT_LT(first[2], 90) << "pitch " << pitch;

        rig.source().setImage(solid(0, 0, 255));
        const auto second = rig.render();
        EXPECT_LT(second[0], 90) << "pitch " << pitch;
        EXPECT_GT(second[2], 150) << "pitch " << pitch;

        rig.source().setImage(solid(0, 255, 0));
        const auto third = rig.render();
        EXPECT_GT(third[1], 150) << "pitch " << pitch;
        EXPECT_LT(third[2], 90) << "pitch " << pitch;
    }
}

// The corners of an image source change what its drape shows as well.
TEST(TerrainDrape, MovingTheCornersOfAnImageSourceReachesTheDrape) {
    Rig rig(0.0);
    rig.source().setImage(solid(255, 0, 0));
    const auto first = rig.render();
    ASSERT_GT(first[0], 150);

    // Move the image off the view center, inside the same covering tiles.
    rig.source().setCoordinates(
        {{LatLng{46.02, 10.005}, LatLng{46.02, 10.02}, LatLng{45.98, 10.02}, LatLng{45.98, 10.005}}});
    const auto second = rig.render();
    EXPECT_LT(second[0], 90) << "the image no longer covers the center";
}
