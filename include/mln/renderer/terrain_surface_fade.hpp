#pragma once

#include <mln/util/chrono.hpp>

#include <algorithm>

namespace mln {
namespace terrain {

/// The one fade the whole terrain surface shares when the DEMs it is drawn from change.
///
/// A mesh tile that changes DEM (a finer tile replacing the ancestor it was drawing with, or a new
/// terrain source or exaggeration replacing the whole surface) keeps drawing the old DEM until the
/// new one is on the GPU, then blends the heights from old to new in the vertex shader. The blend
/// is one number for every tile, so two tiles that meet at an edge are always at the same point of
/// their blend, and their heights at the edge move between the two static states the skirts
/// already cover: the step between them never exceeds the larger of the step before and the one
/// after (see blendedHeight).
///
/// Time comes from the caller, so a test can step it.
class SurfaceFade {
public:
    /// How long the blend takes once it starts.
    static constexpr Milliseconds fadeDuration{300};
    /// How long a switch of source (or exaggeration) holds the old surface for the new one to load
    /// under every visible tile before it blends in whatever has loaded.
    static constexpr Milliseconds holdTimeout{3000};
    /// A frame that comes later than this after the one before advances the blend by this much, so a
    /// stall does not end the blend in one step.
    static constexpr Milliseconds maxFrameStep{50};

    enum class Phase {
        Idle,    ///< the surface is the new one
        Holding, ///< the old surface, until the new one has loaded everywhere visible
        Fading   ///< the blend, old to new
    };

    Phase phase() const { return phase_; }
    bool active() const { return phase_ != Phase::Idle; }

    /// 0 while holding, 1 at rest, in between while fading (eased, so it starts and ends gently).
    float blend() const {
        switch (phase_) {
            case Phase::Idle:
                return 1.0f;
            case Phase::Holding:
                return 0.0f;
            case Phase::Fading: {
                const float t = std::clamp(
                    static_cast<float>(elapsed.count()) / static_cast<float>(fadeDuration.count()), 0.0f, 1.0f);
                return t * t * (3.0f - 2.0f * t);
            }
        }
        return 1.0f;
    }

    /// Start holding the old surface (a new source or exaggeration).
    void hold(TimePoint now) {
        phase_ = Phase::Holding;
        started = now;
        lastFrame = now;
        elapsed = Milliseconds{0};
    }

    /// Start blending at once (a finer DEM replacing an ancestor, already loaded).
    void fade(TimePoint now) {
        phase_ = Phase::Fading;
        lastFrame = now;
        elapsed = Milliseconds{0};
    }

    /// End at the new surface, whatever the phase.
    void finish() { phase_ = Phase::Idle; }

    /// Step to the frame at `now`. `ready` says the new surface is loaded under every visible tile;
    /// a hold ends when it is, or after holdTimeout.
    void advance(TimePoint now, bool ready) {
        switch (phase_) {
            case Phase::Idle:
                return;
            case Phase::Holding:
                if (ready || now - started >= holdTimeout) {
                    fade(now);
                }
                return;
            case Phase::Fading: {
                const auto step = std::clamp(std::chrono::duration_cast<Milliseconds>(now - lastFrame),
                                             Milliseconds{0},
                                             maxFrameStep);
                elapsed += step;
                lastFrame = now;
                if (elapsed >= fadeDuration) {
                    phase_ = Phase::Idle;
                }
                return;
            }
        }
    }

private:
    Phase phase_ = Phase::Idle;
    TimePoint started{};
    TimePoint lastFrame{};
    Milliseconds elapsed{0};
};

/// The height the vertex shader draws at a point: the old DEM's height blended into the new one's
/// (`blend` 0 is the old, 1 the new). Mirrors the shader's mix.
inline float blendedHeight(float fromHeight, float toHeight, float blend) {
    return fromHeight + (toHeight - fromHeight) * blend;
}

} // namespace terrain
} // namespace mln
