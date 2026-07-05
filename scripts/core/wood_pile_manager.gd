class_name WoodPileManager extends Node

## Registry for all wood piles (child of Main). Deposit/take API for braves
## and construction sites; emits Events.stockpile_changed with the total wood
## lying around (shown in the HUD — there is no tribe wood stock).

const PILE_SCENE: PackedScene = preload("res://scenes/wood_pile.tscn")
## A deposit merges into an existing pile within this radius (if it has space).
const MERGE_RADIUS: float = 2.5

var terrain_data: TerrainData = null
var piles: Array[WoodPile] = []


func setup(p_terrain_data: TerrainData) -> void:
	terrain_data = p_terrain_data


func total_wood() -> int:
	var total: int = 0
	for pile in piles:
		total += pile.amount
	return total


## Drops wood on the ground at pos: fills nearby piles first, creates new
## piles (max 5 each) for the rest.
func deposit(pos: Vector3, amount: int) -> void:
	while amount > 0:
		var pile: WoodPile = _pile_with_space_near(pos)
		if pile == null:
			pile = _create_pile(pos)
		var put: int = mini(pile.space_left(), amount)
		pile.set_amount(pile.amount + put)
		amount -= put
	_emit_total()


## Takes up to `want` wood from all piles within radius around pos; returns
## how much was actually taken. Empty piles are removed.
func take_from_radius(pos: Vector3, radius: float, want: int) -> int:
	if want <= 0:
		return 0
	var taken: int = 0
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for pile in piles.duplicate():
		if taken >= want:
			break
		if Vector2(pile.position.x, pile.position.z).distance_to(flat) > radius:
			continue
		taken += _drain(pile, want - taken)
	if taken > 0:
		_emit_total()
	return taken


## Takes up to `want` wood from one specific pile.
func take_from_pile(pile: WoodPile, want: int) -> int:
	if pile == null or not is_instance_valid(pile) or want <= 0:
		return 0
	var taken: int = _drain(pile, want)
	if taken > 0:
		_emit_total()
	return taken


## Nearest non-empty pile that is NOT within exclude_radius of exclude_pos
## (piles that close to a site get absorbed automatically — hauling them is
## pointless). Pass exclude_radius 0.0 to search all piles.
func nearest_pile(pos: Vector3, exclude_pos: Vector3 = Vector3.INF,
		exclude_radius: float = 0.0) -> WoodPile:
	var best: WoodPile = null
	var best_dist: float = INF
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for pile in piles:
		if pile.amount <= 0:
			continue
		if exclude_radius > 0.0 and exclude_pos != Vector3.INF:
			var to_excluded: float = Vector2(pile.position.x, pile.position.z).distance_to(
				Vector2(exclude_pos.x, exclude_pos.z))
			if to_excluded <= exclude_radius:
				continue
		var d: float = Vector2(pile.position.x, pile.position.z).distance_squared_to(flat)
		if d < best_dist:
			best_dist = d
			best = pile
	return best


func wood_in_radius(pos: Vector3, radius: float) -> int:
	var total: int = 0
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for pile in piles:
		if Vector2(pile.position.x, pile.position.z).distance_to(flat) <= radius:
			total += pile.amount
	return total


## Nearest pile with free space within radius around pos (for consolidating
## deliveries onto an existing pile). Null if none.
func pile_with_space_near(pos: Vector3, radius: float) -> WoodPile:
	var best: WoodPile = null
	var best_dist: float = radius * radius
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for pile in piles:
		if pile.space_left() <= 0:
			continue
		var d: float = Vector2(pile.position.x, pile.position.z).distance_squared_to(flat)
		if d <= best_dist:
			best_dist = d
			best = pile
	return best


## Total wood in piles that lie within radius of ANY of the given positions
## (each pile counted once). Used for the "wood near own buildings" HUD readout.
func wood_near_positions(positions: Array[Vector3], radius: float) -> int:
	if positions.is_empty():
		return 0
	var r2: float = radius * radius
	var total: int = 0
	for pile in piles:
		if pile.amount <= 0:
			continue
		var pf: Vector2 = Vector2(pile.position.x, pile.position.z)
		for p in positions:
			if pf.distance_squared_to(Vector2(p.x, p.z)) <= r2:
				total += pile.amount
				break
	return total


# --- Internals -----------------------------------------------------------------------

func _drain(pile: WoodPile, want: int) -> int:
	var taken: int = mini(pile.amount, want)
	pile.set_amount(pile.amount - taken)
	if pile.amount <= 0:
		piles.erase(pile)
		if pile.is_inside_tree():
			pile.queue_free()
		else:
			pile.free()
	return taken


func _pile_with_space_near(pos: Vector3) -> WoodPile:
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for pile in piles:
		if pile.space_left() <= 0:
			continue
		if Vector2(pile.position.x, pile.position.z).distance_to(flat) <= MERGE_RADIUS:
			return pile
	return null


func _create_pile(pos: Vector3) -> WoodPile:
	var pile: WoodPile = PILE_SCENE.instantiate() as WoodPile
	# Offset follow-up piles slightly so they do not overlap visually.
	var offset: Vector3 = Vector3.ZERO
	if _pile_at(pos) != null:
		var angle: float = TAU * float(piles.size() % 6) / 6.0
		offset = Vector3(cos(angle), 0.0, sin(angle)) * 0.9
	pile.position = pos + offset
	if terrain_data != null:
		pile.position.y = terrain_data.get_height(pile.position.x, pile.position.z)
	add_child(pile)
	piles.append(pile)
	return pile


func _pile_at(pos: Vector3) -> WoodPile:
	var flat: Vector2 = Vector2(pos.x, pos.z)
	for pile in piles:
		if Vector2(pile.position.x, pile.position.z).distance_to(flat) < 0.5:
			return pile
	return null


func _emit_total() -> void:
	if not is_inside_tree():
		return
	var events: Node = get_node_or_null("/root/Events")
	if events != null:
		events.stockpile_changed.emit(total_wood())
