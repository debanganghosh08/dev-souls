class_name FireLight
extends OmniLight3D
## The light and the flame of one lit fire: a brazier, a wall torch, a hearth, a pyre. Kit pieces describe
## their fires as data (a `lights` list on the piece dictionary, see StructureKitFire) and
## StructureKit.make_node/make_multi hands every entry to attach(), so a layout lights itself by naming a
## fire piece: nothing in a level or a site file has to know what a flame is.
##
## Three things decide the cost, because a valley full of fires is a valley full of lights:
##  - no shadows, ever: a shadow-casting omni costs several times a plain one, and a flame reads as a glow,
##  - nothing past `cull_distance` is visible at all, and the engine fades out what is nearly there,
##  - the camera, the hour and the darkness are read ONCE per frame for the whole world (statics keyed on
##    Engine.get_frames_drawn()), not once per fire.
##
## The flame is one billboarded quad wearing a teardrop texture painted in code (no fire texture exists in
## assets/, and D-005 keeps binaries out of git), additive and unshaded, its scale driven by the same two
## beating sines as the light so flame and glow gutter together. UNVERIFIED by eye: nobody has seen it.

## Two slow sines beating against each other, as HearthSite does it, so the gutter never finds a rhythm.
const GUTTER_A_HZ := 1.9
const GUTTER_B_HZ := 0.37
const FLAME_TEX := 64
## Below this the flame quad is left out entirely: a light with no flame of its own, for a window glow.
const FLAME_MIN := 0.02

@export var base_energy: float = 2.2
@export var base_range: float = 9.0
## How much of the energy the gutter swings: 0 steady, 0.9 nearly guttering out.
@export var flicker: float = 0.3
@export var cull_distance: float = 60.0
## Share of the energy a fire keeps at midday. A fire still reads in daylight, but it must not wash the
## ground out; at night it runs at the full energy, which is what the player needs it for.
@export var day_share: float = 0.5
## Flame height in metres. The quad is 0.8 as wide.
@export var flame_size: float = 0.5
## Fixed per fire, taken from where it stands, so two fires side by side never gutter in step.
@export var phase: float = 0.0

## Every fire in the scene joins this group, so the vale probe can count them without walking the tree.
const GROUP := &"fires"

## Fires drawing this frame. The vale probe prints it; nothing in the game reads it.
static var lit_count: int = 0

static var _frame: int = -1
static var _camera_at: Vector3 = Vector3.ZERO
static var _has_camera: bool = false
static var _darkness: float = 1.0
static var _flame_mesh: QuadMesh = null
static var _flame_material: StandardMaterial3D = null

var _flame: MeshInstance3D = null
var _time: float = 0.0


## Builds one fire from a piece light spec and parents it. `placement` is the instance transform of the
## piece the fire belongs to (identity for a lone piece, the instance transform for one of a MultiMesh),
## and the spec `at` is local to that piece, exactly like the geometry around it.
static func attach(parent: Node3D, spec: Dictionary, placement: Transform3D = Transform3D.IDENTITY) -> FireLight:
	var light := FireLight.new()
	light.name = "Fire"
	light.base_energy = _f(spec, "energy", 2.2)
	light.base_range = maxf(0.5, _f(spec, "range", 9.0))
	light.flicker = clampf(_f(spec, "flicker", 0.3), 0.0, 0.9)
	light.flame_size = maxf(0.0, _f(spec, "flame", 0.5))
	light.day_share = clampf(_f(spec, "day", 0.5), 0.0, 1.0)
	light.cull_distance = maxf(4.0, _f(spec, "cull", 60.0))
	light.light_color = _colour(spec.get("color", null))
	light.transform = Transform3D(Basis.IDENTITY, placement * _vec(spec.get("at", null)))
	light.phase = fposmod(absf(light.position.x * 12.9898 + light.position.z * 78.233), TAU)
	parent.add_child(light)
	return light


## 1 in the dead of night, 0 with the sun overhead: the same arc from a 06:00 sunrise that DayNightCycle
## paints the sky by, steepened so the fires are already carrying the light at dusk, not at full dark.
static func darkness_at(hour: float) -> float:
	var elevation: float = fposmod(hour - DayNightCycle.SUNRISE_HOUR, DayNightCycle.HOURS_PER_DAY) \
			/ DayNightCycle.DAY_LENGTH_HOURS * 180.0
	if elevation <= 0.0 or elevation >= 180.0:
		return 1.0
	return clampf(1.0 - sin(deg_to_rad(elevation)) * 1.25, 0.0, 1.0)


## Drops the shared flame mesh and material, so the next fire paints a new texture.
static func clear_shared() -> void:
	_flame_mesh = null
	_flame_material = null


