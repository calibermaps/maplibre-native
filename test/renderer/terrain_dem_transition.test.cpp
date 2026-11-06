#include <mln/test/util.hpp>
#include <mln/test/stub_file_source.hpp>
#include <mln/test/map_adapter.hpp>

#include <mln/gfx/backend_scope.hpp>
#include <mln/gfx/context.hpp>
#include <mln/gfx/headless_frontend.hpp>
#include <mln/gfx/rendering_stats.hpp>
#include <mln/map/bound_options.hpp>
#include <mln/map/camera.hpp>
#include <mln/map/map_options.hpp>
#include <mln/map/mode.hpp>
#include <mln/renderer/terrain_surface_fade.hpp>
#include <mln/style/style.hpp>
#include <mln/style/terrain.hpp>
#include <mln/util/image.hpp>
#include <mln/util/projection.hpp>
#include <mln/util/run_loop.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <functional>
#include <optional>
#include <string>
#include <thread>
#include <vector>

using namespace mln;
using terrain::SurfaceFade;

namespace {

TimePoint at(int64_t ms) {
    return TimePoint{} + std::chrono::milliseconds(ms);
}

// Runs the fade frame by frame, `frameMs` apart, from `start`, and returns the blend of each frame.
std::vector<float> blendsOfAFade(SurfaceFade& fade, int64_t start, int64_t frameMs, int maxFrames = 200) {
    std::vector<float> blends{fade.blend()};
    for (int i = 1; i <= maxFrames && fade.active(); ++i) {
        fade.advance(at(start + i * frameMs), true);
        blends.push_back(fade.blend());
    }
    return blends;
}

} // namespace

// The blend is what the eye sees as a height changing: it rises over several frames, in small steps,
// not in one, and a stalled frame does not end it early.
TEST(TerrainSurfaceFade, TheBlendRisesAcrossFramesInSmallSteps) {
    SurfaceFade fade;
    EXPECT_EQ(1.0f, fade.blend()) << "at rest the surface is the new one";
    fade.fade(at(0));
    const auto blends = blendsOfAFade(fade, 0, 16);

    EXPECT_EQ(0.0f, blends.front());
    EXPECT_EQ(1.0f, blends.back());
    EXPECT_GE(blends.size(), 15u) << "the fade took " << blends.size() << " frames";
    for (size_t i = 1; i < blends.size(); ++i) {
        EXPECT_GE(blends[i], blends[i - 1]) << "frame " << i;
        EXPECT_LE(blends[i] - blends[i - 1], 0.15f) << "frame " << i << " stepped " << blends[i] - blends[i - 1];
    }
    EXPECT_FALSE(fade.active());
}

TEST(TerrainSurfaceFade, AStalledFrameAdvancesTheBlendByAFrameStepAtMost) {
    SurfaceFade fade;
    fade.fade(at(0));
    fade.advance(at(16), true);
    const float before = fade.blend();
    fade.advance(at(16 + 2000), true); // the app stalled for two seconds
    EXPECT_TRUE(fade.active()) << "a stall ended the fade";
    EXPECT_LE(fade.blend() - before, 0.3f);
}

// A switch of source shows only the old surface until the new source's tiles are loaded under every
// visible tile: the blend stays at 0, whatever a loaded part of the new source could show.
TEST(TerrainSurfaceFade, ASwitchHoldsTheOldSurfaceUntilTheNewOneIsLoaded) {
    SurfaceFade fade;
    fade.hold(at(0));
    for (int64_t t = 16; t < SurfaceFade::holdTimeout.count() - 100; t += 16) {
        fade.advance(at(t), /*ready=*/false);
        ASSERT_EQ(SurfaceFade::Phase::Holding, fade.phase()) << "at " << t << " ms";
        ASSERT_EQ(0.0f, fade.blend()) << "the new source showed at " << t << " ms, before it had loaded";
    }
    fade.advance(at(2000), /*ready=*/true);
    EXPECT_EQ(SurfaceFade::Phase::Fading, fade.phase());
    EXPECT_EQ(0.0f, fade.blend()) << "the fade starts from the old surface";
}

TEST(TerrainSurfaceFade, ASwitchHoldsNoLongerThanTheTimeout) {
    SurfaceFade fade;
    fade.hold(at(1000));
    fade.advance(at(1000 + SurfaceFade::holdTimeout.count() - 1), false);
    EXPECT_EQ(SurfaceFade::Phase::Holding, fade.phase());
    fade.advance(at(1000 + SurfaceFade::holdTimeout.count()), false);
    EXPECT_EQ(SurfaceFade::Phase::Fading, fade.phase()) << "a source that never finishes loading held the old surface for good";
}

