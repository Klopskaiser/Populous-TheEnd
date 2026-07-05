extends Node

## Central game-state autoload. Autoload "GameState".
##
## Holds access points to the terrain data model and the tribes (created by
## Main at startup) and drives the tribe ticks (mana economy). Match phase and
## win/lose signals are added in later phases.

var terrain_data: TerrainData = null
var terrain: Node3D = null   # the Terrain node (set by Main on startup)
var nav_grid: NavGrid = null

## Player (index 0, blue) and AI (index 1, red) — identical Tribe instances.
var tribes: Array[Tribe] = []

## Fixed seed for the skirmish island (kept here so all systems agree on it).
const ISLAND_SEED: int = 1337

## Tribe id of the human player.
const PLAYER_TRIBE: int = 0


func _process(delta: float) -> void:
	for tribe in tribes:
		tribe.tick(delta)


func get_tribe(id: int) -> Tribe:
	if id >= 0 and id < tribes.size():
		return tribes[id]
	return null


func reset() -> void:
	terrain_data = null
	terrain = null
	nav_grid = null
	tribes = []
