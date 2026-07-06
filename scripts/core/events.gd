extends Node

## Global signal bus for decoupling gameplay systems. Autoload "Events".
## Signals are declared here as the project grows; emitters/listeners connect
## through this bus instead of referencing each other directly.

signal unit_died(unit: Node)
signal building_destroyed(building: Node)
## Total wood lying around in piles (there is no per-tribe wood stock).
signal stockpile_changed(total: int)
signal mana_changed(tribe_id: int, amount: float)
signal population_changed(tribe_id: int, population: int, capacity: int)
## Terrain heights changed in this cell rect (flattening, later Landbridge);
## Main rebuilds the affected mesh chunks + collision.
signal terrain_deformed(rect: Rect2i)
## A combat hit landed (kind: punch/kick/shove/fireball); CombatAudio plays a
## matching procedural sound at the position.
signal combat_hit(kind: StringName, pos: Vector3)
