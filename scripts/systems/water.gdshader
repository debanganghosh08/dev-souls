shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Water (W14). No texture and no normal map: the surface is two scrolling noise fields crossed against
// each other, which is enough for a river seen from a bank and cannot ever be a missing asset (D-005).
// Shallow water reads lighter than deep because of the depth fade, which is what makes a bank look like a
// bank rather than a cut edge.

uniform vec3 shallow_colour : source_color = vec3(0.26, 0.42, 0.40);
uniform vec3 deep_colour : source_color = vec3(0.05, 0.13, 0.17);
uniform float depth_fade = 2.6;        // metres of water over which it darkens to deep_colour
uniform float wave_scale = 0.55;       // ripples per metre
uniform float wave_speed = 0.22;
uniform float wave_strength = 0.35;
uniform float surface_roughness = 0.08;
uniform float edge_softness = 0.6;     // metres of fade where the water meets the ground
uniform float alpha_shallow = 0.55;
uniform float alpha_deep = 0.95;
// Godot 4 removed the built-in DEPTH_TEXTURE: it is a uniform with a hint now.
uniform sampler2D depth_buffer : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

// Cheap value noise: hash the cell corners and smooth between them.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	float t = TIME * wave_speed;
	// Two fields crossing at different rates and angles, so the pattern never visibly repeats.
	float a = noise(uv + vec2(t, t * 0.6));
	float b = noise(uv * 1.9 - vec2(t * 0.7, t * 1.3));
	float ripple = (a + b) * 0.5;

	// Slope of the ripple becomes the normal, which is what catches the light.
	float e = 0.35;
	float nx = noise(uv + vec2(e, 0.0) + vec2(t, t * 0.6)) - noise(uv - vec2(e, 0.0) + vec2(t, t * 0.6));
	float nz = noise(uv + vec2(0.0, e) + vec2(t, t * 0.6)) - noise(uv - vec2(0.0, e) + vec2(t, t * 0.6));
	NORMAL = normalize(mix(NORMAL, normalize(NORMAL + vec3(nx, 0.0, nz) * wave_strength * 6.0), 0.85));

	// Depth is read from how far the ground behind this pixel is, which needs the depth texture. Kept
	// deliberately simple: a linear view-space distance, clamped. Anything cleverer here risks not
	// compiling on a driver nobody has tested, and this has to work on the owner's laptop first.
	float raw = texture(depth_buffer, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float behind = -(view.z / view.w);
	float under = clamp(behind + VERTEX.z, 0.0, 40.0);

	float deep = clamp(under / max(0.05, depth_fade), 0.0, 1.0);
	ALBEDO = mix(shallow_colour, deep_colour, deep) * (0.9 + 0.2 * ripple);
	ROUGHNESS = surface_roughness + 0.08 * ripple;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(alpha_shallow, alpha_deep, deep) * clamp(under / max(0.05, edge_softness), 0.0, 1.0);
}
