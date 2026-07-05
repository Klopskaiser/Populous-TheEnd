class_name Hud extends Control

## German HUD: shows the wood lying around in piles (there is no wood stock),
## plus mana and population of the player tribe. Updates purely via Events
## signals (no polling); the initial values are read once in setup().

var tribe_id: int = 0

@onready var _wood_label: Label = %WoodLabel
@onready var _mana_label: Label = %ManaLabel
@onready var _population_label: Label = %PopulationLabel


func setup(tribe: Tribe, initial_stockpile: int = 0) -> void:
	tribe_id = tribe.id
	_set_wood(initial_stockpile)
	_set_mana(tribe.mana)
	_set_population(tribe.population(), tribe.housing_capacity())


func _ready() -> void:
	var events: Node = get_node_or_null("/root/Events")
	if events == null:
		return
	events.stockpile_changed.connect(_on_stockpile_changed)
	events.mana_changed.connect(_on_mana_changed)
	events.population_changed.connect(_on_population_changed)


func _on_stockpile_changed(total: int) -> void:
	_set_wood(total)


func _on_mana_changed(p_tribe_id: int, amount: float) -> void:
	if p_tribe_id == tribe_id:
		_set_mana(amount)


func _on_population_changed(p_tribe_id: int, population: int, capacity: int) -> void:
	if p_tribe_id == tribe_id:
		_set_population(population, capacity)


func _set_wood(amount: int) -> void:
	_wood_label.text = "Holz: %d" % amount


func _set_mana(amount: float) -> void:
	_mana_label.text = "Mana: %d" % int(amount)


func _set_population(population: int, capacity: int) -> void:
	_population_label.text = "Bevölkerung: %d/%d" % [population, capacity]
