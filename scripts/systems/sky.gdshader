shader_type sky;
// Dev Souls sky (W21). ProceduralSkyMaterial's gradient, ground and sun halo written out by hand so a cloud
// layer and a star field can sit on top of them. The uniform names are the ProceduralSkyMaterial property
// names DayNightCycle used to write (sky_top_color, sky_horizon_color, sky_curve, ground_*, sun_angle_max in
// DEGREES, sun_curve), so data/daynight.json keeps its meaning and the old halo tests still describe it.
// Clouds: four octaves of value-noise FBM on a dome projection, drifting with TIME, computed in the
// half-resolution pass (a quarter of the fragments) and composited over the sky in the full pass. Thin
// edges take cloud_color, thick cores cloud_shade, and the lights' discs bleed into thin cloud near them.
// Stars: one hash per cell of a direction-space grid, scaled by star_alpha (already in the profile), hidden
// where cloud is. Both colours and the cover come from the profile per hour, so night clouds are near-black
// instead of a static grey glowing over a dark dome.
render_mode use_half_res_pass;

uniform vec3 sky_top_color : source_color = vec3(0.29, 0.34, 0.41);
uniform vec3 sky_horizon_color : source_color = vec3(0.59, 0.61, 0.63);
uniform float sky_curve : hint_range(0.01, 1.0) = 0.15;
uniform vec3 ground_bottom_color : source_color = vec3(0.17, 0.18, 0.19);
uniform vec3 ground_horizon_color : source_color = vec3(0.53, 0.55, 0.57);
uniform float ground_curve : hint_range(0.01, 1.0) = 0.02;
// Halo around each sky light, in degrees like ProceduralSkyMaterial.sun_angle_max.
uniform float sun_angle_max : hint_range(0.0, 90.0) = 10.0;
uniform float sun_curve : hint_range(0.01, 1.0) = 0.35;

uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;
uniform vec3 cloud_color : source_color = vec3(0.72, 0.74, 0.76);
uniform vec3 cloud_shade : source_color = vec3(0.46, 0.48, 0.52);
// Noise tiles across the dome; higher = smaller clouds.
uniform float cloud_scale : hint_range(0.1, 4.0) = 0.9;
// Width of the density ramp from clear to solid; small = hard-edged cumulus, large = soft overcast.
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.35;
// Noise units per second. The dome spans about 2 / cloud_dome units, so 0.008 crosses it in ~8 real minutes.
uniform vec2 cloud_wind = vec2(0.008, 0.004);
// Added to EYEDIR.y before dividing: 0 is a flat plane (infinite stretch at the horizon), larger bends the
// layer into a dome so the horizon shows smaller, calmer clouds.
uniform float cloud_dome : hint_range(0.05, 1.0) = 0.25;
uniform float cloud_horizon_fade : hint_range(0.01, 0.5) = 0.12;
// How much of a sky light's disc colour bleeds into thin cloud facing it (silver lining).
uniform float cloud_sun_glow : hint_range(0.0, 1.0) = 0.25;

uniform float star_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float star_density : hint_range(10.0, 200.0) = 60.0;
// Fraction of grid cells that hold no star: 0.985 leaves about one cell in seventy.
uniform float star_cutoff : hint_range(0.9, 1.0) = 0.985;
uniform vec3 star_color : source_color = vec3(0.55, 0.6, 0.7);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Four octaves, amplitudes 0.5 .. 0.0625: roughly 0.15 .. 0.8 with its mass around 0.47.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return v;
}

// ProceduralSkyMaterial's disc + halo for one light: solid disc inside the light's own size, then a falloff
// out to halo_rad shaped by sun_curve.
vec3 light_disc(vec3 sky, vec3 eye, bool enabled, vec3 dir, vec3 col, float energy, float size, float halo_rad) {
	if (!enabled) {
		return sky;
	}
	float angle = acos(clamp(dot(dir, eye), -1.0, 1.0));
	if (angle < size) {
		return col * energy;
	}
	if (angle < size + halo_rad) {
		float c = (angle - size) / halo_rad;
		return mix(col * energy, sky, clamp(1.0 - pow(1.0 - c, 1.0 / sun_curve), 0.0, 1.0));
	}
	return sky;
}

