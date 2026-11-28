#pragma once

#include <mln/tile/tile_id.hpp>

#include <cstdint>
#include <memory>
#include <span>

namespace mln {

namespace gfx {

class DrawableData {
public:
    virtual ~DrawableData() = default;

    /// The tiles a drawable covers when that is more than its own tile (an image source's
    /// drawable spans its image), for terrain drape targets to find the drawables to draw.
    /// Empty when the drawable covers only its own tile.
    virtual std::span<const UnwrappedTileID> drapeCover() const { return {}; }

    /// Changes when what the drawable shows changes while its tile and bucket stay: an image
    /// source swaps the image of the one bucket it keeps. A terrain drape bakes it again then.
    virtual std::uint32_t contentRevision() const { return 0; }
};

using UniqueDrawableData = std::unique_ptr<DrawableData>;

} // namespace gfx
} // namespace mln
