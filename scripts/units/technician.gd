class_name Technician extends Brave

## Engineer, trained at the training hall (Ausbildungshalle, 10 s).
##
## Statistically a brave — same health, same speed, same base damage — with two
## differences and one speciality:
##  * melee: half kick, half punch, never a shove;
##  * civilian: he BUILDS and REPAIRS like a brave, but wood is not his job.
##    He takes what already lies around (pile or wood depot) for his own site
##    and never fells a tree, never gathers for the tribe's stock and never
##    mans a hut (that one comes for free — Hut._find_idle_brave_near and
##    Unit.order_man_hut both gate on unit_kind() == &"brave").
##  * speciality: aboard a vehicle he is worth far more than a brave — see
##    CrewedVehicle.technician_crew_count() for the bonuses he unlocks.
##
## Deriving from Brave rather than Unit is deliberate: building and repairing
## are ~700 lines of task machinery in brave.gd (job/task, _choose_job_task,
## _tick_construct, _tick_repair, seeking, claims) that are not separable
## without a project-wide refactor of every `Array[Brave]` and `is Brave`.


func _init() -> void:
	max_health = Balance.TECHNICIAN_HP
	health = max_health
	speed = Balance.TECHNICIAN_SPEED


func unit_kind() -> StringName:
	return &"technician"


## Half kick, half punch — no shove (user spec 2026-09-09).
func _shove_chance() -> float:
	return Balance.TECHNICIAN_SHOVE_CHANCE


func _kick_chance() -> float:
	return Balance.TECHNICIAN_KICK_CHANCE


## Wood is not his job: no felling, no gathering, no hauling. He still uses a
## pile or a depot that already sits at his own building site (Brave._try_fetch_wood).
func can_gather_wood() -> bool:
	return false


## Already trained: no retraining into a warrior/firewarrior/preacher. Without
## this the 10 s spent on him could be thrown away in a barracks.
func order_train(_building: TrainingBuilding) -> void:
	pass


## The forester is wood industry — not his trade.
func order_forester(_forester: Forester) -> void:
	pass


## Workshop duty means fetching stock wood and being housed; he stays outside
## and builds. Manning the finished VEHICLE is a different thing entirely and
## stays open to him (that is his whole point).
func order_workshop(_workshop: Workshop) -> void:
	pass
