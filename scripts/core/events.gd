extends Node

## Global signal bus for decoupling gameplay systems. Autoload "Events".
## Signals are declared here as the project grows; emitters/listeners connect
## through this bus instead of referencing each other directly.

signal unit_died(unit: Node)
signal building_destroyed(building: Node)
signal wood_changed(tribe_id: int, amount: int)
signal mana_changed(tribe_id: int, amount: float)
signal population_changed(tribe_id: int, population: int, capacity: int)
