extends Node

## Central game-state autoload. Autoload "GameState".
##
## For Phase 1 it only holds access points to the terrain data model. Tribe
## management, match phase and win/lose signals are added in later phases.

var terrain_data: TerrainData = null
var terrain: Node3D = null   # the Terrain node (set by Main on startup)

## Fixed seed for the skirmish island (kept here so all systems agree on it).
const ISLAND_SEED: int = 1337


func reset() -> void:
	terrain_data = null
	terrain = null
