shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Four surfaces blended by slope and height (see terrain_material.gd for why one shader, not four
// materials). Grass, mud and gravel only appear on gentle ground, so they are mapped planar in world XZ;
// rock lives on steep faces, so it alone is triplanar. Normal maps perturb the WORLD normal along each
// projection's own axes and the result is converted to view space, which keeps the planar and triplanar
// layers in one frame without mesh tangents. Albedo is untinted: the day/night cycle grades colour.

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

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack(vec4 n) {
	return n.xyz * 2.0 - 1.0;
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

	vec2 uv = world_pos.xz * uv_scale;
	vec3 albedo = texture(grass_albedo, uv).rgb * grass_tint * w_grass
		+ texture(mud_albedo, uv).rgb * w_mud
		+ texture(gravel_albedo, uv).rgb * (w_gravel + w_road);
	float rough = texture(grass_rough, uv).r * w_grass
		+ texture(mud_rough, uv).r * w_mud
		+ texture(gravel_rough, uv).r * (w_gravel + w_road);
	// Planar layers share one tangent frame: +X is the texture's u, +Z its v.
	vec3 nm_planar = unpack(texture(grass_normal, uv)) * w_grass
		+ unpack(texture(mud_normal, uv)) * w_mud
		+ unpack(texture(gravel_normal, uv)) * w_gravel;
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

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n_world), 0.0)).xyz);
}
