shader_type spatial;
// Twig-card material for TreeGen crowns. The albedo JPEG has no alpha channel, so the cut-out comes from the
// separate _alpha PNG (white = needle). ALPHA_SCISSOR, not alpha blend: hundreds of trees with ~100 cards
// each would need per-card depth sorting and pay transparent overdraw on every fragment; a scissor cut-out
// stays in the opaque pass, writes depth, sorts for free and casts correct shadows. cull_disabled makes each
// card double-sided so the crown does not vanish from behind; Godot flips NORMAL for back faces itself.
// Lambert + no specular: the crown should read as a dark, matte mass in fog, not a sheet of shiny leaves.
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D alpha_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float scissor : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ALPHA = texture(alpha_tex, UV).r;
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
