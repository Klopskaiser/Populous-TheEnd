class_name LavaCommon extends RefCounted

## The shared MODEL behind both lava shapes (phase 10c): a red, viscous mass
## that creeps downhill and pools where the ground levels out. LavaSurge (a
## radial sheet at the crater) and LavaFlow (a ribbon down a slope) stay
## separate classes — three production sites and a pile of test assertions
## hang off them — but they share the colour ramp, the gradient probe, the
## flow law and the ignition query from here: "one model, two shapes".
##
## Pure statics only, no state, never instantiated. The COLOURS live here
## rather than in Balance on purpose: they are presentation, and Balance is
## the gameplay-tuning file (project convention).

## Glowing front of a freshly poured tongue.
const COLOR_HOT: Color = Color(1.0, 0.22, 0.04)
## Viscous dark red — the body of the mass after it has been lying a moment.
const COLOR_MID: Color = Color(0.62, 0.06, 0.02)
## Cooled crust; stays behind as a scorch mark where the source scorches.
const COLOR_SCORCH: Color = Color(0.07, 0.05, 0.04)


## Colour of a patch of lava that was poured `age` seconds ago. `cooled`
## patches turn to scorch (or fade out where the source leaves no scorch —
## the earthquake's fault lava).
static func color_for(age: float, molten_time: float, cooled: bool,
		scorch: bool) -> Color:
	if cooled:
		if scorch:
			return COLOR_SCORCH
		# No scorch: the crust fades away over one more molten window.
		return Color(COLOR_MID.r, COLOR_MID.g, COLOR_MID.b,
			clampf(1.0 - (age - molten_time) / maxf(molten_time, 0.01), 0.0, 1.0))
	var t: float = clampf(age / maxf(molten_time, 0.01), 0.0, 1.0)
	return COLOR_HOT.lerp(COLOR_MID, t)


## Downhill direction at a world XZ, with the LENGTH of the local gradient
## (rise per metre) — callers need both, and a second probe just to measure
## the slope would double the height samples.
static func downhill(td: TerrainData, x: float, z: float) -> Vector3:
	if td == null:
		return Vector3.ZERO
	var e: float = 0.5
	var gx: float = td.get_height(x + e, z) - td.get_height(x - e, z)
	var gz: float = td.get_height(x, z + e) - td.get_height(x, z - e)
	return Vector3(-gx, 0.0, -gz) / (2.0 * e)


## The flow law: viscous base speed, faster the steeper it runs, ZERO uphill
## — the mass simply piles up there. `slope` is the descent along the flow
## direction (positive = downhill), i.e. downhill(...).dot(direction).
static func flow_speed(slope: float) -> float:
	return Balance.LAVA_FLOW_SPEED \
		* clampf(1.0 + Balance.LAVA_SLOPE_BIAS * slope, 0.0, 3.0)


## Ignites everything flammable inside one radius around `at`: units (lava
## knows no friends; airborne ones pass over it), trees and wood piles.
## `source` throttles repeat ignition per lava instance (Unit.ignite).
static func ignite_all(um: UnitManager, at: Vector3, radius: float,
		source: Node3D) -> void:
	if um == null:
		return
	for u in um.get_units_in_radius(at, radius):
		if u.state == Unit.State.DEAD or u.is_airborne():
			continue   # airborne units (thrown, airship deck) pass over the lava
		u.ignite(at, source)
	if um.tree_manager != null:
		um.tree_manager.ignite_in_radius(at, radius)
	if um.wood_pile_manager != null:
		um.wood_pile_manager.ignite_in_radius(at, radius)
