#pragma once

#include <mln/map/zoom_history.hpp>
#include <mln/util/chrono.hpp>
#include <mln/util/feature.hpp>

#include <memory>
#include <set>
#include <string>

namespace mln {

class CrossfadeParameters {
public:
    float fromScale;
    float toScale;
    float t;
};

class PropertyEvaluationParameters {
public:
    explicit PropertyEvaluationParameters(float z_)
        : z(z_),
          now(Clock::time_point::max()),

          defaultFadeDuration(0) {}

    PropertyEvaluationParameters(ZoomHistory zoomHistory_, TimePoint now_, Duration defaultFadeDuration_)
        : z(zoomHistory_.lastZoom),
          now(now_),
          zoomHistory(zoomHistory_),
          defaultFadeDuration(defaultFadeDuration_) {}

    CrossfadeParameters getCrossfadeParameters() const {
        if (pinnedCrossfade) {
            // Settled: the pattern at its final scale, whatever the time since the zoom level changed.
            return {.fromScale = z > zoomHistory.lastIntegerZoom ? 2.0f : 0.5f, .toScale = 1.0f, .t = 1.0f};
        }
        const float fraction = z - std::floor(z);
        const std::chrono::duration<float> d = defaultFadeDuration;
        const float t = d != std::chrono::duration<float>::zero()
                            ? std::min((now - zoomHistory.lastIntegerZoomTime) / d, 1.0f)
                            : 1.0f;

        return z > zoomHistory.lastIntegerZoom
                   ? CrossfadeParameters{.fromScale = 2.0f, .toScale = 1.0f, .t = fraction + (1.0f - fraction) * t}
                   : CrossfadeParameters{.fromScale = 0.5f, .toScale = 1.0f, .t = 1 - (1 - t) * fraction};
    }

    float z;
    TimePoint now;
    ZoomHistory zoomHistory;
    Duration defaultFadeDuration;

    /// The style's current global state, used to evaluate `global-state` expressions.
    std::shared_ptr<const GlobalStateMap> globalState;

    /// The global-state properties that changed since the last evaluation;
    /// null means the changed keys are unknown (treat all as changed).
    std::shared_ptr<const std::set<std::string>> changedGlobalStateKeys;

    bool zoomChanged = true;
    bool layerChanged = false;
    bool hasCrossfade = true;
    bool globalStateChanged = false;
    /// With terrain on, a pattern is drawn into a drape target that keeps what it was drawn with until
    /// its tiles change. A target drawn in the 300 ms after the view crosses a zoom level kept the
    /// cross-fade half way for good, so the pattern of one tile looked finer than its neighbours'.
    /// Pinned, the cross-fade is already at its end.
    bool pinnedCrossfade = false;
};

} // namespace mln
