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
## A tribe's stored spell-charge counts changed (conversion or cast); the
## sidebar refreshes its charge pips.
signal spell_charges_changed(tribe_id: int)
## A building finished construction (AudioManager plays building_complete).
signal building_completed(building: Node)
## A training building released a freshly trained unit at pos.
signal unit_trained(kind: StringName, pos: Vector3)
## A spell was successfully cast (charge consumed) at the target position.
signal spell_cast(spell_id: StringName, pos: Vector3)