// Neighboring tiles read the same two DEMs at the edge they share, and the one blend value, so
// their heights there are the same at every frame of the fade: no cliff opens between them.
TEST(TerrainSurfaceFade, TwoTilesShareTheirEdgeAtEveryFrameOfASwitch) {
    const float oldEdge = 1200.0f; // the old source's height at the shared edge, read by both tiles
    const float newEdge = 1237.5f; // the new source's
    SurfaceFade fade;
    fade.hold(at(0));
    fade.advance(at(10), true);
    for (const float blend : blendsOfAFade(fade, 10, 16)) {
        const float left = terrain::blendedHeight(oldEdge, newEdge, blend);
        const float right = terrain::blendedHeight(oldEdge, newEdge, blend);
        EXPECT_EQ(left, right) << "blend " << blend;
    }
}

// A tile that takes a finer DEM beside a neighbor that does not blends from the edge height it
// shares with the neighbor to the finer DEM's: the step between them grows from nothing to the
// difference between the two DEMs and never past it, so the skirts, which cover that difference
// once the fade is over, cover it throughout.
TEST(TerrainSurfaceFade, ARefinementBesideAnUnrefinedTileNeverStepsPastItsEnds) {
    const float neighbor = 800.0f;     // the unrefined tile's height at the edge
    const float coarseEdge = 800.0f;   // the refined tile's old height there: the same DEM
    const float fineEdge = 764.0f;     // its finer DEM's
    const float finalStep = std::abs(fineEdge - neighbor);
    SurfaceFade fade;
    fade.fade(at(0));
    float previousStep = 0.0f;
    for (const float blend : blendsOfAFade(fade, 0, 16)) {
        const float step = std::abs(terrain::blendedHeight(coarseEdge, fineEdge, blend) - neighbor);
        EXPECT_LE(step, finalStep + 1e-3f) << "blend " << blend;
        EXPECT_GE(step, previousStep - 1e-3f) << "the step shrank and grew back at blend " << blend;
        previousStep = step;
    }
    EXPECT_NEAR(finalStep, previousStep, 1e-3f);
}

namespace {

constexpr uint32_t demTileSize = 64;

std::string uniformTile(double meters) {
    const auto encoded = static_cast<uint32_t>(std::lround((meters + 10000.0) * 10.0));
    PremultipliedImage image({demTileSize, demTileSize});
    for (uint32_t i = 0; i < demTileSize * demTileSize; ++i) {
        uint8_t* px = image.data.get() + i * 4;
        px[0] = static_cast<uint8_t>(encoded >> 16);
        px[1] = static_cast<uint8_t>((encoded >> 8) & 0xFF);
        px[2] = static_cast<uint8_t>(encoded & 0xFF);
        px[3] = 255;
    }
    return encodePNG(image);
}

// ".../{z}-{x}-{y}.png" holds the position, at its zoom, the tile covers.
bool tileUrlCovers(const std::string& url, const LatLng& position) {
    int z = 0, x = 0, y = 0;
    const auto name = url.substr(url.rfind('/') + 1);
    if (std::sscanf(name.c_str(), "%d-%d-%d.png", &z, &x, &y) != 3) {
        return false;
    }
    const auto at = Projection::project(position, z);
    return std::floor(at.x) == x && std::floor(at.y) == y;
}

const char* twoSourcesStyle = R"STYLE({
  "version": 8,
  "sources": {
    "a": {"type": "raster-dem", "tiles": ["http://example.com/a/{z}-{x}-{y}.png"],
          "encoding": "mapbox", "maxzoom": 8, "tileSize": 64},
    "b": {"type": "raster-dem", "tiles": ["http://example.com/b/{z}-{x}-{y}.png"],
          "encoding": "mapbox", "maxzoom": 8, "tileSize": 64}
  },
  "terrain": {"source": "a", "exaggeration": 1.0},
  "layers": []
})STYLE";

