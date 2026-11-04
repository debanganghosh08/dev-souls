shader_type spatial;
// Twig-card material for TreeGen crowns. The albedo JPEG has no alpha channel, so the cut-out comes from the
// separate _alpha PNG (white = needle). ALPHA_SCISSOR, not alpha blend: hundreds of trees with ~100 cards
// each would need per-card depth sorting and pay transparent overdraw on every fragment; a scissor cut-out
// writes depth in the prepass, sorts for free and casts correct shadows. cull_disabled makes each
// card double-sided so the crown does not vanish from behind; Godot flips NORMAL for back faces itself.
// Lambert + no specular: the crown should read as a dark, matte mass in fog, not a sheet of shiny leaves.
// W21-D: alpha_to_coverage on top of the scissor (W21-B's handoff). The scissor's hard 0/1 edge is what
// crawled with speckle in the owner's frames; alpha-to-coverage turns the one-pixel band round the
// threshold into MSAA sample coverage and TAA settles it. ALPHA_ANTIALIASING_EDGE is NOT the scissor
// value: the engine adds the edge to the scissor threshold when both are set (so the feather sits just
// above the cut), and handing it 0.5 would put the feather at alpha 1.0 and hollow every crown to half
// coverage. ALPHA_TEXTURE_COORDINATE in texels lets the engine scale alpha back up on distant mips, which
// is what stops mipmapped needles thinning away with distance. The material moves to the alpha pass for
// this (Godot draws alpha-antialiased materials there, still with the depth prepass); the cost is
// UNVERIFIED on the laptop.
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque, alpha_to_coverage;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D alpha_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float scissor : hint_range(0.0, 1.0) = 0.5;
// Added to `scissor` by the engine: the coverage feather is centred at scissor + aa_edge.
uniform float aa_edge : hint_range(0.0, 0.5) = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ALPHA = texture(alpha_tex, UV).r;
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ALPHA_ANTIALIASING_EDGE = aa_edge;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(alpha_tex, 0));
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
