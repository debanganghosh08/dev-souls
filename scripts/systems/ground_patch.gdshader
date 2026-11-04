shader_type spatial;
// Leaf-drift patches for Grass: one tiling photo texture on a flat quad. A square patch of leaves would
// read as a tile, so the edge is cut by the texture's own brightness through ALPHA_SCISSOR: the quad
// keeps the depth prepass (depth, sorting and fog for free) and its outline is ragged where the leaves
// are. Each instance offsets the UV from INSTANCE_CUSTOM so no two patches show the same leaves. Toward
// the fade distance the scissor erodes the patch away instead of popping it.
// W21-D: alpha_to_coverage feathers the ragged outline over MSAA samples instead of a hard cut (the
// handoff from W21-B). aa_edge is added to the scissor threshold by the engine, so it is a small number,
// not the 0.5 the handoff suggested. No ALPHA_TEXTURE_COORDINATE: the alpha here is a radial falloff, not
// a texture lookup, so there is no mip to compensate for.
render_mode cull_back, diffuse_lambert, specular_disabled, depth_draw_opaque, world_vertex_coords, alpha_to_coverage;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_tiles = 0.7;
uniform float fade_start = 30.0;
uniform float fade_end = 45.0;
uniform float edge_start : hint_range(0.0, 1.0) = 0.45;
uniform float aa_edge : hint_range(0.0, 0.5) = 0.05;
uniform vec3 tint : source_color = vec3(0.85, 0.82, 0.78);

varying vec2 v_uv;
varying float v_fade;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	v_fade = 1.0 - smoothstep(fade_start, fade_end, distance(root, CAMERA_POSITION_WORLD));
	v_uv = UV * uv_tiles + INSTANCE_CUSTOM.rg * 7.0;
	// Sit a hair above the ground so the quad never z-fights the terrain it lies on.
	VERTEX.y += 0.015;
}

void fragment() {
	vec4 tex = texture(albedo_tex, v_uv);
	float r = length(UV - vec2(0.5)) * 2.0;
	float lum = dot(tex.rgb, vec3(0.333));
	float coverage = (1.0 - smoothstep(edge_start, 1.0, r)) * v_fade + (lum - 0.5) * 0.7;
	ALBEDO = tex.rgb * tint;
	ALPHA = clamp(coverage, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = aa_edge;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