// Source "a" is 2,000 m everywhere and "b" sea level, as a switch to a source whose ground is much
// lower. Source "b" answers only what `bAnswers` lets through.
struct SourceSwitch {
    util::RunLoop loop;
    std::shared_ptr<StubFileSource> fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(),
                                                                                  ClientOptions());
    HeadlessFrontend frontend{{390, 844}, 1};
    MapAdapter map;
    const LatLng center{47.29, 11.4041};
    std::function<bool(const Resource&)> bAnswers = [](const Resource&) { return false; };
    const std::string high = uniformTile(2000.0);
    const std::string low = uniformTile(0.0);

    SourceSwitch()
        : map(frontend,
              MapObserver::nullObserver(),
              fileSource,
              MapOptions().withMapMode(MapMode::Continuous).withSize(frontend.getSize())) {
        fileSource->tileResponse = [this](const Resource& resource) -> std::optional<Response> {
            const bool fromB = resource.url.find("/b/") != std::string::npos;
            if (fromB && !bAnswers(resource)) {
                return std::nullopt;
            }
            Response res;
            res.data = std::make_shared<std::string>(fromB ? low : high);
            return res;
        };
        map.setCenterClampedToGround(true);
        map.getStyle().loadJSON(twoSourcesStyle);
        map.jumpTo(CameraOptions().withCenter(center).withZoom(6.0).withPitch(0.0));
    }

    void render(int steps, const std::function<void()>& each = nullptr) {
        for (int i = 0; i < steps; ++i) {
            loop.runOnce();
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            if (each) {
                each();
            }
        }
    }

    // Frames take as long as the software renderer takes, so the tests count time, not steps
    void renderFor(std::chrono::milliseconds duration,
                   const std::function<void()>& each = nullptr,
                   const std::function<bool()>& done = nullptr) {
        const auto until = std::chrono::steady_clock::now() + duration;
        while (std::chrono::steady_clock::now() < until && !(done && done())) {
            render(1, each);
        }
    }

    double centerAltitude() const { return map.getCameraOptions().centerAltitude.value_or(0.0); }

    gfx::RenderingStats stats() {
        gfx::BackendScope guard{*frontend.getBackend()};
        return frontend.getBackend()->getContext().renderingStats();
    }

    void settleOnA() {
        renderFor(std::chrono::milliseconds(6000));
        ASSERT_NEAR(centerAltitude(), 2000.0, 1.0) << "the camera did not settle on source a's ground";
    }

    void switchToB() { map.getStyle().setTerrain(std::make_unique<style::Terrain>("b")); }
};

} // namespace

// Source b is 2,000 m lower. Its tiles arrive one at a time; the old surface is still what is drawn
// until they have all arrived, so the camera must not follow the new ground down while it does:
// drawn over the old surface, it would be inside the ground.
TEST(TerrainSourceSwitch, TheCameraClearsTheOldGroundWhileTheNewSourceLoads) {
    SourceSwitch test;
    test.settleOnA();

    // Only the tile under the center arrives from b.
    test.bAnswers = [&](const Resource& resource) { return tileUrlCovers(resource.url, test.center); };
    test.switchToB();
    double lowest = 1e9;
    int heldFrames = 0;
    test.renderFor(std::chrono::milliseconds(2500), [&] {
        // Frames are slow on a software renderer; count the ones that drew the old surface
        if (test.stats().terrainSurfaceBlend < 1.0f) {
            lowest = std::min(lowest, test.centerAltitude());
            ++heldFrames;
        }
    });

    ASSERT_GE(heldFrames, 2) << "the old surface was not held";
    EXPECT_GE(lowest, 1990.0) << "the camera followed the new, lower ground down to " << lowest
                              << " m while the old surface was still drawn";
}

// The old surface is drawn, whole, until the new source is loaded under every visible tile, and then
// the whole surface blends to the new one together, a little each frame.
TEST(TerrainSourceSwitch, TheOldSurfaceIsHeldThenTheWholeSurfaceBlendsInTogether) {
    SourceSwitch test;
    test.settleOnA();

    test.bAnswers = [&](const Resource& resource) { return tileUrlCovers(resource.url, test.center); };
    test.switchToB();
    float mostBlendWhileHeld = 0.0f;
    int frames = 0;
    test.renderFor(std::chrono::milliseconds(2500), [&] {
        mostBlendWhileHeld = std::max(mostBlendWhileHeld, test.stats().terrainSurfaceBlend);
        ++frames;
    });
    ASSERT_GE(frames, 2);
    EXPECT_EQ(0.0f, mostBlendWhileHeld) << "part of the new source showed before all of it had loaded";
    EXPECT_GT(test.stats().numTerrainTilesBlending, 0) << "the old surface is not being drawn under the held tiles";

    test.bAnswers = [](const Resource&) { return true; };
    std::vector<float> blends;
    // The new source loads, then the surface blends: until the blend has finished
    test.renderFor(
        std::chrono::milliseconds(20000),
        [&] {
            const float blend = test.stats().terrainSurfaceBlend;
            if (blends.empty() || blend != blends.back()) {
                blends.push_back(blend);
            }
        },
        [&] { return !blends.empty() && blends.back() == 1.0f; });

    ASSERT_FALSE(blends.empty());
    EXPECT_EQ(1.0f, blends.back()) << "the blend did not finish";
    int between = 0;
    for (size_t i = 1; i < blends.size(); ++i) {
        EXPECT_GE(blends[i], blends[i - 1]) << "the blend went back at step " << i;
        EXPECT_LE(blends[i] - blends[i - 1], 0.35f) << "the surface jumped at step " << i;
        between += blends[i] > 0.0f && blends[i] < 1.0f;
    }
    EXPECT_GE(between, 3) << "the surface changed in " << between << " intermediate steps";
    EXPECT_EQ(0, test.stats().numTerrainTilesBlending) << "tiles still hold the old DEM after the fade";

    test.renderFor(std::chrono::milliseconds(1500));
    EXPECT_LT(test.centerAltitude(), 100.0) << "the camera did not settle on the new ground";
}

// A finer DEM replacing the ancestor a tile draws blends in (the same single blend for every tile)
// rather than replacing it between two frames.
TEST(TerrainDEMTransition, AFinerDEMBlendsInOverFramesInsteadOfJumping) {
    util::RunLoop loop;
    auto fileSource = std::make_shared<StubFileSource>(ResourceOptions::Default(), ClientOptions());
    const std::string ground = uniformTile(500.0);
    bool fineAnswers = false;
    fileSource->tileResponse = [&](const Resource& resource) -> std::optional<Response> {
        int z = 0, x = 0, y = 0;
        const auto name = resource.url.substr(resource.url.rfind('/') + 1);
        std::sscanf(name.c_str(), "%d-%d-%d.png", &z, &x, &y);
        if (z > 6 && !fineAnswers) {
            return std::nullopt;
        }
        Response res;
        res.data = std::make_shared<std::string>(ground);
        return res;
    };
    HeadlessFrontend frontend{{390, 844}, 1};
    MapAdapter map(frontend,
                   MapObserver::nullObserver(),
                   fileSource,
                   MapOptions().withMapMode(MapMode::Continuous).withSize(frontend.getSize()));
    map.getStyle().loadJSON(R"STYLE({
      "version": 8,
      "sources": {"dem": {"type": "raster-dem", "tiles": ["http://example.com/{z}-{x}-{y}.png"],
                          "encoding": "mapbox", "maxzoom": 8, "tileSize": 64}},
      "terrain": {"source": "dem", "exaggeration": 1.0},
      "layers": []
    })STYLE");
    const auto stats = [&] {
        gfx::BackendScope guard{*frontend.getBackend()};
        return frontend.getBackend()->getContext().renderingStats();
    };
    const auto render = [&](int steps, const std::function<void()>& each = nullptr) {
        for (int i = 0; i < steps; ++i) {
            loop.runOnce();
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            if (each) {
                each();
            }
        }
    };
    // Zoom 3 asks for zoom 6 tiles, which load; then zoom 5 asks for zoom 8 tiles, held at first
    map.jumpTo(CameraOptions().withCenter(LatLng{47.29, 11.4041}).withZoom(3.0).withPitch(0.0));
    render(80);
    map.jumpTo(CameraOptions().withZoom(5.0));
    float most = 0.0f;
    render(40, [&] { most = std::max(most, 1.0f - stats().terrainSurfaceBlend); });
    EXPECT_EQ(0.0f, most) << "the surface blended with no finer DEM to blend in";

    fineAnswers = true;
    std::vector<float> blends;
    render(120, [&] {
        const float blend = stats().terrainSurfaceBlend;
        if (blend < 1.0f && (blends.empty() || blend != blends.back())) {
            blends.push_back(blend);
        }
    });
    int between = 0;
    for (size_t i = 1; i < blends.size(); ++i) {
        // A blend restarts at 0 when a later fade begins; within one the steps are small
        if (blends[i] > blends[i - 1]) {
            EXPECT_LE(blends[i] - blends[i - 1], 0.35f) << "the surface jumped at step " << i;
        }
        between += blends[i] > 0.0f;
    }
    EXPECT_GE(between, 3) << "the finer DEM replaced the ancestor in " << between << " intermediate steps";
    EXPECT_EQ(1.0f, stats().terrainSurfaceBlend);
}
