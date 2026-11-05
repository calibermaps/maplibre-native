in vec2 v_uv;
in float v_elevation;
in vec3 v_normal;

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

#if defined(OVERDRAW_INSPECTOR)
    fragColor = vec4(1.0);
#endif
}
