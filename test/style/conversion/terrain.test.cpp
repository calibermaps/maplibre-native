#include <mln/test/util.hpp>

#include <mln/style/conversion/json.hpp>
#include <mln/style/conversion/terrain.hpp>
#include <mln/style/conversion_impl.hpp>
#include <mln/style/rapidjson_conversion.hpp>
#include <mln/style/terrain.hpp>
#include <mln/util/rapidjson.hpp>

using namespace mln;
using namespace mln::style;
using namespace mln::style::conversion;

// Rock shading is optional and off by default.
TEST(StyleConversion, TerrainRockShading) {
    Error error;
    const auto parse = [&](const std::string& src) {
        return convertJSON<Terrain>(src, error);
    };

    auto unset = parse(R"({"source": "dem"})");
    ASSERT_TRUE(unset);
    EXPECT_EQ(unset->getRockShading(), 0.0f);
    EXPECT_EQ(unset->getExaggeration(), 1.0f);

    auto on = parse(R"({"source": "dem", "exaggeration": 2, "rock-shading": 0.5})");
    ASSERT_TRUE(on);
    EXPECT_EQ(on->getRockShading(), 0.5f);
    EXPECT_EQ(on->getExaggeration(), 2.0f);

    // Like exaggeration, a value that is not a number is an error; a number is kept as given.
    EXPECT_FALSE(parse(R"({"source": "dem", "rock-shading": "on"})"));
    EXPECT_EQ(error.message, "terrain rock-shading must be a number");
    auto big = parse(R"({"source": "dem", "rock-shading": 3})");
    ASSERT_TRUE(big);
    EXPECT_EQ(big->getRockShading(), 3.0f);

    // A copy, as a style load makes, and the setter keep it.
    Terrain copy(*on);
    EXPECT_EQ(copy.getRockShading(), 0.5f);
    copy.setRockShading(1.0f);
    EXPECT_EQ(copy.getRockShading(), 1.0f);
    EXPECT_EQ(Terrain("dem").getRockShading(), 0.0f);
}
