extends Interactable
class_name HearthSite
## The Hearth: the old fire-being under the Mirror Pond, and the last thing the Wick uses. The rule is all in
## scripts/systems/hearth.gd (plain dictionaries in, an Ending out); this node is what the rule touches in
## the world. Using it asks Hearth.ending_for with the real inventory and flags, then either turns the
## player away with a line from data/ui_text.json (the pond still sealed, or a Kindling still wanting --
## named, in requirement order) or records the ending through Flags and hands it to Game.end_journey, where
## EndingCard is already listening. A refusal sets nothing and ends nothing, and the Hearth stays usable;
## once either ending has happened it is spent and refuses for good, on a loaded save too.
##
## Inside the chamber it is the only light: a dim, guttering ember in the bowl with an OmniLight on it, so
## the room is never pitch black whether or not the player brought the torch (PlayerWeapons lights that).
## Taking an ending flares it; a spent Hearth is dark.

const FLARE_ENERGY := 7.0
const FLARE_RANGE := 24.0
const FLARE_SEC := 2.5
const FOCUS_BOOST := 1.35
## Two slow sines beating against each other so the light never settles into a rhythm.
const GUTTER_A_HZ := 1.7
const GUTTER_B_HZ := 0.43
const GUTTER_DEPTH := 0.22

@export var light_energy: float = 1.1
@export var light_range: float = 14.0
@export var ember_emission: float = 1.6

var _cfg: Dictionary = Hearth.DEFAULTS
var _light: OmniLight3D
var _ember_material: StandardMaterial3D
var _ending: int = -1
var _time: float = 0.0


func _init() -> void:
	# In _init rather than _ready so the test runner (which never enters a tree) sees the real config and
	# the data file's prompt; a prompt stored in the scene would still win, so the scene stores none.
	_cfg = Hearth.load_from()
	prompt = UiText.text("hearth_prompt")


func _ready() -> void:
	super()
	_light = get_node_or_null(^"%Light") as OmniLight3D
	var ember: MeshInstance3D = get_node_or_null(^"%Ember") as MeshInstance3D
	if ember != null:
		# Duplicated so a second instance (there is none, but the base glow does the same) never shares it.
		var source: Material = ember.material_override if ember.material_override != null else ember.get_active_material(0)
		_ember_material = source.duplicate() as StandardMaterial3D if source != null else null
		if _ember_material != null:
			ember.material_override = _ember_material
	# A finished journey loaded from a save finds the fire already out.
	if is_spent():
		_set_lit(false)
		set_process(false)


## Game is looked up by the base in _ready; tests hand one in the same way they hand in Flags.
func _inject_game(game: Node) -> void:
	_game = game


func config() -> Dictionary:
	return _cfg


func lit_ending() -> int:
	return _ending


## The decision, from the live inventory and flags. Missing autoloads read as nothing held and nothing
## set, which the rule turns into UNREACHABLE: a refusal, never a crash and never a free ending.
func decide() -> Hearth.Ending:
	return Hearth.ending_for(_definitions(), _held(), _flag_ids(), _cfg)


## Spent means an ending has been recorded, not a once_flag: which flag that is depends on the outcome.
func is_spent() -> bool:
	return Hearth.is_finished(_flag_ids(), _cfg)


func can_interact() -> bool:
	return super() and Hearth.is_ending(decide())


func refusal_reason() -> String:
	if is_spent():
		return UiText.text("hearth_spent")
	match decide():
		Hearth.Ending.UNREACHABLE:
			return UiText.text("hearth_sealed")
		Hearth.Ending.NOT_READY:
			var names: Array[String] = Hearth.missing_names(_definitions(), _held(), str(_cfg.get("kindling_kind", "")))
			return UiText.text("hearth_needs") % ", ".join(names)
	return super()


# The base contract is "never touch flags here; the base sets sets_flag". It cannot hold for the Hearth:
# sets_flag names one flag, and which flag an ending leaves behind is decided by the outcome of this very
# use (REKINDLE and BECOME_FLAME record differently, and both must persist so a finished journey stays
# finished). Setting it here, from Hearth.ending_flag, keeps the rule in one place rather than adding a
# second mechanism to the base for a single prop. Everything else (the refusal path, interacted, autosave)
# is still the base's.
func _on_interact(_who: Node) -> void:
	var ending: Hearth.Ending = decide()
	_ending = ending
	var flag: StringName = Hearth.ending_flag(ending, _cfg)
	if _flags != null and flag != &"":
		_flags.set_flag(flag)
	if _game != null and _game.has_method(&"end_journey"):
		_game.end_journey(ending)
	_flare()


func _process(delta: float) -> void:
	if _light == null or _ending >= 0:
		return
	_time += delta
	var gutter: float = 1.0 + GUTTER_DEPTH * sin(_time * TAU * GUTTER_A_HZ) * sin(_time * TAU * GUTTER_B_HZ)
	var boost: float = FOCUS_BOOST if _focused else 1.0
	_light.light_energy = light_energy * gutter * boost


# The flare runs under EndingCard's three-second fade: the fire wakes, then the screen takes over. The
# tree is never paused for the card (PAUSED is a Game state scripts consult), so a plain tween suffices.
func _flare() -> void:
	set_process(false)
	if _light == null:
		return
	if not is_inside_tree():
		_light.light_energy = FLARE_ENERGY
		_light.omni_range = FLARE_RANGE
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_light, ^"light_energy", FLARE_ENERGY, FLARE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_light, ^"omni_range", FLARE_RANGE, FLARE_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _ember_material != null:
		tween.tween_property(_ember_material, ^"emission_energy_multiplier", ember_emission * 4.0, FLARE_SEC)


func _set_lit(lit: bool) -> void:
	if _light != null:
		_light.light_energy = light_energy if lit else 0.0
		_light.omni_range = light_range
		_light.visible = lit
	if _ember_material != null:
		_ember_material.emission_energy_multiplier = ember_emission if lit else 0.0


func _definitions() -> Dictionary:
	return _inventory.all_definitions() if _inventory != null else {}


func _held() -> Dictionary:
	return _inventory.items() if _inventory != null else {}


func _flag_ids() -> Array:
	return _flags.all_flags() if _flags != null else []
