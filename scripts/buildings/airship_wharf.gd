class_name AirshipWharf extends Workshop

## Luftschiffwerft: manufactures airships — the complete production machinery
## (worker slots, stock fetching, worker-seconds, auto-crew, rally dispatch,
## exit blocking, per-tribe cap) is inherited from the catapult workshop; only
## the product, the dimensions and the worker count differ.
##
## NOTE for type checks: `is Workshop` matches this subclass too — sites that
## distinguish the kinds (sidebar crew view, AI building counts) must check
## AirshipWharf FIRST.

const WHARF_WOOD_COST: int = Balance.AIRSHIP_WHARF_WOOD_COST
const WHARF_FOOTPRINT: Vector2i = Balance.AIRSHIP_WHARF_FOOTPRINT
const WHARF_MAX_HEALTH: int = Balance.AIRSHIP_WHARF_HP
const WHARF_SLOTS: int = Balance.WHARF_WORKER_SLOTS
const WORK_PER_AIRSHIP: float = Balance.WHARF_WORK_PER_AIRSHIP
const AIRSHIP_WOOD: int = Balance.WHARF_AIRSHIP_WOOD

const AIRSHIP_SCENE: PackedScene = preload("res://scenes/units/airship.tscn")


func _init() -> void:
	super()
	wood_cost = WHARF_WOOD_COST
	footprint = WHARF_FOOTPRINT
	max_health = WHARF_MAX_HEALTH
	health = WHARF_MAX_HEALTH


func display_name() -> String:
	return "Luftschiffwerft"


func asset_kind() -> StringName:
	return &"airship_wharf"


# --- Product hooks --------------------------------------------------------------------

func product_scene() -> PackedScene:
	return AIRSHIP_SCENE


func product_wood() -> int:
	return AIRSHIP_WOOD


func work_per_product() -> float:
	return WORK_PER_AIRSHIP


func worker_slots() -> int:
	return WHARF_SLOTS


func product_cap_reached() -> bool:
	return tribe == null or tribe.owned_airship_count() >= tribe.max_airships


# --- Visuals (placeholder) -----------------------------------------------------------

## The workshop hall scaled up, with a balloon nose poking out of the gate
## (so the building reads as "airship wharf").
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var d: float = float(footprint.y)
	var nose: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.1
	sphere.height = 2.2
	nose.mesh = sphere
	nose.material_override = _make_material(Color(0.75, 0.68, 0.5))
	nose.scale = Vector3(1.0, 0.8, 1.6)
	nose.position = Vector3(0.0, 1.6, d * 0.32)
	_mesh_root.add_child(nose)
