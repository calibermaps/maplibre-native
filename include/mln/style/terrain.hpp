#pragma once

#include <mln/util/immutable.hpp>
#include <string>

namespace mln {
namespace style {

class TerrainObserver;

/**
 * @brief Terrain configuration for 3D terrain rendering
 *
 * Terrain allows the map to be draped over digital elevation model (DEM) data.
 * It requires a raster-dem source and provides an optional exaggeration multiplier and an optional,
 * off-by-default rock shading strength.
 */
class Terrain {
public:
    Terrain();
    explicit Terrain(const std::string& sourceID, float exaggeration = 1.0f, float rockShading = 0.0f);
    ~Terrain();

    /**
     * @brief Get the ID of the raster-dem source providing elevation data
     */
    std::string getSource() const;

    /**
     * @brief Set the ID of the raster-dem source providing elevation data
     */
    void setSource(const std::string& sourceID);

    /**
     * @brief Get the elevation exaggeration multiplier
     * @return Exaggeration factor (default: 1.0)
     */
    float getExaggeration() const;

    /**
     * @brief Set the elevation exaggeration multiplier
     * @param exaggeration Multiplier for elevation values (e.g., 1.5 = 50% more dramatic)
     */
    void setExaggeration(float exaggeration);

    /**
     * @brief Get the rock shading strength
     * @return Strength from 0 to 1 (default: 0, off)
     */
    float getRockShading() const;

    /**
     * @brief Set the rock shading strength, the style's terrain `rock-shading`
     * @param rockShading 0 (the default) leaves the terrain drape untouched; 1 fades ground steeper
     * than about 50 degrees toward lit gray rock, fully by 65 degrees; in between scales that
     * fade. Values outside 0 to 1 are clamped when drawn, and NaN counts as 0. OpenGL and Metal
     * only: the Vulkan and WebGPU backends accept the value and ignore it.
     */
    void setRockShading(float rockShading);

    // Internal implementation
    class Impl;
    Immutable<Impl> impl;
    explicit Terrain(Immutable<Impl>);
    Mutable<Impl> mutableImpl() const;

    TerrainObserver* observer = nullptr;
    void setObserver(TerrainObserver*);
};

} // namespace style
} // namespace mln
