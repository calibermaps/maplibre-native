#include <mln/map/camera.hpp>
#include <mln/map/map_snapshotter.hpp>
#include <mln/storage/resource_options.hpp>
#include <mln/style/layers/fill_layer.hpp>
#include <mln/style/style.hpp>
#include <mln/test/util.hpp>
#include <mln/util/client_options.hpp>
#include <mln/util/run_loop.hpp>
#include <mln/util/timer.hpp>
#include <mln/util/io.hpp>
#include <mln/util/image.hpp>

#include <filesystem>

using namespace mln;

static PremultipliedImage namedImage(const std::string& name) {
    return decodeImage(util::read_file("test/fixtures/sprites/" + name + ".png"));
}

static std::unique_ptr<style::Image> namedMarker(const std::string& name) {
    return std::make_unique<style::Image>(name, namedImage(name), 1.0f);
}

class SnapshotterObserver final : public MapSnapshotterObserver {
public:
    ~SnapshotterObserver() = default;
    void onDidFinishLoadingStyle() override {
        if (didFinishLoadingStyleCallback) {
            didFinishLoadingStyleCallback();
        }
    }
    std::function<void()> didFinishLoadingStyleCallback;
};

TEST(MapSnapshotter, setStyleJSON) {
    util::RunLoop runLoop;
    MapSnapshotter snapshotter(Size{32, 16}, 1.0f, ResourceOptions());
    snapshotter.setStyleJSON(R"JSON({
        "version": 8,
        "layers": [{
            "id": "background",
            "type": "background",
            "paint": {"background-color": "green"}
        }]
    })JSON");

    snapshotter.snapshot([&runLoop](std::exception_ptr ptr,
                                    mln::PremultipliedImage image,
                                    mln::MapSnapshotter::Attributions,
                                    mln::MapSnapshotter::PointForFn,
                                    mln::MapSnapshotter::LatLngForFn) {
        EXPECT_EQ(nullptr, ptr);
        EXPECT_EQ(32, image.size.width);
        EXPECT_EQ(16, image.size.height);
        runLoop.stop();
    });

    runLoop.run();
}

TEST(MapSnapshotter, setSize) {
    util::RunLoop runLoop;
    MapSnapshotter snapshotter(Size{32, 16}, 1.0f, ResourceOptions());
    snapshotter.setStyleJSON(R"JSON({
        "version": 8,
        "layers": [{
            "id": "background",
            "type": "background",
            "paint": {"background-color": "green"}
        }]
    })JSON");

    snapshotter.setSize(Size{16, 32});

    snapshotter.snapshot([&runLoop](std::exception_ptr ptr,
                                    mln::PremultipliedImage image,
                                    mln::MapSnapshotter::Attributions,
                                    mln::MapSnapshotter::PointForFn,
                                    mln::MapSnapshotter::LatLngForFn) {
        EXPECT_EQ(nullptr, ptr);
        EXPECT_EQ(16, image.size.width);
        EXPECT_EQ(32, image.size.height);
        runLoop.stop();
    });

    runLoop.run();
}

TEST(MapSnapshotter, TEST_REQUIRES_SERVER(setStyleURL)) {
    util::RunLoop runLoop;
    MapSnapshotter snapshotter(Size{64, 32}, 1.0f, ResourceOptions());
    snapshotter.setStyleURL("http://127.0.0.1:3000/online/style.json");
    snapshotter.snapshot([&runLoop](std::exception_ptr ptr,
                                    mln::PremultipliedImage image,
                                    mln::MapSnapshotter::Attributions,
                                    mln::MapSnapshotter::PointForFn,
                                    mln::MapSnapshotter::LatLngForFn) {
        EXPECT_EQ(nullptr, ptr);
        EXPECT_EQ(64, image.size.width);
        EXPECT_EQ(32, image.size.height);
        runLoop.stop();
    });

    runLoop.run();
}

TEST(MapSnapshotter, TEST_REQUIRES_SERVER(cancel)) {
    util::RunLoop runLoop;
    MapSnapshotter snapshotter(Size{1, 1}, 1.0f, ResourceOptions());
    snapshotter.setStyleURL("http://127.0.0.1:3000/online/style.json");
    snapshotter.snapshot([](std::exception_ptr,
                            mln::PremultipliedImage,
                            mln::MapSnapshotter::Attributions,
                            mln::MapSnapshotter::PointForFn,
                            mln::MapSnapshotter::LatLngForFn) { ASSERT_TRUE(false); });

    snapshotter.cancel();

    util::Timer timer;
    timer.start(Milliseconds(100), Duration::zero(), [&runLoop] { runLoop.stop(); });

    runLoop.run();
}

TEST(MapSnapshotter, TEST_REQUIRES_SERVER(runtimeStyling)) {
    util::RunLoop runLoop;
    SnapshotterObserver observer;
    MapSnapshotter snapshotter(Size{256, 128}, 1.0f, ResourceOptions(), ClientOptions(), observer);
    snapshotter.setStyleURL("http://127.0.0.1:3000/online/style.json");

    observer.didFinishLoadingStyleCallback = [&snapshotter, &runLoop] {
        auto fillLayer = std::make_unique<style::FillLayer>("green_fill", "mapbox");
        fillLayer->setSourceLayer("water");
        fillLayer->setFillColor(Color(0.25f, 0.88f, 0.82f, 1.0f));
        snapshotter.getStyle().addLayer(std::move(fillLayer));
        snapshotter.snapshot([&runLoop](std::exception_ptr ptr,
                                        mln::PremultipliedImage image,
                                        mln::MapSnapshotter::Attributions,
                                        mln::MapSnapshotter::PointForFn,
                                        mln::MapSnapshotter::LatLngForFn) {
            EXPECT_EQ(nullptr, ptr);
            EXPECT_EQ(256, image.size.width);
            EXPECT_EQ(128, image.size.height);
            test::checkImage("test/fixtures/map/map_snapshotter_overlay", image, 0.005, 0.1);
            runLoop.stop();
        });
    };

    runLoop.run();
}

TEST(MapSnapshotter, TEST_REQUIRES_SERVER(annotation)) {
    util::RunLoop runLoop;
    MapSnapshotter snapshotter(Size{256, 128}, 1.0f, ResourceOptions(), ClientOptions());
    snapshotter.setStyleURL("http://127.0.0.1:3000/online/style.json");
    snapshotter.addAnnotationImage(namedMarker("default_marker"));
    snapshotter.addAnnotation(SymbolAnnotation{Point<double>{0, 0}, "default_marker"});
    FillAnnotation fillAnnotation{Polygon<double>{{{{0, 0}, {0, 45}, {45, 45}, {45, 0}}}}};
    fillAnnotation.color = Color::red();
    snapshotter.addAnnotation(fillAnnotation);
    LineAnnotation lineAnnotation{LineString<double>{{{0, 0}, {45, 45}, {30, 0}}}};
    lineAnnotation.color = Color::blue();
    lineAnnotation.width = {5};
    snapshotter.addAnnotation(lineAnnotation);
    snapshotter.snapshot([&runLoop](std::exception_ptr ptr,
                                    mln::PremultipliedImage image,
                                    mln::MapSnapshotter::Attributions,
                                    mln::MapSnapshotter::PointForFn,
                                    mln::MapSnapshotter::LatLngForFn) {
        EXPECT_EQ(nullptr, ptr);
        EXPECT_EQ(256, image.size.width);
        EXPECT_EQ(128, image.size.height);
        test::checkImage("test/fixtures/map/map_snapshotter_annotation", image, 0.005, 0.1);
        runLoop.stop();
    });

    runLoop.run();
}

namespace {

// A flat plateau 2000 m high, as Terrain-RGB: (2000 + 10000) / 0.1 = 120000 = 1 * 65536 + 212 * 256 + 192.
std::string plateauDEMURL() {
    PremultipliedImage image({256, 256});
    for (uint32_t i = 0; i < 256 * 256; ++i) {
        image.data[i * 4 + 0] = 1;
        image.data[i * 4 + 1] = 212;
        image.data[i * 4 + 2] = 192;
        image.data[i * 4 + 3] = 255;
    }
    const auto path = std::filesystem::temp_directory_path() / "mln-snapshotter-terrain-plateau.png";
    util::write_file(path.string(), encodePNG(image));
    return "file://" + path.string();
}

struct SnapshotProjection {
    ScreenCoordinate point;
    LatLng roundTrip;
};

// Where a snapshot's conversion functions put `latLng`, and the coordinate they give back for that pixel.
SnapshotProjection snapshotProjection(bool terrain, const LatLng& latLng) {
    util::RunLoop runLoop;
    MapSnapshotter snapshotter(Size{256, 256}, 1.0f, ResourceOptions());
    std::string style = R"JSON({
        "version": 8,
        "sources": {"dem": {"type": "raster-dem", "tiles": ["DEM_URL"], "encoding": "mapbox",
                            "minzoom": 0, "maxzoom": 0, "tileSize": 256}},
        "layers": [{"id": "background", "type": "background", "paint": {"background-color": "green"}}]
    })JSON";
    if (terrain) {
        style.replace(style.rfind('}'), 1, R"JSON(, "terrain": {"source": "dem", "exaggeration": 1.0}})JSON");
    }
    style.replace(style.find("DEM_URL"), 7, plateauDEMURL());
    snapshotter.setStyleJSON(style);
    snapshotter.setCameraOptions(CameraOptions().withCenter(LatLng{46.0, 10.0}).withZoom(8.0).withPitch(60.0));

    SnapshotProjection result;
    snapshotter.snapshot([&](std::exception_ptr error,
                             PremultipliedImage,
                             MapSnapshotter::Attributions,
                             MapSnapshotter::PointForFn pointFor,
                             MapSnapshotter::LatLngForFn latLngFor) {
        EXPECT_EQ(nullptr, error);
        result.point = pointFor(latLng);
        result.roundTrip = latLngFor(result.point);
        runLoop.stop();
    });
    runLoop.run();
    return result;
}

} // namespace

// With terrain a snapshot's conversions answer on the draped surface, as the map's projection does
// (Map::pixelForLatLngOnTerrain): a point on a 2000 m plateau seen from a pitched camera sits
// higher on the screen than the same point at sea level, and converting that pixel back gives the
// point. They used to ignore the terrain, so a marker placed with them landed below the ground it marks.
TEST(MapSnapshotter, ConversionsAnswerOnTheTerrainSurface) {
    const LatLng ahead{46.5, 10.0};
    const auto flat = snapshotProjection(false, ahead);
    const auto draped = snapshotProjection(true, ahead);

    EXPECT_LT(draped.point.y, flat.point.y - 3.0) << "sea level y " << flat.point.y << ", terrain y " << draped.point.y;
    EXPECT_NEAR(draped.point.x, flat.point.x, 1.0);
    EXPECT_NEAR(draped.roundTrip.latitude(), ahead.latitude(), 0.01);
    EXPECT_NEAR(draped.roundTrip.longitude(), ahead.longitude(), 0.01);
    // Without terrain nothing changes: the sea-level round trip.
    EXPECT_NEAR(flat.roundTrip.latitude(), ahead.latitude(), 0.01);
}
