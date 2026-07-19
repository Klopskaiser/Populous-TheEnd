class_name WoodDepot extends Building

## Holzstation: a tiny (1x1, 1 wood) storage rack for up to CAPACITY wood.
## The stock is kept as REAL WoodPile objects on fixed slots inside the
## footprint — so workshops and construction/repair sites within their
## ABSORB_RADIUS consume it directly, the tornado scatters it and fire burns
## it exactly like any ground pile. The stored amount is always DERIVED from
## the live piles (never a separate counter), so no sync is needed.
##
## Only ONE destruction stage (user spec): the depot stays fully usable at any
## damage and there is no repairable in-between state — health 0 destroys it
## and the stock keeps lying around as normal (clickable) piles.

const WOOD_COST: int = Balance.WOOD_DEPOT_WOOD_COST
const FOOTPRINT: Vector2i = Balance.WOOD_DEPOT_FOOTPRINT
const MAX_HEALTH: int = Balance.WOOD_DEPOT_HP
const CAPACITY: int = Balance.WOOD_DEPOT_CAPACITY
## Stock pile slots (2x2 raster on the footprint cell).
const STOCK_SLOTS: int = 4
const SLOT_OFFSET: float = 0.28
## Foreign piles this close to the centre are folded into free stock space
## (deposit() merges can drop untracked piles right next to the rack).
const ADOPT_RADIUS: float = 1.2
const ADOPT_INTERVAL: float = 0.5

const C_BASE: Color = Color(0.4, 0.28, 0.14)
const C_POST: Color = Color(0.3, 0.2, 0.1)

## Stock piles (untyped entries: consumed/burnt piles may be freed).
var _stock_piles: Array = []
var _adopt_timer: float = ADOPT_INTERVAL


func _init() -> void:
	wood_cost = WOOD_COST
	footprint = FOOTPRINT
	max_health = MAX_HEALTH
	health = MAX_HEALTH


func display_name() -> String:
	return "Holzstation"


## One destruction stage only: intact (fully usable) or destroyed.
func destruction_stage() -> int:
	return 4 if health <= 0 else 0


## The stock must never be silently eaten as the depot's own repair wood.
func _absorbs_repair_wood() -> bool:
	return false


func _click_body_height() -> float:
	return 1.6


# --- Stock ---------------------------------------------------------------------

## Drops freed/emptied piles (tornado, fire, absorbed by sites/workshops).
func _prune_stock() -> void:
	var kept: Array = []
	for pile in _stock_piles:
		if is_instance_valid(pile) and pile.amount > 0:
			kept.append(pile)
	_stock_piles = kept


func stored_wood() -> int:
	_prune_stock()
	var total: int = 0
	for pile in _stock_piles:
		total += pile.amount
	return total


func storage_left() -> int:
	return CAPACITY - stored_wood()


## Stores up to `amount` wood into the rack; returns how much fit. Fills the
## existing stock piles first, then opens new slots (max STOCK_SLOTS).
func store_wood(amount: int) -> int:
	if wood_pile_manager == null or amount <= 0 or not is_usable():
		return 0
	_prune_stock()
	var stored: int = 0
	for pile in _stock_piles:
		if amount <= 0:
			break
		var put: int = wood_pile_manager.add_to_pile(pile, amount)
		stored += put
		amount -= put
	while amount > 0 and _stock_piles.size() < STOCK_SLOTS:
		var pile: WoodPile = wood_pile_manager.create_pile_at(
			_pile_slot_pos(_stock_piles.size()), false)
		_stock_piles.append(pile)
		var put: int = wood_pile_manager.add_to_pile(pile, amount)
		stored += put
		amount -= put
	return stored


## Takes up to `want` wood out of the rack; returns how much was taken.
func take_stored(want: int) -> int:
	if wood_pile_manager == null or want <= 0:
		return 0
	_prune_stock()
	var taken: int = 0
	for pile in _stock_piles.duplicate():
		if taken >= want:
			break
		taken += wood_pile_manager.take_from_pile(pile, want - taken)
	return taken


func _pile_slot_pos(index: int) -> Vector3:
	var c: Vector3 = center_world()
	var sx: float = -SLOT_OFFSET if index % 2 == 0 else SLOT_OFFSET
	var sz: float = -SLOT_OFFSET if index / 2 == 0 else SLOT_OFFSET
	return Vector3(c.x + sx, c.y, c.z + sz)


## Folds foreign piles lying on the rack (deposit merges create untracked
## piles right next to full stock piles) into free stock space.
func _tick_active(delta: float) -> void:
	_adopt_timer -= delta
	if _adopt_timer > 0.0:
		return
	_adopt_timer = ADOPT_INTERVAL
	if wood_pile_manager == null:
		return
	_prune_stock()
	for pile in wood_pile_manager.piles_in_radius(center_world(), ADOPT_RADIUS):
		if pile in _stock_piles or pile.is_burning():
			continue
		var space: int = storage_left()
		if space <= 0:
			return
		var taken: int = wood_pile_manager.take_from_pile(pile,
			mini(pile.amount, space))
		if taken > 0:
			store_wood(taken)


## The wood is physically there: destroyed depot leaves its stock lying around
## as normal, right-click targetable piles.
func destroy() -> void:
	for pile in _stock_piles:
		if is_instance_valid(pile):
			pile.make_clickable()
	_stock_piles.clear()
	super.destroy()


# --- Visuals (placeholder) -------------------------------------------------------

func asset_kind() -> StringName:
	return &"wood_depot"


## A flat timber base with four corner posts — the visible stock are the real
## wood-pile sprites sitting on the slots.
func _create_visuals() -> void:
	super._create_visuals()
	if _has_custom_model:
		return
	var span: float = float(FOOTPRINT.x)

	var base: MeshInstance3D = MeshInstance3D.new()
	var bbox: BoxMesh = BoxMesh.new()
	bbox.size = Vector3(span * 0.95, 0.1, span * 0.95)
	base.mesh = bbox
	base.material_override = _make_material(C_BASE)
	base.position.y = 0.05
	_mesh_root.add_child(base)

	for sx in [-span * 0.42, span * 0.42]:
		for sz in [-span * 0.42, span * 0.42]:
			var post: MeshInstance3D = MeshInstance3D.new()
			var pbox: BoxMesh = BoxMesh.new()
			pbox.size = Vector3(0.1, 1.2, 0.1)
			post.mesh = pbox
			post.material_override = _make_material(C_POST)
			post.position = Vector3(sx, 0.6, sz)
			_mesh_root.add_child(post)

	_add_flag()