vec3 light_glow(vec3 eye, bool enabled, vec3 dir, vec3 col, float energy) {
	if (!enabled) {
		return vec3(0.0);
	}
	return col * energy * pow(max(dot(eye, dir), 0.0), 8.0);
}

void sky() {
	if (AT_HALF_RES_PASS) {
		// Cloud layer only. Below the horizon there is nothing to draw.
		if (EYEDIR.y <= 0.0) {
			COLOR = vec3(0.0);
			ALPHA = 0.0;
		} else {
			vec2 p = EYEDIR.xz / (EYEDIR.y + cloud_dome) * cloud_scale + cloud_wind * TIME;
			float n = fbm(p);
			float threshold = mix(0.78, 0.22, cloud_cover);
			float cloud = smoothstep(threshold, threshold + cloud_softness, n);
			vec3 glow = light_glow(EYEDIR, LIGHT0_ENABLED, LIGHT0_DIRECTION, LIGHT0_COLOR, LIGHT0_ENERGY)
					+ light_glow(EYEDIR, LIGHT1_ENABLED, LIGHT1_DIRECTION, LIGHT1_COLOR, LIGHT1_ENERGY)
					+ light_glow(EYEDIR, LIGHT2_ENABLED, LIGHT2_DIRECTION, LIGHT2_COLOR, LIGHT2_ENERGY)
					+ light_glow(EYEDIR, LIGHT3_ENABLED, LIGHT3_DIRECTION, LIGHT3_COLOR, LIGHT3_ENERGY);
			vec3 col = mix(cloud_color, cloud_shade, cloud) + glow * cloud_sun_glow * (1.0 - cloud);
			COLOR = col;
			ALPHA = cloud * smoothstep(0.0, cloud_horizon_fade, EYEDIR.y);
		}
	} else {
		float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
		float c = 1.0 - v_angle / (PI * 0.5);
		vec3 sky = mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
		float halo = radians(sun_angle_max);
		sky = light_disc(sky, EYEDIR, LIGHT0_ENABLED, LIGHT0_DIRECTION, LIGHT0_COLOR, LIGHT0_ENERGY, LIGHT0_SIZE, halo);
		sky = light_disc(sky, EYEDIR, LIGHT1_ENABLED, LIGHT1_DIRECTION, LIGHT1_COLOR, LIGHT1_ENERGY, LIGHT1_SIZE, halo);
		sky = light_disc(sky, EYEDIR, LIGHT2_ENABLED, LIGHT2_DIRECTION, LIGHT2_COLOR, LIGHT2_ENERGY, LIGHT2_SIZE, halo);
		sky = light_disc(sky, EYEDIR, LIGHT3_ENABLED, LIGHT3_DIRECTION, LIGHT3_COLOR, LIGHT3_ENERGY, LIGHT3_SIZE, halo);
		if (star_alpha > 0.001 && EYEDIR.y > 0.0) {
			vec3 d = EYEDIR * star_density;
			vec3 cell = floor(d);
			float h = hash31(cell);
			vec3 jitter = vec3(hash31(cell + 1.7), hash31(cell + 3.1), hash31(cell + 5.3)) - 0.5;
			vec3 centre = cell + 0.5 + jitter * 0.7;
			float star = (1.0 - smoothstep(0.0, 0.12, length(d - centre))) * step(star_cutoff, h);
			sky += star_color * star * star_alpha * smoothstep(0.0, 0.2, EYEDIR.y);
		}
		c = (v_angle - PI * 0.5) / (PI * 0.5);
		vec3 ground = mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
		vec3 col = mix(ground, sky, step(0.0, EYEDIR.y));
		COLOR = mix(col, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
	}
}
