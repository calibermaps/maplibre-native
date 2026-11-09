#pragma once

#include <mln/style/terrain.hpp>
#include <mln/util/immutable.hpp>
#include <string>

namespace mln {
namespace style {

class Terrain::Impl {
public:
    Impl()
        : exaggeration(1.0f) {}
    Impl(const std::string& sourceID_, float exaggeration_, float rockShading_)
        : sourceID(sourceID_),
          exaggeration(exaggeration_),
          rockShading(rockShading_) {}

    std::string sourceID;
    float exaggeration;
    float rockShading = 0.0f; // optional, off by default

    bool operator==(const Impl& other) const {
        return sourceID == other.sourceID && exaggeration == other.exaggeration && rockShading == other.rockShading;
    }
};

} // namespace style
} // namespace mln
