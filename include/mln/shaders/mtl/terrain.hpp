#pragma once

#include <mln/shaders/terrain_layer_ubo.hpp>
#include <mln/shaders/shader_source.hpp>
#include <mln/shaders/mtl/shader_program.hpp>

namespace mln {
namespace shaders {

constexpr auto terrainShaderPrelude = R"(

enum {
    idTerrainDrawableUBO = idDrawableReservedVertexOnlyUBO,
    idTerrainTilePropsUBO = idDrawableReservedFragmentOnlyUBO,
    idTerrainEvaluatedPropsUBO = drawableReservedUBOCount,
    terrainUBOCount
};

struct alignas(16) TerrainDrawableUBO {
    /*  0 */ float4x4 matrix;
    /* 64 */ float4 dem_coords;
    /* 80 */ float4 slope_params; // x = metres per tile unit
    /* 96 */
};
static_assert(sizeof(TerrainDrawableUBO) == 6 * 16, "wrong size");

struct alignas(16) TerrainTilePropsUBO {
    /*  0 */ float2 dem_tl;
    /*  8 */ float dem_scale;
    /* 12 */ float pad1;
    /* 16 */
};
static_assert(sizeof(TerrainTilePropsUBO) == 16, "wrong size");

/// Evaluated properties that do not depend on the tile
struct alignas(16) TerrainEvaluatedPropsUBO {
    /*  0 */ float4 unpack; // DEM unpack vector for the source's encoding
    /* 16 */ float exaggeration;
    /* 20 */ float elevation_offset;
    /* 24 */ float pad1;
    /* 28 */ float pad2;
    /* 32 */
};
static_assert(sizeof(TerrainEvaluatedPropsUBO) == 32, "wrong size");

)";

template <>
struct ShaderSource<BuiltIn::TerrainShader, gfx::Backend::Type::Metal> {
    static constexpr auto name = "TerrainShader";
    static constexpr auto vertexMainFunction = "vertexMain";
    static constexpr auto fragmentMainFunction = "fragmentMain";

    static const std::array<AttributeInfo, 1> attributes;
    static constexpr std::array<AttributeInfo, 0> instanceAttributes{};
    static const std::array<TextureInfo, 2> textures;

    static constexpr auto prelude = terrainShaderPrelude;
    static constexpr auto source = R"(

struct VertexStage {
    short4 pos [[attribute(0)]]; // xy = tile position, z = skirt flag (1 = skirt)
};

struct FragmentStage {
    float4 position [[position, invariant]];
    float2 uv;
    float elevation;
    float3 normal;
};

FragmentStage vertex vertexMain(thread const VertexStage vertx [[stage_in]],
                                device const uint32_t& uboIndex [[buffer(idGlobalUBOIndex)]],
                                device const TerrainDrawableUBO* drawableVector [[buffer(idTerrainDrawableUBO)]],
                                device const TerrainEvaluatedPropsUBO& props [[buffer(idTerrainEvaluatedPropsUBO)]],
                                texture2d<float, access::sample> demTexture [[texture(0)]],
                                sampler demSampler [[sampler(0)]]) {

    device const TerrainDrawableUBO& drawable = drawableVector[uboIndex];

    // The mesh was generated with coordinates from 0 to EXTENT (8192)
    float2 pos = float2(vertx.pos.xy);
    float2 uv = pos / 8192.0;

    // Decode the DEM and interpolate in meters via the shared helper (the packed
    // Terrain-RGB/Terrarium DEM cannot be hardware-filtered, so it is sampled
    // NEAREST and interpolated after decoding, matching maplibre-gl-js and the
    // elevated layers). Map into the bound DEM tile; an ancestor tile is bound as
    // a fallback while this tile's own DEM loads. dem_coords.w = DEM dimension.
    float elevation = get_elevation(pos, demTexture, demSampler, drawable.dem_coords, props.unpack,
                                    drawable.dem_coords.w, props.exaggeration, 1.0);

    // Surface normal (x east, y south, z up) from central differences one DEM texel either side,
    // in the same exaggerated metres the mesh is lifted by. The fragment stage turns steep
    // ground into lit rock.
    const float texel = 1.0 / max(drawable.dem_coords.x * drawable.dem_coords.w, 1e-4);
    const float dx = get_elevation(pos + float2(texel, 0.0), demTexture, demSampler, drawable.dem_coords,
                                   props.unpack, drawable.dem_coords.w, props.exaggeration, 1.0) -
                     get_elevation(pos - float2(texel, 0.0), demTexture, demSampler, drawable.dem_coords,
                                   props.unpack, drawable.dem_coords.w, props.exaggeration, 1.0);
    const float dy = get_elevation(pos + float2(0.0, texel), demTexture, demSampler, drawable.dem_coords,
                                   props.unpack, drawable.dem_coords.w, props.exaggeration, 1.0) -
                     get_elevation(pos - float2(0.0, texel), demTexture, demSampler, drawable.dem_coords,
                                   props.unpack, drawable.dem_coords.w, props.exaggeration, 1.0);
    const float3 normal = normalize(float3(-dx, -dy, 2.0 * texel * drawable.slope_params.x));

    // Skirt vertices hang below the surface by elevation_offset, forming a curtain
    // that hides the cracks between neighbouring tiles at different zoom levels
    // (maplibre-gl-js u_ele_delta). pos.z carries the skirt flag.
    const float ele_delta = (float(vertx.pos.z) == 1.0) ? props.elevation_offset : 0.0;
    float4 position = drawable.matrix * float4(pos.x, pos.y, elevation - ele_delta, 1.0);

    return {
        .position  = position,
        .uv        = uv,
        .elevation = elevation,
        .normal    = normal,
    };
}

half4 fragment fragmentMain(FragmentStage in [[stage_in]],
                            device const TerrainEvaluatedPropsUBO& props [[buffer(idTerrainEvaluatedPropsUBO)]],
                            texture2d<float, access::sample> mapTexture [[texture(1)]],
                            sampler mapSampler [[sampler(1)]]) {
#if defined(OVERDRAW_INSPECTOR)
    return half4(1.0);
#endif

    // Sample the map texture (render-to-texture output) for the surface color.
    // The drape RTT is rendered with the core's GL-convention projection. On Vulkan
    // (NDC Y-down) that stores the RTT already flipped, so its terrain shader samples
    // 1.0 - uv.y. Metal's NDC is Y-up, so the RTT is stored upright and the V must NOT
    // be flipped here - sampling 1.0 - uv.y flips the draped map vertically (north/south
    // swapped about the view). Sample uv.y directly on Metal.
    float4 color = mapTexture.sample(mapSampler, float2(in.uv.x, in.uv.y));

    // Ground steeper than about 50 degrees stretches the top-down drape into streaks. Fade it
    // toward lit rock (full by 65 degrees), keeping about a third of the drape so lines and
    // overlays crossing a face stay visible. Gentler ground takes no part of this.
    const float3 n = normalize(in.normal);
    const float rock = 1.0 - smoothstep(0.4226, 0.6428, n.z); // cos 65, cos 50 degrees
    if (rock > 0.0) {
        const float shade = 0.55 + 0.6 * max(dot(n, float3(-0.5, -0.5, 0.7071)), 0.0); // sun from the north-west
        const float3 lit = mix(float3(0.54), color.rgb, 0.35) * shade * color.a;
        color.rgb = mix(color.rgb, lit, rock);
    }
    return half4(color);
}
)";
};

} // namespace shaders
} // namespace mln
