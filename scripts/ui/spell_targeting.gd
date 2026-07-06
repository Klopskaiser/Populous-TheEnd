class_name SpellTargeting extends Control

## Spell target-mode controller (no buttons of its own — the sidebar's spell
## tab and the 1-5 hotkeys drive it via toggle_targeting()). A gold ring
## indicator follows the mouse over the terrain; left click casts the armed
## spell via TribeCommands.cast_spell (the shaman walks into cast range
## first), Esc or right click cancels. While active the SelectionManager
## ignores mouse input (it checks is_active()); clicks over the sidebar are
## ignored (Sidebar.is_mouse_over_ui()).

const RAY_LENGTH: float = 1000.0
const TERRAIN_MASK: int = 1   # the indicator snaps to terrain only

## Hotkey order of the ten spells (input actions cast_spell_1..10, keys 1-9
## and 0); matches Sidebar.default_spell_entries().
const HOTKEY_SPELLS: Array[StringName] = [
	&"fireball", &"lightning", &"swarm", &"landbridge", &"tornado",
	&"earthquake", &"volcano", &"firestorm", &"flatten", &"sink"]

var _tribe_commands: TribeCommands = null
var _tribe: Tribe = null
var _world_root: Node3D = null   # parent for the cursor indicator
var _build_menu: BuildMenu = null

var _armed_spell: StringName = &""
var _cursor: Node3D = null
## Cursor variants: gold ring (default) vs. square outline (flatten spell —
## its effect area is a hard-edged square).
var _cursor_ring: Node3D = null
var _cursor_square: Node3D = null
## Ring around the shaman showing the armed spell's cast range; follows her
## every frame (targets beyond it are allowed — she walks closer first).
var _range_ring: MeshInstance3D = null


func setup(p_tribe_commands: TribeCommands, p_tribe: Tribe,
		p_world_root: Node3D, p_build_menu: BuildMenu = null) -> void:
	_tribe_commands = p_tribe_commands
	_tribe = p_tribe
	_world_root = p_world_root
	_build_menu = p_build_menu


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return _armed_spell != &""


func armed_spell() -> StringName:
	return _armed_spell


## Arms the spell for targeting (called by the sidebar / hotkeys). Ignored
## when the spell has no stored charge or the shaman is dead. Cancels a
## running building placement — only one target mode at a time.
func start_targeting(spell_id: StringName) -> void:
	if _tribe == null:
		return
	var spell: Spell = _tribe.get_spell(spell_id)
	if spell == null or spell.charges <= 0:
		return
	var shaman: Unit = _tribe.shaman
	if shaman == null or not is_instance_valid(shaman) \
			or shaman.state == Unit.State.DEAD:
		return
	if _build_menu != null and _build_menu.is_active():
		_build_menu.cancel()
	_armed_spell = spell_id
	_ensure_cursor()
	if _cursor_ring != null:
		_cursor_ring.visible = spell_id != &"flatten"
	if _cursor_square != null:
		_cursor_square.visible = spell_id == &"flatten"
	_show_range_ring(spell.cast_range)


## Same hotkey/button again disarms; a different spell switches over.
func toggle_targeting(spell_id: StringName) -> void:
	if _armed_spell == spell_id:
		cancel()
	else:
		start_targeting(spell_id)


func cancel() -> void:
	_armed_spell = &""
	if _cursor != null:
		_cursor.visible = false
	if _range_ring != null:
		_range_ring.visible = false


func _ensure_cursor() -> void:
	if _cursor != null or _world_root == null:
		return
	_cursor = Node3D.new()
	_cursor.name = "SpellCursor"
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.85, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_ring = Node3D.new()
	_cursor_ring.name = "RingCursor"
	_cursor.add_child(_cursor_ring)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.25
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.15
	_cursor_ring.add_child(ring)
	var tip: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	tip.mesh = sphere
	tip.material_override = mat
	tip.position.y = 0.3
	_cursor_ring.add_child(tip)
	_cursor_square = _make_square_cursor(mat)
	_cursor.add_child(_cursor_square)
	_cursor.visible = false
	_world_root.add_child(_cursor)


## Square outline (four thin bars) matching the flatten spell's area.
func _make_square_cursor(mat: StandardMaterial3D) -> Node3D:
	var square: Node3D = Node3D.new()
	square.name = "SquareCursor"
	var side: float = FlattenSpell.HALF_EXTENT * 2.0
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.15, -FlattenSpell.HALF_EXTENT),
		Vector3(0.0, 0.15, FlattenSpell.HALF_EXTENT),
		Vector3(-FlattenSpell.HALF_EXTENT, 0.15, 0.0),
		Vector3(FlattenSpell.HALF_EXTENT, 0.15, 0.0)]
	for i in range(4):
		var bar: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(side, 0.12, 0.18) if i < 2 else Vector3(0.18, 0.12, side)
		bar.mesh = box
		bar.material_override = mat
		bar.position = offsets[i]
		square.add_child(bar)
	square.visible = false
	return square


## Builds (once) and sizes the range ring for the armed spell.
func _show_range_ring(radius: float) -> void:
	if _world_root == null:
		return
	if _range_ring == null:
		_range_ring = MeshInstance3D.new()
		_range_ring.name = "SpellRangeRing"
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.8, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_range_ring.material_override = mat
		_world_root.add_child(_range_ring)
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius - 0.12
	torus.outer_radius = radius
	_range_ring.mesh = torus
	_range_ring.visible = true


func _process(_delta: float) -> void:
	if not is_active():
		return
	# The shaman died mid-targeting: drop the mode entirely.
	var shaman: Unit = _tribe.shaman if _tribe != null else null
	if shaman == null or not is_instance_valid(shaman) \
			or shaman.state == Unit.State.DEAD:
		cancel()
		return
	# Range ring follows the (possibly moving) shaman.
	if _range_ring != null:
		_range_ring.position = shaman.position + Vector3(0.0, 0.15, 0.0)
	if _cursor == null:
		return
	if Sidebar.is_mouse_over_ui():
		_cursor.visible = false
		return
	var hit: Dictionary = _terrain_hit(get_viewport().get_mouse_position())
	if hit.is_empty():
		_cursor.visible = false
		return
	_cursor.position = hit.position
	_cursor.visible = true


func _terrain_hit(screen_pos: Vector2) -> Dictionary:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * RAY_LENGTH)
	query.collision_mask = TERRAIN_MASK
	return space.intersect_ray(query)


func _unhandled_input(event: InputEvent) -> void:
	# Hotkeys 1-5 toggle the matching spell's target mode.
	for i in range(HOTKEY_SPELLS.size()):
		if event.is_action_pressed("cast_spell_%d" % (i + 1)):
			toggle_targeting(HOTKEY_SPELLS[i])
			get_viewport().set_input_as_handled()
			return
	if not is_active():
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event
		if Sidebar.is_mouse_over_ui():
			return   # clicks over the sidebar never cast/cancel
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var hit: Dictionary = _terrain_hit(mb.position)
			if not hit.is_empty() and _tribe_commands != null:
				if _tribe_commands.cast_spell(_tribe, _armed_spell, hit.position):
					cancel()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()
