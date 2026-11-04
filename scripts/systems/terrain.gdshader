shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Four surfaces blended by slope and height (see terrain_material.gd for why one shader, not four
// materials). Grass, mud and gravel only appear on gentle ground, so they are mapped planar in world XZ;
// rock lives on steep faces, so it alone is triplanar. Normal maps perturb the WORLD normal along each
// projection's own axes and the result is converted to view space, which keeps the planar and triplanar
// layers in one frame without mesh tangents. The day/night cycle grades colour; what is done here is
// spatial variation only, so no two hectares of the vale look alike (W21-E).
//
// W21-E, the owner's "completely pixelated ... repeating stripes ... one flat green" footage. A 2 m tile
// repeated across a 1024 m field is a stripe generator: every directional feature in the texture lines up
// with every other copy of itself along world X and Z. Three things break it, all in this file:
//   1. Tile breaking (Quilez's "texture repetition" blend): a low-frequency noise picks one of eight
//      ROTATED, offset and slightly rescaled copies of the planar UV per region, and the two neighbouring
//      copies are blended across the region edge. Rotation is the part that kills stripes; an offset alone
//      keeps every feature pointing the same way. Costs one extra fetch per map on the planar layers.
//   2. Macro variation: two octaves of value noise (~60 m and ~16 m) multiply every layer's albedo by
//      1 +- macro_variation, so distant ground is mottled instead of one flat value. ALU only.
//   3. Grass tint variation: grass_tint is still the base, but it is swung between a dry (warm, yellower)
//      and a lush (cooler, greener) multiplier by a ~30 m noise, so the field reads as living ground with
//      patches rather than a mown lawn. Both multipliers sit near luminance 1.0: hue is theirs,
//      brightness is the macro's. ALU only.
// Mud and gravel are now only fetched where their weight is non-zero (the branches are spatially
// coherent), so flat open grass costs 6 fetches where it used to cost 9.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float uv_scale = 0.5;          // tiles per metre: 0.5 -> one tile every 2 m
uniform float grass_slope_deg = 20.0;  // below this: pure grass (or mud when low)
uniform float gravel_slope_deg = 28.0; // grass -> gravel band
uniform float rock_slope_deg = 36.0;   // gravel -> rock band
uniform float mud_height = -3.4;       // world y under which the wet mud ring begins
uniform float mud_blend = 1.8;
uniform float normal_strength = 0.8;
// Multiplied into the grass layer's albedo only (not mud, gravel or rock). The shared ground texture is a
// dry aerial grass, and in the Vale the flat ground is meant to read as living meadow between the blades,
// so the owner's "the starting area is not the desert area" is a colour problem as much as a density one.
uniform vec3 grass_tint : source_color = vec3(1.0);
// W21-E knobs. All scales are in METRES (not tiles, not uv units) so none of them can quietly be a
// multiple of the tile: a region or a noise cell that is exactly n tiles wide lines up with the grid it
// is meant to hide. tile_break_metres <= 0 turns the tile breaking off (one sample per map, as before).
uniform float tile_break_metres = 9.0;  // size of one rotation region: a few tiles, never one, never thirty
uniform float macro_metres = 61.0;      // the slow brightness mottle; a second octave sits at 0.27x
uniform float macro_variation = 0.12;   // +- fraction of albedo the mottle may move
uniform float tint_metres = 31.0;       // size of a dry or lush patch of grass
uniform vec3 grass_tint_dry : source_color = vec3(1.08, 0.99, 0.84);
uniform vec3 grass_tint_lush : source_color = vec3(0.92, 1.02, 1.06);
// The old road, as up to eight segments of the valley polyline (x1, z1, x2, z2). Within road_half metres
// of the line the ground is worn to bare gravel, fading out over road_feather. The grass layer already
// thins along the same line (data/grass/zones_vale.json), but thin grass over green ground is not a road:
// the owner played it and reported "the game has no roads", which was the honest reading. road_count 0
// leaves every area that defines no road looking exactly as it did.
uniform vec4 road_segments[8];
uniform int road_count = 0;
uniform float road_half = 2.5;
uniform float road_feather = 4.0;

float road_weight(vec2 p) {
	if (road_count <= 0) {
		return 0.0;
	}
	float best = 1.0e9;
	for (int i = 0; i < road_count; i++) {
		vec2 a = road_segments[i].xy;
		vec2 b = road_segments[i].zw;
		vec2 ab = b - a;
		float len2 = max(0.0001, dot(ab, ab));
		float t = clamp(dot(p - a, ab) / len2, 0.0, 1.0);
		best = min(best, distance(p, a + ab * t));
	}
	return 1.0 - smoothstep(road_half, road_half + road_feather, best);
}

// Hoskins' sin-free hash: no precision cliff on large world coordinates, no sin() in the inner loop.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise in [0, 1], one cell per unit of p.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Copy number `k` of the planar UV: rotated by k golden angles (eight copies before the cycle repeats,
// none of them axis-aligned), rescaled by up to +-10 %, and offset. `cs` returns (cos, sin) so the
// normal sampled at the rotated UV can be turned back into the world frame.
vec2 variant_uv(vec2 uv, float k, out vec2 cs) {
	float angle = k * 2.399963;
	cs = vec2(cos(angle), sin(angle));
	float scale = 1.0 + 0.1 * sin(k * 1.7);
	vec2 offset = sin(vec2(3.0, 7.0) * k);
	return vec2(cs.x * uv.x - cs.y * uv.y, cs.y * uv.x + cs.x * uv.y) * scale + offset;
}

vec3 unpack(vec4 n) {
	return n.xyz * 2.0 - 1.0;
}

// A tangent-space normal read at a UV rotated by +angle lives in the rotated frame; R(-angle) puts its
// xy back along world X and Z, which is what the planar tangent frame below expects.
vec3 unrotate(vec3 n, vec2 cs) {
	return vec3(cs.x * n.x + cs.y * n.y, -cs.y * n.x + cs.x * n.y, n.z);
}

// One planar layer: albedo, tangent normal and roughness at `uv`. With tile breaking on, two rotated
// copies are read and blended by `index` (a low-frequency noise times eight): the integer part picks the
// pair, the fraction mixes them, and the mix is nudged by the albedo difference so the seam hides in
// whichever copy is darker (Quilez). Normal and roughness reuse the albedo's mix weight, so bumps and
// shine always belong to the same copy as the colour under them.
void planar_layer(sampler2D albedo_tex, sampler2D normal_tex, sampler2D rough_tex, vec2 uv, float index,
		out vec3 albedo, out vec3 normal, out float rough) {
	if (tile_break_metres <= 0.0) {
		albedo = texture(albedo_tex, uv).rgb;
		normal = unpack(texture(normal_tex, uv));
		rough = texture(rough_tex, uv).r;
		return;
	}
	float k = floor(index);
	float f = fract(index);
	vec2 cs_a;
	vec2 cs_b;
	vec2 uv_a = variant_uv(uv, k, cs_a);
	vec2 uv_b = variant_uv(uv, k + 1.0, cs_b);
	vec3 albedo_a = texture(albedo_tex, uv_a).rgb;
	vec3 albedo_b = texture(albedo_tex, uv_b).rgb;
	float w = smoothstep(0.2, 0.8, f - 0.1 * (albedo_a.r + albedo_a.g + albedo_a.b - albedo_b.r - albedo_b.g - albedo_b.b));
	albedo = mix(albedo_a, albedo_b, w);
	normal = mix(unrotate(unpack(texture(normal_tex, uv_a)), cs_a), unrotate(unpack(texture(normal_tex, uv_b)), cs_b), w);
	rough = mix(texture(rough_tex, uv_a).r, texture(rough_tex, uv_b).r, w);
}

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n_geo = normalize(world_normal);
	float slope = degrees(acos(clamp(n_geo.y, -1.0, 1.0)));
	float w_rock = smoothstep(gravel_slope_deg, rock_slope_deg, slope);
	float w_gravel = smoothstep(grass_slope_deg, gravel_slope_deg, slope) * (1.0 - w_rock);
	float w_mud = (1.0 - smoothstep(mud_height, mud_height + mud_blend, world_pos.y)) * (1.0 - w_rock - w_gravel);
	float w_grass = max(0.0, 1.0 - w_rock - w_gravel - w_mud);
	float w_sum = max(0.0001, w_rock + w_gravel + w_mud + w_grass);
	w_rock /= w_sum;
	w_gravel /= w_sum;
	w_mud /= w_sum;
	w_grass /= w_sum;

	// The road eats into whatever is under it, grass first: a track runs over flat ground, and a wagon
	// never wore a path up a cliff, so it fades out as the slope turns to rock.
	float w_road = road_weight(world_pos.xz) * (1.0 - w_rock);
	w_grass = max(0.0, w_grass - w_road);
	w_mud = max(0.0, w_mud - w_road * 0.5);
	w_sum = max(0.0001, w_rock + w_gravel + w_mud + w_grass + w_road);
	w_rock /= w_sum;
	w_gravel /= w_sum;
	w_mud /= w_sum;
	w_grass /= w_sum;
	w_road /= w_sum;

	// The noises, in metres. Each scale is offset so no two share a cell grid.
	vec2 p = world_pos.xz;
	float index = vnoise(p / max(0.01, tile_break_metres)) * 8.0;
	float n_macro = vnoise(p / macro_metres + vec2(7.3, 2.9)) * 0.65
		+ vnoise(p / (macro_metres * 0.27) + vec2(41.7, 13.1)) * 0.35;
	float n_tint = vnoise(p / tint_metres + vec2(19.4, 57.8));
	float macro = 1.0 + macro_variation * (n_macro * 2.0 - 1.0);
	vec3 tint = grass_tint * mix(grass_tint_dry, grass_tint_lush, n_tint);

	vec2 uv = p * uv_scale;
	vec3 albedo = vec3(0.0);
	float rough = 0.0;
	// Planar layers share one tangent frame: +X is the texture's u, +Z its v.
	vec3 nm_planar = vec3(0.0);
	vec3 layer_albedo;
	vec3 layer_normal;
	float layer_rough;
	if (w_grass > 0.001) {
		planar_layer(grass_albedo, grass_normal, grass_rough, uv, index, layer_albedo, layer_normal, layer_rough);
		albedo += layer_albedo * tint * w_grass;
		rough += layer_rough * w_grass;
		nm_planar += layer_normal * w_grass;
	}
	if (w_mud > 0.001) {
		planar_layer(mud_albedo, mud_normal, mud_rough, uv, index, layer_albedo, layer_normal, layer_rough);
		albedo += layer_albedo * w_mud;
		rough += layer_rough * w_mud;
		nm_planar += layer_normal * w_mud;
	}
	float w_gravel_road = w_gravel + w_road;
	if (w_gravel_road > 0.001) {
		planar_layer(gravel_albedo, gravel_normal, gravel_rough, uv, index, layer_albedo, layer_normal, layer_rough);
		albedo += layer_albedo * w_gravel_road;
		rough += layer_rough * w_gravel_road;
		// As before W21-E the road's share of the gravel normal is left out: a worn track is flatter than scree.
		nm_planar += layer_normal * w_gravel;
	}
	vec3 n_world = n_geo + (vec3(1.0, 0.0, 0.0) * nm_planar.x + vec3(0.0, 0.0, 1.0) * nm_planar.y) * normal_strength;

	if (w_rock > 0.001) {
		vec3 bw = pow(abs(n_geo), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec2 uv_x = world_pos.zy * uv_scale;
		vec2 uv_y = world_pos.xz * uv_scale;
		vec2 uv_z = world_pos.xy * uv_scale;
		vec3 rock = texture(rock_albedo, uv_x).rgb * bw.x + texture(rock_albedo, uv_y).rgb * bw.y + texture(rock_albedo, uv_z).rgb * bw.z;
		float rock_r = texture(rock_rough, uv_x).r * bw.x + texture(rock_rough, uv_y).r * bw.y + texture(rock_rough, uv_z).r * bw.z;
		vec3 nx = unpack(texture(rock_normal, uv_x));
		vec3 ny = unpack(texture(rock_normal, uv_y));
		vec3 nz = unpack(texture(rock_normal, uv_z));
		vec3 rock_perturb = (vec3(0.0, nx.y, nx.x) * bw.x + vec3(ny.x, 0.0, ny.y) * bw.y + vec3(nz.x, nz.y, 0.0) * bw.z) * normal_strength;
		albedo += rock * w_rock;
		rough += rock_r * w_rock;
		n_world = mix(n_world, n_geo + rock_perturb, w_rock);
	}

	ALBEDO = albedo * macro;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n_world), 0.0)).xyz);
}
