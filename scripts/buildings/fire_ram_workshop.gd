class_name FireRamWorkshop extends Workshop

## Feuerrammenwerkstatt: manufactures fire rams — the complete production
## machinery (worker slots, stock fetching, worker-seconds, auto-crew, rally
## dispatch, exit blocking, per-tribe cap) is inherited from the catapult
## workshop; only the product and the dimensions differ.
##
## NOTE for type checks: `is Workshop` matches this subclass too — sites that
## distinguish the two (sidebar crew view, AI building counts) must check
## FireRamWorkshop FIRST.

const RAM_WOOD_COST: int = Balance.FIRERAM_WORKSHOP_WOOD_COST
const RAM_FOOTPRINT: Vector2i = Balance.FIRERAM_WORKSHOP_FOOTPRINT
const RAM_MAX_HEALTH: int = Balance.FIRERAM_WORKSHOP_HP
const RAM_WORKER_SLOTS: int = 3
const WORK_PER_RAM: float = Balance.FIRERAM_WORK_PER_RAM
const RAM_WOOD: int = Balance.FIRERAM_WOOD

const FIRE_RAM_SCENE: PackedScene = preload("res://scenes/units/fire_ram.tscn")


func _init() -> void:
	super()
	wood_cost = RAM_WOOD_COST
	footprint = RAM_FOOTPRINT
	max_health = RAM_MAX_HEALTH
	health = RAM_MAX_HEALTH


func display_name() -> String:
	return "Feuerrammenwerkstatt"


func asset_kind() -> StringName:
	return &"fireram_workshop"


# --- Product hooks --------------------------------------------------------------------

func product_scene() -> PackedScene:
	return FIRE_RAM_SCENE


func product_wood() -> int:
	return RAM_WOOD


func work_per_product() -> float:
	return WORK_PER_RAM


func worker_slots() -> int:
	return RAM_WORKER_SLOTS


func product_cap_reached() -> bool:
	return tribe == null or tribe.owned_fire_ram_count() >= tribe.max_fire_rams


# --- Visuals (placeholder) -----------------------------------------------------------

## The workshop hall, with the catapult-arm signature prop swapped for a ram
## beam with a glowing brazier tip (so the building reads as "fire-ram shop").
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	# super() built the hall including the catapult arm + wheel — recolour the
	# roof and add the glowing brazier beam as this shop's own signature.
	var w: float = float(footprint.x)
	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_box: BoxMesh = BoxMesh.new()
	beam_box.size = Vector3(0.24, 0.24, 2.4)
	beam.mesh = beam_box
	beam.material_override = _make_material(C_WOOD_ARM)
	beam.position = Vector3(w * 0.28, 1.6, 0.6)
	beam.rotation.x = -0.2
	_mesh_root.add_child(beam)
	var brazier: MeshInstance3D = MeshInstance3D.new()
	var pot: SphereMesh = SphereMesh.new()
	pot.radius = 0.3
	pot.height = 0.6
	brazier.mesh = pot
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.35, 0.05)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brazier.material_override = glow
	brazier.position = Vector3(w * 0.28, 1.45, 1.75)
	_mesh_root.add_child(brazier)
