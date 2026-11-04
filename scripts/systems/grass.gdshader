shader_type spatial;
// Blade clumps, wildflowers and pebbles for Grass. No texture samples: colour is per instance (W8-G).
// COLOR.rgb is the instance's tip colour (the MultiMesh instance colour times the mesh's vertex colour,
// which is white for a blade and the stone's own colour for a pebble) and COLOR.a the per-blade shade
// jitter the mesh bakes in (GrassMesh.SHADE_MIN/SHADE_RANGE). INSTANCE_CUSTOM.rgb is the root colour as
// a fraction of the tip and INSTANCE_CUSTOM.a the wind phase. UV2.y runs 0 at the root to 1 at the tip
// for the colour ramp; UV.y is the bend mask, kept separate so a flower head takes the petal colour
// without taking the whole lean. cull_disabled because a blade is a single strip seen from both sides.
// Lambert, no specular: grass in fog is a matte mass, not a shiny lawn. world_vertex_coords so wind and
// the distance fade work in metres and the instance origin is just the model matrix translation. The
// engine flips NORMAL on back faces before this code runs, so NORMAL is rebuilt in fragment() from the
// varying: a blade is lit like the ground it grows from (mostly up) from either side, instead of half
// the field going dark depending on which way the strips happen to face. No ALPHA anywhere: blades are
// opaque geometry in the opaque pass, so TAA + MSAA handle their edges and nothing here goes transparent.
// W21-D: far_widen. A 4 cm blade is under a pixel wide from 30 m, so the mid field used to dissolve into
// speckle and read as mown lawn over bare ground. From widen_start to fade_start each blade grows up to
// far_widen metres across toward its tip (UV.y, so a pebble at UV.y 0 is untouched and a root stays
// planted); the instance count is the same, only the pixels each blade covers, and TAA integrates the
// still-thin ones into a soft green instead of noise. The wind stays sub-pixel per frame at the current
// strength (about 2.5 mm per frame at the tip at 60 fps), which is why TAA does not smear it.
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque, world_vertex_coords;

uniform float wind_strength : hint_range(0.0, 2.0) = 0.28;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wind_speed : hint_range(0.0, 5.0) = 1.1;
// Metres^-1: how tightly the travelling ripple bands pack across the field.
uniform float ripple_scale : hint_range(0.0, 1.0) = 0.09;
uniform float fade_start = 44.0;
uniform float fade_end = 60.0;
// Metres a blade widens by at its tip by fade_start, ramping in from widen_start.
uniform float far_widen : hint_range(0.0, 0.2) = 0.04;
uniform float widen_start = 12.0;
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.8;
// Must match GrassMesh.SHADE_MIN and SHADE_RANGE: vertex alpha decodes to shade_min + shade_range * a.
uniform float shade_min = 0.85;
uniform float shade_range = 0.3;

varying vec3 v_color;
varying vec3 v_normal;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	// UV.y runs 0 at the root to 1 at the tip: the bend mask, squared so the base stays planted.
	float mask = UV.y * UV.y;
	// Phase from the clump's world position along the wind plus a per-clump jitter: neighbouring clumps are
	// out of step, so gusts travel across the field as bands instead of every blade nodding in unison.
	float phase = dot(root.xz, wind_dir) * ripple_scale + INSTANCE_CUSTOM.a * 6.2831853;
	float t = TIME * wind_speed;
	float gust = 0.6 + 0.4 * (0.7 * sin(t - phase) + 0.3 * sin(2.17 * t - 1.9 * phase + 1.3));
	float bend = wind_strength * gust * mask;
	float dist = distance(root, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	vec3 v = VERTEX;
	// A blade's NORMAL is the direction it leans, so across it is the horizontal perpendicular; UV.x is 0
	// on one edge and 1 on the other, so the edges move apart and the centre line stays where it was.
	vec3 across = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL) + vec3(1e-5, 0.0, 0.0));
	v += across * (UV.x - 0.5) * far_widen * UV.y * smoothstep(widen_start, fade_start, dist);
	// Lean, do not scale: the tip travels downwind and dips, so the blade keeps its length.
	v.xz += wind_dir * bend;
	v.y -= bend * bend * 0.5;
	// Toward the lattice edge the blade sinks into the ground, so the field dissolves instead of ending in a wall.
	v.y = root.y + (v.y - root.y) * fade;
	VERTEX = v;
	v_normal = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), normal_up_blend));
	float shade = shade_min + shade_range * COLOR.a;
	v_color = COLOR.rgb * mix(INSTANCE_CUSTOM.rgb, vec3(1.0), UV2.y) * shade;
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
}
