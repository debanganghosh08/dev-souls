shader_type spatial;
// Blade clumps and pebbles for Grass. No texture samples: colour is the mesh's vertex gradient (dark root,
// dry pale tip) tinted per instance from INSTANCE_CUSTOM. cull_disabled because a blade is a single strip
// seen from both sides. Lambert, no specular: ashen grass in fog is a matte mass, not a shiny lawn.
// world_vertex_coords so wind and the distance fade work in metres and the instance origin is just the
// model matrix translation. The engine flips NORMAL on back faces before this code runs, so NORMAL is
// rebuilt in fragment() from the varying: a blade is lit like the ground it grows from (mostly up) from
// either side, instead of half the field going dark depending on which way the strips happen to face.
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque, world_vertex_coords;

uniform float wind_strength : hint_range(0.0, 2.0) = 0.28;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wind_speed : hint_range(0.0, 5.0) = 1.1;
// Metres^-1: how tightly the travelling ripple bands pack across the field.
uniform float ripple_scale : hint_range(0.0, 1.0) = 0.09;
uniform float fade_start = 52.0;
uniform float fade_end = 70.0;
uniform vec3 dry_tint : source_color = vec3(0.70, 0.64, 0.48);
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.8;

varying vec3 v_color;
varying vec3 v_normal;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	// UV.y runs 0 at the root to 1 at the tip: the bend mask, squared so the base stays planted.
	float mask = UV.y * UV.y;
	// Phase from the clump's world position along the wind plus a per-clump jitter: neighbouring clumps are
	// out of step, so gusts travel across the field as bands instead of every blade nodding in unison.
	float phase = dot(root.xz, wind_dir) * ripple_scale + INSTANCE_CUSTOM.b * 6.2831853;
	float t = TIME * wind_speed;
	float gust = 0.6 + 0.4 * (0.7 * sin(t - phase) + 0.3 * sin(2.17 * t - 1.9 * phase + 1.3));
	float bend = wind_strength * gust * mask;
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(root, CAMERA_POSITION_WORLD));
	vec3 v = VERTEX;
	// Lean, do not scale: the tip travels downwind and dips, so the blade keeps its length.
	v.xz += wind_dir * bend;
	v.y -= bend * bend * 0.5;
	// Toward the lattice edge the blade sinks into the ground, so the field dissolves instead of ending in a wall.
	v.y = root.y + (v.y - root.y) * fade;
	VERTEX = v;
	v_normal = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), normal_up_blend));
	v_color = COLOR.rgb * mix(vec3(1.0), dry_tint, INSTANCE_CUSTOM.g) * (0.85 + 0.3 * INSTANCE_CUSTOM.r);
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
}
