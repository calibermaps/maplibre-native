out vec2 v_uv;
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
    highp vec4 u_unpack_from; // the DEM unpack vector of the surface being blended away from
    highp float u_exaggeration_from;
    highp float u_dem_dim_from;
    highp float u_dem_blend; // 1 = the surface is the bound DEM; below 1, blended up from u_dem_from
    lowp float props_pad5;
};

layout (location = 0) in vec4 a_pos; // xy = tile position, z = skirt flag (1 = skirt vertex)

uniform sampler2D u_dem;
uniform sampler2D u_dem_from;

// The surface height at a tile-local point: the bound DEM's, or while the terrain blends from
// another DEM (a finer tile replacing an ancestor, or a new source or exaggeration) the old DEM's
// height mixed into it by one blend value for every tile. The old DEM is read only while blending.
float surface_elevation(vec2 p) {
    float to_height = get_elevation(p, u_dem, u_dem_tile_coords, u_unpack,
                                    u_dem_tile_coords.w, u_exaggeration, 1.0);
    if (u_dem_blend >= 1.0) {
        return to_height;
    }
    vec4 from_coords = vec4(u_slope_params.yzw, u_dem_dim_from);
    float from_height = get_elevation(p, u_dem_from, from_coords, u_unpack_from,
                                      u_dem_dim_from, u_exaggeration_from, 1.0);
    return mix(from_height, to_height, u_dem_blend);
}

void main() {
    // The mesh was generated with coordinates from 0 to EXTENT (8192)
    vec2 pos = a_pos.xy;
    v_uv = pos / 8192.0;

    // Decode the DEM and interpolate in meters via the shared prelude helper
    // (the packed Terrain-RGB/Terrarium DEM cannot be hardware-filtered, so it is
    // sampled NEAREST and interpolated after decoding, matching maplibre-gl-js and
    // the elevated layers). Map into the bound DEM tile; an ancestor tile is bound
    // as a fallback while this tile's own DEM loads. dem_coords.w = DEM dimension.
    v_elevation = surface_elevation(pos);

    // Surface normal (x east, y south, z up) from central differences one DEM texel either side,
    // in the same exaggerated metres the mesh is lifted by. The fragment stage turns steep
    // ground into lit rock.
    float texel = 1.0 / max(u_dem_tile_coords.x * u_dem_tile_coords.w, 1e-4);
    float dx = surface_elevation(pos + vec2(texel, 0.0)) - surface_elevation(pos - vec2(texel, 0.0));
    float dy = surface_elevation(pos + vec2(0.0, texel)) - surface_elevation(pos - vec2(0.0, texel));
    v_normal = normalize(vec3(-dx, -dy, 2.0 * texel * u_slope_params.x));

    // Skirt vertices hang below the surface by u_elevation_offset, forming a
    // curtain that hides the cracks between neighbouring tiles at different zoom
    // levels (maplibre-gl-js u_ele_delta).
    float ele_delta = a_pos.z == 1.0 ? u_elevation_offset : 0.0;
    gl_Position = u_matrix * vec4(pos.x, pos.y, v_elevation - ele_delta, 1.0);
    // The view depth, for the distance haze
    v_depth = gl_Position.w;
}