func _ready() -> void:
	add_to_group(GROUP)
	shadow_enabled = false
	light_bake_mode = Light3D.BAKE_DISABLED
	light_specular = 0.4
	omni_range = base_range
	omni_attenuation = 1.4
	light_energy = base_energy * _night_scale()
	# Two different distances, and the difference is the point of a beacon: `cull_distance` is how far away
	# the FLAME can still be seen (a watchfire reads from across the valley, which is what makes it worth
	# walking towards), while the light itself is faded out a little past where it actually reaches, so a
	# fire visible at 200 m costs the renderer two triangles rather than a live light.
	var reach: float = minf(cull_distance, base_range * 2.2)
	distance_fade_enabled = true
	distance_fade_begin = reach * 0.7
	distance_fade_length = reach * 0.3
	distance_fade_shadow = reach
	if flame_size > FLAME_MIN:
		_flame = MeshInstance3D.new()
		_flame.name = "Flame"
		_flame.mesh = flame_mesh()
		_flame.material_override = flame_material()
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.visibility_range_end = cull_distance
		_flame.visibility_range_end_margin = cull_distance * 0.15
		_flame.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(_flame)
		_shape_flame(1.0)


func _process(delta: float) -> void:
	_time += delta
	_refresh_world()
	if _has_camera and global_position.distance_squared_to(_camera_at) > cull_distance * cull_distance:
		if visible:
			visible = false
		return
	if not visible:
		visible = true
	lit_count += 1
	var gutter: float = 1.0 + flicker * (0.62 * sin(TAU * GUTTER_A_HZ * _time + phase)
			+ 0.38 * sin(TAU * GUTTER_B_HZ * _time + phase * 1.7))
	light_energy = maxf(0.0, base_energy * _night_scale() * gutter)
	omni_range = base_range * (0.94 + 0.06 * gutter)
	if _flame != null:
		_shape_flame(gutter)


## The quad is 1 x 1 with its centre at its origin, so scaling the basis and lifting the origin by half a
## height together is what makes the flame grow from its base instead of from its middle.
func _shape_flame(gutter: float) -> void:
	var h: float = flame_size * clampf(0.82 + 0.18 * gutter, 0.5, 1.4)
	var w: float = flame_size * 0.8 * clampf(1.06 - 0.1 * gutter, 0.5, 1.4)
	var lean: float = 0.03 * flame_size * sin(TAU * GUTTER_B_HZ * 1.3 * _time + phase)
	_flame.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(w, h, 1.0)), Vector3(lean, h * 0.5, 0.0))


func _night_scale() -> float:
	return lerpf(day_share, 1.0, _darkness)


## Once per drawn frame for every fire in the world: whichever fire processes first does the work and the
## rest read the statics. With no Game (the test runner has no autoloads) it counts as night, which is the
## case the fires exist for.
func _refresh_world() -> void:
	# Process frames, not drawn frames: a headless run draws nothing, and get_frames_drawn() stays put
	# there, which would leave the count accumulating instead of restarting each frame.
	var frame: int = Engine.get_process_frames()
	if frame == _frame:
		return
	_frame = frame
	lit_count = 0
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	_has_camera = camera != null
	if _has_camera:
		_camera_at = camera.global_position
	var game: Node = get_node_or_null(^"/root/Game")
	_darkness = darkness_at(float(game.time_of_day)) if game != null else 1.0


static func flame_mesh() -> QuadMesh:
	if _flame_mesh == null:
		_flame_mesh = QuadMesh.new()
		_flame_mesh.size = Vector2.ONE
	return _flame_mesh


## Additive, unshaded and billboarded about Y: the flame faces the player but stays upright, which is what
## a one-quad fire needs so it does not read as a card lying over.
static func flame_material() -> StandardMaterial3D:
	if _flame_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.disable_receive_shadows = true
		m.disable_ambient_light = true
		m.albedo_texture = flame_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_flame_material = m
	return _flame_material


## A teardrop painted in code: the width falls from the base to a point at the top, the core runs
## yellow-white and the edges orange, and a fixed hash roughens the edge so it is not a smooth lozenge.
## Alpha doubles as the brightness, because the material is additive.
static func flame_texture() -> ImageTexture:
	var img := Image.create(FLAME_TEX, FLAME_TEX, true, Image.FORMAT_RGBA8)
	var edge := Color(1.0, 0.42, 0.07)
	var core := Color(1.0, 0.95, 0.72)
	for y: int in range(FLAME_TEX):
		var v: float = 1.0 - (float(y) + 0.5) / float(FLAME_TEX)
		var half: float = 0.47 * pow(maxf(0.0, 1.0 - v), 0.55)
		for x: int in range(FLAME_TEX):
			var u: float = (float(x) + 0.5) / float(FLAME_TEX) - 0.5
			var t: float = 0.0
			if half > 0.001:
				t = clampf(1.0 - absf(u) / half, 0.0, 1.0)
			# Softened at the very bottom edge only: the base of a flame is its brightest part, and it
			# sits down in the coals where the seam cannot be seen anyway.
			t = pow(t, 1.6) * (0.85 + 0.15 * smoothstep(0.0, 0.08, v))
			t *= 0.86 + 0.14 * float((x * 1973 + y * 9277) % 101) / 100.0
			var c: Color = edge.lerp(core, pow(t, 2.0))
			c.a = clampf(t, 0.0, 1.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _colour(value: Variant) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]))
	if value is String:
		return Color(str(value))
	return Color(1.0, 0.63, 0.31)


static func _vec(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback
