// Generated code, do not modify this file!
#pragma once
#include <mln/shaders/shader_source.hpp>

namespace mln {
namespace shaders {

template <>
struct ShaderSource<BuiltIn::TerrainShader, gfx::Backend::Type::OpenGL> {
    static constexpr const char* name = "TerrainShader";
    static constexpr const char* vertex = R"(out vec2 v_uv;
out float v_elevation;
out vec3 v_normal;
out highp float v_depth;

layout (std140) uniform TerrainDrawableUBO {
    highp mat4 u_matrix;
    highp vec4 u_dem_tile_coords;
    highp vec4 u_slope_params; // x = metres per tile unit
};

layout (std140) uniform TerrainEvaluatedPropsUBO {
    highp vec4 u_unpack;
    highp float u_exaggeration;
    highp float u_elevation_offset;
    lowp float props_pad1;
    lowp float props_pad2;
    highp vec4 u_haze_color; // premultiplied; clear when there is no haze
    highp vec2 u_haze_ramp; // haze = clamp(x - y / view depth, 0, 1)^2
    lowp float props_pad3;
    lowp float props_pad4;
};

layout (location = 0) in vec4 a_pos; // xy = tile position, z = skirt flag (1 = skirt vertex)

uniform sampler2D u_dem;

void main() {
    // The mesh was generated with coordinates from 0 to EXTENT (8192)
    vec2 pos = a_pos.xy;
    v_uv = pos / 8192.0;

    // Decode the DEM and interpolate in meters via the shared prelude helper
    // (the packed Terrain-RGB/Terrarium DEM cannot be hardware-filtered, so it is
    // sampled NEAREST and interpolated after decoding, matching maplibre-gl-js and
    // the elevated layers). Map into the bound DEM tile; an ancestor tile is bound
    // as a fallback while this tile's own DEM loads. dem_coords.w = DEM dimension.
    v_elevation = get_elevation(pos, u_dem, u_dem_tile_coords, u_unpack,
                                u_dem_tile_coords.w, u_exaggeration, 1.0);

    // Surface normal (x east, y south, z up) from central differences one DEM texel either side,
    // in the same exaggerated metres the mesh is lifted by. The fragment stage turns steep
    // ground into lit rock.
    float texel = 1.0 / max(u_dem_tile_coords.x * u_dem_tile_coords.w, 1e-4);
    float dx = get_elevation(pos + vec2(texel, 0.0), u_dem, u_dem_tile_coords, u_unpack,
                             u_dem_tile_coords.w, u_exaggeration, 1.0) -
               get_elevation(pos - vec2(texel, 0.0), u_dem, u_dem_tile_coords, u_unpack,
                             u_dem_tile_coords.w, u_exaggeration, 1.0);
    float dy = get_elevation(pos + vec2(0.0, texel), u_dem, u_dem_tile_coords, u_unpack,
                             u_dem_tile_coords.w, u_exaggeration, 1.0) -
               get_elevation(pos - vec2(0.0, texel), u_dem, u_dem_tile_coords, u_unpack,
                             u_dem_tile_coords.w, u_exaggeration, 1.0);
    v_normal = normalize(vec3(-dx, -dy, 2.0 * texel * u_slope_params.x));

    // Skirt vertices hang below the surface by u_elevation_offset, forming a
    // curtain that hides the cracks between neighbouring tiles at different zoom
    // levels (maplibre-gl-js u_ele_delta).
    float ele_delta = a_pos.z == 1.0 ? u_elevation_offset : 0.0;
    gl_Position = u_matrix * vec4(pos.x, pos.y, v_elevation - ele_delta, 1.0);
    // The view depth, for the distance haze
    v_depth = gl_Position.w;
}
)";
    static constexpr const char* fragment = R"(in vec2 v_uv;
in float v_elevation;
in vec3 v_normal;
in highp float v_depth;

layout (std140) uniform TerrainEvaluatedPropsUBO {
    highp vec4 u_unpack;
    highp float u_exaggeration;
    highp float u_elevation_offset;
    lowp float props_pad1;
    lowp float props_pad2;
    highp vec4 u_haze_color; // premultiplied; clear when there is no haze
    highp vec2 u_haze_ramp; // haze = clamp(x - y / view depth, 0, 1)^2
    lowp float props_pad3;
    lowp float props_pad4;
};

uniform sampler2D u_map;

void main() {
    // Sample the map texture (render-to-texture output) for the surface color
    // Note: Y-coordinate is flipped (1.0 - y) to match OpenGL convention
    fragColor = texture(u_map, vec2(v_uv.x, 1.0 - v_uv.y));

    // Ground steeper than about 50 degrees stretches the top-down drape into streaks. Fade it
    // toward lit rock (full by 65 degrees), keeping about a third of the drape so lines and
    // overlays crossing a face stay visible. Gentler ground takes no part of this.
    vec3 n = normalize(v_normal);
    float rock = 1.0 - smoothstep(0.4226, 0.6428, n.z); // cos 65, cos 50 degrees
    if (rock > 0.0) {
        float shade = 0.55 + 0.6 * max(dot(n, vec3(-0.5, -0.5, 0.7071)), 0.0); // sun from the north-west
        vec3 lit = mix(vec3(0.54), fragColor.rgb, 0.35) * shade * fragColor.a;
        fragColor.rgb = mix(fragColor.rgb, lit, rock);
    }

    // Distance haze: past where it begins the ground fades toward the haze color, as gl-js's terrain fog
    // does, to the full color (its alpha) where it ends (the ramp is TerrainLayerTweaker's). A zero
    // ramp leaves the drape as it is.
    highp float haze = clamp(u_haze_ramp.x - u_haze_ramp.y / max(v_depth, 1e-6), 0.0, 1.0);
    haze *= haze;
    fragColor.rgb = fragColor.rgb * (1.0 - u_haze_color.a * haze) + u_haze_color.rgb * (fragColor.a * haze);

#if defined(OVERDRAW_INSPECTOR)
    fragColor = vec4(1.0);
#endif
}
)";
};

} // namespace shaders
} // namespace mln
