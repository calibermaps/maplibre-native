#pragma once

#include <mln/gfx/drawable_data.hpp>

#include <cstdint>
#include <memory>
#include <vector>

namespace mln {

namespace gfx {

class ImageDrawableData : public DrawableData {
public:
    ImageDrawableData(std::vector<UnwrappedTileID> cover_, std::uint32_t revision_)
        : cover(std::move(cover_)),
          revision(revision_) {}

    std::span<const UnwrappedTileID> drapeCover() const override { return cover; }

    std::uint32_t contentRevision() const override { return revision; }

    /// The tiles the image covers at the zoom of the drawable's own tile
    std::vector<UnwrappedTileID> cover;
    std::uint32_t revision = 0;
};

using UniqueImageDrawableData = std::unique_ptr<ImageDrawableData>;

} // namespace gfx
} // namespace mln
