# Phase 10g — KI: Bautrupps, Erreichbarkeit, Fahrzeuge, Holz, Kartengröße, Zielwahl

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Abhängigkeit:** [Phase 10f](10f_hut_upgrades.md) muss abgeschlossen und committet sein.

## Context

Phase 10e hat die KI *planen* gelehrt (Bauordnung als reine Funktion, Bauplatzsuche mit
Abstand und Ausrichtung, Fäll-Trupps, skalierende Fahrzeuglimits). Der Nutzertest zeigt: sie
**führt keine Logistik aus**. Für die letzten Meter verlässt sie sich überall auf passive
Engine-Mechanik, die nur im Umkreis der Basis greift.

| Fehlbild (Nutzerreport) | Verifizierte Ursache |
|---|---|
| „etliche Baustellen, ohne Leute zum Bauen hinzuschicken" | Der `AIController` ruft **nie** `commands.order_build`. Bauarbeiter kommen ausschließlich aus `BuildingManager._recruit_workers` — nur `State.IDLE`-Braves im **30-m**-Umkreis. Bauplätze liegen aber bis `AI_PLOT_SEARCH_RADIUS = 40` **Zellen** vom Siedlungsanker, und `_tick_wood_logistics` (4 Trupps × 6), `_staff_foresters`, `_staff_workshops` und `_tick_train` (bis 12/Tick) verbrauchen den Idle-Pool vorher restlos. **Nichts** reserviert Braves fürs Bauen, `parallel_site_count` erlaubt aber bis **8** gleichzeitige Baustellen. |
| „unerreichbare Gebäude platzieren" | Die Vorprüfung urteilt über die **Plotmitte** (`_plot_reachable`, A\* ab `base_anchor`), die Nachprüfung über den **Anlaufpunkt** (`_accept_or_scrap_site`, `approach_island()`). Zwei verschiedene Fragen ⇒ die KI setzt Bauplätze, die sie sofort wieder abreißt, oder eben nicht erkennt. Dazu: `_base_island() == -1` schaltet die Selbstheilung ganz ab („never scrap on a guess"), der Relax-Pass lässt die Freihaltung **komplett** fallen (Türschwelle zubaubar), und **nach** der Platzierung prüft nichts mehr — Landbrücke, Erdbeben, Absinken, Lava oder ein späteres Gebäude schneiden eine bestehende Baustelle ab. |
| „mehrere Werkstätten, aber da kam nie was raus" | `Workshop.exit_blocked()` ist die Falle: `_finish_catapult` bemannt das frische Fahrzeug **einmalig** mit ≤ 2 **idle Braves im 12-m-Radius**, `CrewedVehicle._tick_auto_recrew` zieht Militär nur aus **3 m**. Steht dort niemand, blockiert das Fahrzeug den Ausgang **dauerhaft** und die Werkstatt produziert nie wieder. Die KI ruft `order_crew` nur für Luftschiffe und liest `pending_engine`/`exit_blocked` **nie**. Dazu erlaubt `workshop_target(braves)` bis 4 Werkstätten **je Art** (12 gesamt), ohne zu prüfen, ob eine davon produziert. |
| „KI bezaubert den Reinkarnationskreis statt die Follower zu töten", „Kreis ist mit Katapult und Zeppelin-Feuerkriegern angreifbar" | **Beides bestätigt — und es ist ein Ziel-, kein Schadensbug:** `ReincarnationSite.take_damage`/`apply_destruction_stages`/`add_lava_contact` sind seit 10d **No-ops**, aber `Building.is_assailable_by_units()` wird an **vier** Stellen nicht geprüft: `CrewedVehicle.order_attack_building` **und** `_scan_enemy_building` (Katapult/Feuerramme, Spieler *und* KI), `Airship.order_attack_building` (Deck-Feuerkrieger) und die drei KI-Zielfunktionen `_nearest_enemy_building` / `_enemy_buildings_near` / `_attack_target_position`. Folge: Fahrzeuge parken dauerhaft vor einem unverwundbaren Ring, die KI verbrennt Blitz-/Vulkan-Ladungen daran, und ihre Angriffswelle marschiert auf ihn statt auf die Anhänger. Ursache der Lücken ist ein **veralteter 7g-Kommentar** in `building.gd` („only SPELLS and CATAPULTS may damage it … NOT gated by this flag"). |
| „auf kleinen Karten greift sie sofort mit den Braves an" | `DEFEND_RADIUS = 32.0` ist **fix**, die Basisabstände sind es nicht. `MapGenerator._circle_anchors` setzt die Anker auf einen Kreis mit Radius `0,2 · size`: **Insel (128) mit 4 Stämmen ⇒ nächste Nachbarbasis 36,2 Zellen** (3 Stämme 44,3; 2 Stämme 51,2) — also praktisch im Verteidigungsradius. Damit ist `_detect_threat()` **dauerhaft** nicht leer, und die Folgekette ist fatal: `_tick_wood_logistics` wird **permanent übersprungen**, `_tick_attack` läuft **nie** (`if threat.is_empty()`), und `_tick_defend` nimmt bei `core_power < enemy_count` **alle** idle Braves (`take_idle(idle_left())`) für `order_attack` — früh ist `core_power` nur die Schamanin (4,0), fünf gegnerische Einheiten in der Nähe genügen. Zum Vergleich: Plateau (128, Eckanker) hat 82 Zellen Abstand und ist unauffällig. |
| „Holz besser verteilen" | Es gibt **kein globales Holzlager** — Holz existiert nur als physische `WoodPile`s. Arbeiter holen ausschließlich selbst: Stapel bis `PILE_PREFER_RADIUS = 24 m` um die Baustelle, Bäume bis `JOB_TREE_RADIUS = 40 m`. Findet einer nichts → `mark_wood_stalled()` (30 s), der Rekrutierer **überspringt** die Baustelle, nach `CONSTRUCTION_STALL_TIMEOUT = 120 s` verfällt sie. Werkstätten kommen in der Bedarfsrechnung von `_tick_wood_logistics` **gar nicht** vor, und die Bauordnung setzt nie ein Lager an eine Werkstatt. |

**Ziel:** die KI transportiert Holz und Leute aktiv dorthin, wo sie gebraucht werden, räumt
eigene Layoutfehler selbst auf und passt ihr Verhalten an die Enge der Karte an. Kein neues
Spielsystem — durchweg vorhandene `TribeCommands`-Befehle und vorhandene Brave-Muster.

Die sechs Teile sind **unabhängig lieferbar**. Reihenfolge nach Wirkung pro Aufwand:
**Teil 6** (reiner Bugfix, keine neuen Konstanten), dann **Teil 1** (Bautrupps), dann **Teil 5**
für kleine Karten, dann 2–4.

## Nutzer-Festlegungen (2026-08-04)

- **Bauarbeiter: aktive Zuweisung + Budget.** Gezielte Zuweisung, Budget **vor**
  Training/Fäll-Trupps/Werkstattbesetzung reserviert, neue Baustelle nur, wenn die
  bestehenden versorgt sind.
- **Fahrzeug-Crew: Militär zuerst.** „Da der Fahrzeugbau eh erst nach dem Aufbau der
  Wirtschaft folgt, kann die KI hier auf Militäreinheiten zurückgreifen. Braves sollten nur
  genommen werden, wenn eh zu viele da sind oder Militäreinheiten Mangelware sind."
- **Kleine Karten:** die KI darf dort nicht sofort mit Braves angreifen; nach Nutzervorschlag
  **unterschiedliche Baumuster für kleine und große Karten** (Teil 5).
- **Reinkarnationsplatz: kein angreifbares Ziel — „auch für den Spieler nicht"** (Teil 6).
  Katapulte und Zeppelin-Feuerkrieger dürfen ihn also weder per Befehl noch per Auto-Zielsuche
  annehmen, und die KI-Zauberheuristik darf ihn nicht wählen.
- **Holznachschub: nur KI-intern** — kein Spielerbefehl, keine UI-Änderung. Die
  Architekturregel bleibt: die KI mutiert nur über `TribeCommands`; ein neuer Befehl dort ist
  erlaubt, solange **nichts** in `scripts\ui\` ihn aufruft (im Funktionskommentar festhalten).
- **Einordnung: Phase 10g, nach 10f.** 10f liegt im Arbeitsbaum bereits umgesetzt vor
  (uncommitted: `building.gd`, `hut.gd`, `balance.gd`, `tribe_commands.gd`, `sidebar.gd`,
  `brave.gd`) und bringt `AI_MAX_HUTS 30→60`, `AI_MAX_HUT_SITES 2→3` sowie einen **vierten
  Job-Typ** mit (`order_upgrade`, `Building.upgrading`/`upgrade_wood`). **10f muss committet
  sein, bevor 10g beginnt.**

---

## Bestandsaufnahme (vor der Umsetzung am Code verifiziert)

Zehn Befunde, die den Entwurf tragen. Jeder ändert eine naheliegende Entscheidung — sie
gehören deshalb in den Plan, nicht in Implementierungskommentare.

| # | Befund | Konsequenz |
|---|---|---|
| **F1** | Ein IDLE-Brave hat **immer** `job == null`: `Brave._tick_job` und `_stop_all()` rufen `_interrupt_tasks()` **vor** `_set_state(State.IDLE)`. | Wer nur über `cache.take_idle*` an Braves kommt, kann **strukturell** keinen arbeitenden Brave abziehen. Das befürchtete Thrashing (`_interrupt_tasks` wirft Holz ab, gibt Planierzelle und Baumclaim frei) ist unmöglich — **kein** „schon zugewiesen"-Buch nötig. |
| **F2** | `Brave._tick_job` prüft `worker_can_reach` **einmal pro Sekunde selbst** und verlässt den Job. | Die Nachkontrolle muss nur die **Baustelle** einsammeln, nie die Arbeiter. |
| **F3** | `Building.begin_demolish()` lässt `under_construction == true`, wenn `has_build_stage()`. Ein Abriss-Gebäude steht damit **in `cache.sites`**. | `demolishing` muss in Bestückung, Tor und Holzbedarf **explizit** übersprungen werden, sonst schickt die KI Bauarbeiter zum Abreißen und zählt den Slot als Baustelle. |
| **F4** | `NavGrid`-Inseln sind die Zusammenhangskomponenten **genau derselben** Solid-Map, die `AStarGrid2D` nutzt; 4-Nachbarschaft ist äquivalent zu `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` (eine Diagonale verlangt beide Orthogonal-Nachbarn frei — dann sind die Zellen schon 4-verbunden). | Ein Inselvergleich ist **keine Näherung** von `find_path`, sondern dieselbe Relation. `_plot_reachable` darf das teure A\* ersetzen, **ohne Genauigkeit zu verlieren** — und wird dabei billiger. |
| **F5** | `Building.delivery_point()` = `edge_spawn_position()` prüft `entrance_cell()`, dann die Ringe `grow 1..3`. `approach_island()` ist die Insel **dieser** Zelle, gecacht gegen `change_version`. | Zieht man diese Zellwahl als **statische** Funktion heraus, urteilt die Sweep-Prüfung **identisch** zu `_accept_or_scrap_site` → „platzieren und sofort abreißen" verschwindet ganz. Der 3-Ring-Deckel ersetzt exakt die alte 3,0-m-Endpunkttoleranz des A\*. |
| **F6** | `wood_stalled` löscht sich nach `WOOD_RECHECK_INTERVAL = 30 s` selbst bzw. sofort bei eintreffendem Holz. | „Stalled-Baustellen nicht bestücken" ist per Konstruktion temporär, keine Sackgasse. |
| **F7** | `Brave.BUILD_RATE = 0.2`/s ⇒ **5 Arbeitersekunden** stellen ein Gebäude fertig, sobald Holz da ist. `FLATTEN_RATE = 0.5` m/s gilt **pro Arbeiter pro Zelle**, `claim_flatten_cell` gibt eine Zelle je Arbeiter aus. | Nur die **Planierphase** ist handhungrig (skaliert mit der Grundrissfläche); die Bauphase ist **holz**hungrig. Genau so muss die Truppgröße gerechnet werden. |
| **F8** | `building.gd`: `if not demolishing: _tick_decay(delta)`. | **Load-bearing:** eine `demolishing`-Baustelle mit Baustufe, die kein Arbeiter erreicht, verfällt **nie** und wird **nie** fertig — sie blockiert den Bauslot **für immer**. Ein naives „bei Fehlschlag abreißen" wäre schlimmer als der Bug. |
| **F9** | `DEMOLISH_REFUND_UNBUILT = 1.0`, `DEMOLISH_REFUND_BUILT = 0.75`, `CONSTRUCTION_STALL_REFUND = 1.0`. | Abreißen ist **nur** bei `build_progress == 0` gut (sofort, 100 %). Ab Baustufe ist Verfallenlassen sowohl erstattungsseitig (100 % statt 75 %) als auch mechanisch (F8) überlegen. |
| **F10** | `Workshop._tick_active` läuft **jeden Physikframe**. Solange nicht produziert wird, wertet es `wants_more_stock_wood()` → `stock_wood()` → `piles_in_radius()` über **alle** Stapel und `_pile_reserved_by_peer()` je Stapel über **alle** Gebäude aus. Sobald `production_active`, kehrt es früh zurück. | Eine leere, unversorgte Werkstatt ist das **teuerste Gebäude im Spiel**. Werkstätten zu füttern und weniger davon zu bauen ist damit gleichzeitig ein **Performance**-Gewinn — und die KI darf `wants_more_stock_wood()`/`stock_wood()` **niemals selbst** aufrufen. |

Nebenbefund: `destroy()` emittiert `building_destroyed`, der KI-Handler setzt
`_rebuild_ticks = REBUILD_COOLDOWN_TICKS (15)`. **Jeder Selbstabriss pausiert den eigenen Bau
15 s** — das gilt schon heute für `_accept_or_scrap_site` und ist bisher unbemerkt.

---

## Teil 1 — Bautrupps und Budget

### 1.1 Neue reine Statics in `scripts\ai\ai_state.gd`

```gdscript
## Arbeiter, die EINE Baustelle bekommen soll. Zwei Regime, weil die beiden
## Bauphasen an verschiedenen Dingen haengen (F7): Planieren ist ZELLarbeit,
## nach `foundation_done` zaehlt nur noch Holznachschub.
## Der Deckel liegt BEWUSST unter Building.MAX_WORKERS (10) — die freien Plaetze
## bleiben dem passiven BuildingManager._recruit_workers.
static func site_worker_target(footprint_cells: int, needs_flatten: bool,
		wood_missing: int) -> int

## Braves, die die KI in diesem Tick ans Bauen bindet — VOR Training, Faell-Trupps
## und Werkstattbesetzung. Das Budget lebt INNERHALB der Wirtschaftsmannschaft,
## die min_economy_braves() ohnehin aus dem Training haelt: Bauen frisst nicht den
## Armee-Anteil, es entscheidet nur, was die Wirtschaft ZUERST tut.
static func builder_budget(braves: int, population: int, site_demand: int) -> int

## Tor-Praedikat fuer eine NEUE Baustelle (rein, damit der Verklemmungsschutz
## ohne Welt testbar ist).
static func site_is_supplied(workers: int, wood_stalled: bool,
		waited_ticks: int) -> bool

## Pendel-Trupps fuer vorgeschobene Lager (heute in _tick_forward_haul hart 2).
static func haul_crew_count(braves: int) -> int
```

- `site_worker_target`: planierend `ceil(footprint_cells / AI_FLATTEN_CELLS_PER_WORKER)`,
  geklemmt `AI_SITE_WORKERS_MIN .. AI_SITE_WORKERS_MAX`; danach
  `AI_SITE_WORKERS_MIN + wood_missing / AI_WOOD_PER_EXTRA_BUILDER`, geklemmt auf
  `AI_SITE_WORKERS_BUILD_MAX`. Hütte 4×4/8 Holz → 3 dann 3; Feuerkriegerlager 8×8/20 Holz
  → 8 dann 5; 1×1-Lager → 2.
- `builder_budget = clampi(mini(site_demand, max(AI_MIN_BUILDER_BRAVES, braves * AI_BUILDER_BRAVE_SHARE)), 0, min_economy_braves(population))`.
  Die harte Klemmung auf `min_economy_braves` ist der **einzige** Berührungspunkt beider
  Größen und ist headless testbar.
- `site_is_supplied = workers >= AI_SITE_SUPPLIED_WORKERS or wood_stalled or waited_ticks >= AI_SITE_SUPPLY_GRACE_TICKS`.
  Klausel 2: eine holzhungrige Baustelle gehört der Holzlogistik, nicht dem Bautrupp-Tor.
  Klausel 3 ist der Verklemmungsschutz.

**Bewusst keine `_staff_*`-artige Sperre `if brave_count <= min_economy_braves: return`.**
Förster- und Werkstattdienst binden *dauerhaft*, Bauen ist endlich und Voraussetzung für alles
andere. Der Anteilsdeckel plus `AI_MIN_BUILDER_BRAVES = 4` erfüllt denselben Zweck, ohne das
Frühspiel abzuschalten (10 Braves → Budget 4, 6 bleiben für Holz und Training).

### 1.2 Tick-Reihenfolge — Umsortierung, **kein** Reservierungsfeld

Der Idle-Pool ist bereits **verbrauchend**: wer zuerst zieht, hat reserviert. Ein
Reservierungsfeld auf der `TickCache` wäre nur nötig, um Braves über den Tick hinaus
*freizuhalten* — und das ist falsch: was in diesem Tick nicht zugewiesen werden kann
(Baustelle voll, niemand erreichbar), wird auch im nächsten nicht zugewiesen; Freihalten würde
nur Braves untätig parken.

```
Cache -> State -> _detect_threat() -> Fahrzeuglimits
  -> _tick_site_guard(cache)      # NEU, gedrosselt: gibt TOTE Slots frei, BEVOR gebaut wird
  -> _tick_build(cache)           # + Versorgungs-Tor (1.4)
  -> _tick_build_crews(cache)     # NEU: zieht ZUERST aus dem Idle-Pool
  -> _tick_wood_logistics(cache) + _tick_shop_supply(cache)   # nur ohne ERNSTE Bedrohung (5.2.3)
  -> _tick_vehicle_crews(cache)   # NEU, VOR den Tuermen (geteilter FW-Pool)
  -> _staff_foresters -> _staff_workshops -> _man_watchtowers -> _man_airships
  -> _cast_spells -> _tick_defend (bei Bedrohung) -> _tick_train / _tick_attack
```

Drei begründete Details:

- **Guard vor `_tick_build`**, damit ein soeben freigegebener Slot im selben Tick nachbesetzt
  wird. Der Guard ist damit der **einzige** Teil, der das Per-Tick-Read-Model bricht (er
  zerstört ein Element von `cache.sites`) — er muss den Eintrag deshalb selbst aus
  `cache.sites`/`cache.stalled_sites` entfernen, und alle Konsumenten prüfen
  `is_instance_valid` **und** `health > 0`.
- **`_tick_build_crews` nach `_tick_build`**, damit eine im selben Tick eröffnete Baustelle
  sofort ihren Trupp bekommt. Das Tor urteilt dadurch über den Stand des **Vortticks** — ein
  Tick Beweislage, was gewollt ist.
- **Bautrupps laufen auch unter Bedrohung** (anders als die Holztrupps). Ein Bautrupp sind
  2–8 Braves am Dorf, ein Holztrupp 6–24 quer über die Karte, und die Miliz mobilisiert nur
  bei `core_power < enemy_count`. Zweiter, harter Grund: `test_ai_tick_cache_walks_units_once_per_tick`
  baut eine Welt mit Feind im `DEFEND_RADIUS` und garantiert, dass **kein** Zweig früh
  zurückspringt — eine Bedrohungssperre würde diesen Regressionswächter still entwerten.
  Falls der Spieltest die Miliz zu dünn zeigt: unter Bedrohung nur Baustellen mit
  `workers.size() == 0` und nur bis `AI_SITE_WORKERS_MIN`.

### 1.3 `_tick_build_crews(cache) -> int`

Neue Cache-Primitive:

```gdscript
## Nimmt bis zu `count` noch idle Braves, die der Baustelle am NAECHSTEN stehen und
## deren Insel ihr Anlaufpunkt akzeptiert. Naechste-zuerst ist noetig, weil die alte
## Expansions-Eskorte nahm, was pop_back() lieferte — ein Brave 80 m weit laeuft bei
## BRAVE_SPEED 4.0 zwanzig Sekunden, bevor er den Platz beruehrt. Der Inselfilter ist
## ein gecachter Array-Lookup je Kandidat und verhindert, dass order_build Braves
## still verwirft, die wir schon aus dem Pool genommen haben.
func take_idle_for(site: Building, count: int, max_dist: float) -> Array[Unit]
```

Ablauf:

1. `_site_notes` neu aufbauen (1.5) — jeden Tick, damit die Buchführung nie leckt.
2. **Filter.** Übersprungen: ungültig / `health <= 0` · **`demolishing` (F3)** ·
   **`wood_stalled` (F6)** — ein Arbeiter ohne Holzquelle setzt in seinem nächsten Tick
   wieder `mark_wood_stalled()` + `_stop_all()`, fällt in denselben Pool zurück und wirft
   dabei getragenes Holz ab: genau das Ein-Tick-Thrashing, das wir vermeiden ·
   `approach_island() < 0` · `not has_worker_room()` · `note.retry_until > _tick_count` ·
   `note.abandoned`.
3. **Sortierung: am stärksten unterversorgt zuerst**, Gleichstand → näher an `base_anchor`.
   *Nicht* nächste-zuerst: die nahen Baustellen deckt der passive Rekrutierer (30 m) schon
   ab; ein begrenztes Budget nächste-zuerst zu verteilen verbrennt es dort, wo es nicht
   gebraucht wird, und lässt die fernen Baustellen — den Bug — leer. `cache.sites` hat ≤ 8
   Einträge.
4. **Zuweisen**, höchstens `AI_SITES_STAFFED_PER_TICK` Baustellen pro Tick:
   ```gdscript
   var want: int = mini(mini(deficit, Building.MAX_WORKERS - site.workers.size()), budget_left)
   var crew: Array[Unit] = cache.take_idle_for(site, want, dist)
   var got: int = commands.order_build(crew, site)
   budget_left -= crew.size()          # ehrlich: verbrauchte Braves, nicht nur zugewiesene
   if got == 0 and not crew.is_empty():
       note.retry_until = _tick_count + Balance.AI_SITE_RETRY_TICKS
   ```
   `dist = Balance.AI_BUILDER_WALK_RADIUS` (80 m), **Ausnahme:** eine Baustelle mit
   `workers.size() == 0` bekommt ihre `AI_SITE_WORKERS_MIN` Braves **entfernungsunabhängig**
   (`INF`) — „gar niemand" ist der gemeldete Fehler und schlägt jede Laufoptimierung.
5. `_send_escort_if_remote` aus `_tick_build` **entfernen** — `order_build` ist strikt besser
   als eine `order_move`-Eskorte, die darauf hofft, dass der Rekrutierer die Braves aufsammelt
   (und die bei `wood_stalled` gar nicht funktionieren kann). Für **stalled** Baustellen
   bleibt der Aufruf in `_tick_wood_logistics`, dort ergänzt durch den Nachschub aus Teil 4.

**Zusammenspiel mit `BuildingManager._recruit_workers`:** bleibt **unverändert** (das ist auch
der Spielerpfad). Der Vertrag ist numerisch: die KI weist nie über `AI_SITE_WORKERS_MAX = 8`
zu, `MAX_WORKERS` ist 10 → zwei Plätze bleiben immer dem passiven Rekrutierer.
Doppelbeauftragung ist ausgeschlossen (ein passiv rekrutierter Brave ist nicht mehr IDLE, und
`workers.size()` ist gewachsen). `wood_stalled`- und `approach_island() < 0`-Filter sind in
beiden Systemen identisch — bewusst, damit es genau **eine** Wahrheit gibt, welche Baustelle
bedienbar ist. Den globalen `RECRUIT_RADIUS` **nicht** anheben (wirkt auch für den Spieler).

### 1.4 Tor: „erst versorgen, dann eröffnen"

In `_tick_build` **nach** der `max_sites`-Prüfung und **vor** `next_building_kind(cache)`:

```gdscript
if not _all_sites_supplied(cache):
    return   # keine Baustelle eroeffnen, die niemand besetzen kann (Nutzerreport)
```

`_all_sites_supplied` überspringt ungültige, `demolishing` (F3) und `abandoned` Baustellen und
fragt sonst `AIState.site_is_supplied(site.workers.size(), site.wood_stalled, waited)`.
`note.unsupplied_since` wird in `_tick_build_crews` gepflegt.

**Verklemmungsschutz, vierfach:** Gnadenfrist `AI_SITE_SUPPLY_GRACE_TICKS = 30` (eine
Baustelle blockiert höchstens 30 s) · `wood_stalled` blockiert nie · `abandoned` blockiert nie
· `CONSTRUCTION_STALL_TIMEOUT` räumt jede fortschrittslose Baustelle nach 120 s mit **voller**
Erstattung ab (F9).

**Nebengewinn:** das Tor greift **vor** `_find_plot` — laut PROGRESS.md dem teuersten
KI-Posten bei den Benchmark-Bevölkerungen. Jeder blockierte Tick spart eine komplette
Ringsuche. Das ist die Gegenrechnung zu allem, was diese Phase kostet.

**Bestehender Test bleibt grün (durchgerechnet):** `test_build_tick_places_construction_site`
erwartet die zweite Baustelle bei 20 Braves. Tick 1 setzt die Hütte (keine Baustelle → Tor
offen), `_tick_build_crews` bestückt sie mit `site_worker_target(16, false, 8) = 3` Braves aus
10 idle auf flachem Terrain ⇒ versorgt. Tick 3 (20 Braves, `max_sites = 2`) ⇒ Tor offen ⇒
Kriegerlager. **Keine Testanpassung nötig.**

### 1.5 Buchführung: **eine** innere Klasse statt vier Dictionaries

```gdscript
## Buchfuehrung pro Baustelle fuer Bestueckung und Nachkontrolle. Ueber die
## instance id gefuehrt (nie ueber die Referenz — eine verworfene Baustelle darf
## nicht am Leben gehalten werden) und in JEDEM Tick aus cache.sites neu aufgebaut,
## damit sie nicht lecken kann: hoechstens AI_MAX_PARALLEL_SITES Eintraege.
class SiteNote extends RefCounted:
	var unsupplied_since: int = -1   ## Tick, ab dem sie handhungrig aussah
	var strikes: int = 0             ## Guard-Laeufe, die sie abgeschnitten sahen
	var retry_until: int = -1        ## Tick, bis zu dem die Bestueckung sie ueberspringt
	var abandoned: bool = false      ## abgeschnitten MIT Baustufe: Haende weg, verfallen lassen
```

---

## Teil 2 — Erreichbarkeit: eine Wahrheit, plus Nachkontrolle

### 2.1 `_plot_reachable`: Inselvergleich am **Anlaufpunkt** statt A\* zur Plotmitte

Der eigentliche Hebel — und er ist **billiger** als heute.

Neu in `scripts\buildings\building.gd` (eine Wahrheit für beide Pfade, reines Refactoring der
bestehenden Zeilen von `entrance_cell()` / `edge_spawn_position()`):

```gdscript
const APPROACH_SEARCH_RINGS: int = 3

static func entrance_cell_for(cell: Vector2i, footprint: Vector2i,
		orientation: int) -> Vector2i

## Zelle, auf der Arbeiter tatsaechlich stehen, um ein Gebaeude mit diesem
## Grundriss, dieser Ausrichtung und dieser Ursprungszelle zu bedienen: die
## Eingangszelle, wenn begehbar, sonst die naechste begehbare Randzelle innerhalb
## APPROACH_SEARCH_RINGS. STATISCH mit Absicht — die KI muss die Frage fuer einen
## Bauplatz stellen, auf dem noch kein Gebaeude steht, und BEIDE Pfade muessen sich
## auf dieselbe Zelle einigen (sonst urteilen Sweep und _accept_or_scrap_site
## verschieden und die KI setzt Baustellen, die sie sofort wieder abreisst).
## (-1, -1) = diesen Bauplatz kann niemand je bedienen.
static func approach_cell_for(nav: NavGrid, cell: Vector2i, footprint: Vector2i,
		orientation: int) -> Vector2i
```

Controller: `_plot_reachable(cell, footprint, orientation)` prüft Bann (mit Ablauf) →
`approach_cell_for(...)`; `(-1,-1)` ⇒ **abgelehnt** (neu, und fängt genau „Eingang zugebaut /
von Wasser umschlossen") → `nav_grid.island_at(approach)` gegen `_home_islands(cache)`.
Begründung im Kommentar: **F4** (kein Genauigkeitsverlust) und **F5** (identisches Urteil).

Folgen:

- **`_reachable_plots` (Positiv-Cache) entfällt** — einen Array-Lookup zu cachen ist teurer
  als der Lookup. Damit fällt `test_plot_reachable_success_cache` weg und wird durch zwei
  bessere Tests ersetzt. **Das ist die einzige bewusste Test-Löschung dieser Phase** und muss
  in PROGRESS.md als Abweichung stehen.
- `_plot_candidates_left` verliert seinen teuren Verbraucher. **Budgets trotzdem unverändert
  lassen** (weiter beim Erreichbarkeits-Fehlschlag dekrementieren): sie sind dann
  Sicherheitsnetz statt Kostenbremse. Sie *anzuheben* wäre eine zweite, separat zu messende
  Änderung — genau der Fehler, der in 10e zur 3–4×-Regression führte.

### 2.2 Erreichbar für **irgendeinen** Arbeiter, nicht nur ab `base_anchor`

Als **Inselmenge**, nicht als A\* vom Arbeiter:

```gdscript
## Inseln, auf die der Stamm Haende bekommt: die Basisinsel plus die Inseln, auf
## denen seine IDLE-Braves stehen (ein Trupp, der eine Landbruecke ueberquert hat,
## zaehlt). Hoechstens EINMAL pro Tick und nur LAZY — die Basisinsel beantwortet
## fast jede Frage, die Schleife ueber den Idle-Pool wird nur bezahlt, wenn ein
## Kandidat woanders liegt. Absichtlich NICHT aus den eigenen Gebaeuden abgeleitet:
## approach_island() rescannt bis APPROACH_SEARCH_RINGS nach jeder
## Begehbarkeitsaenderung, und die KI bumpt change_version bei jeder Platzierung.
func _home_islands(cache: TickCache) -> Dictionary
```

Mit `cache == null` (Direktaufrufe aus Tests wie `test_expansion_toward_wood`) enthält die
Menge nur die Basisinsel ⇒ Altverhalten, keine Testanpassung.

### 2.3 `_base_island() == -1` behoben

`_home_island(cache)`: `nearest_walkable_cell(base_anchor)` wie heute; bei −1 die Insel der
eigenen idle Braves. Nur ein Stamm ohne begehbare Basis **und** ohne einen einzigen platzierten
Brave bleibt permissiv. `_accept_or_scrap_site(site, cell, cache := null)` bekommt den Cache
als **optionalen** Parameter (der bestehende Zweiargument-Aufruf im Test kompiliert weiter) und
urteilt über `_home_islands(cache)` — damit sind Vorabprüfung, Annahme und Nachkontrolle
**dieselbe** Funktion (F5).

### 2.4 Relax-Pass: abgestuft statt „ohne Prüfung"

`require_clearance: bool` → `spacing: int`.

- Durchgang 1: `AI_PLOT_SPACING` (2).
- Durchgang 2 (nur Basis): **`AI_PLOT_SPACING_RELAXED = 1`** statt 0. Ein Ring Luft ist der
  Unterschied zwischen „eng gebaut" und „Eingang zugemauert" und kostet `(fp+2)²` statt
  `(fp+4)²` Lookups.
- **Immer, in beiden Durchgängen:** die Anlaufzellen-Prüfung aus 2.1. Der Relax-Pass darf
  Abstand entspannen, aber **nie** die Erreichbarkeit der Tür — genau das ist heute die Lücke,
  denn 10e prüft im Relax-Pass nur die Plotmitte gegen die Basis.
- Reihenfolge bleibt strikt nach Kosten (10e-Lehre): `can_place_at` → Baumzahl
  (bucket-indiziert) → Freihaltung → Anlaufzelle + Insel. Letzteres ist jetzt das
  **billigste** der teuren Dinge, nicht mehr das teuerste.

### 2.5 `_tick_site_guard(cache)` — Nachkontrolle bestehender Baustellen

Alle `AI_SITE_GUARD_INTERVAL` Ticks über `cache.sites` (**kein** zusätzlicher
Gebäude-Durchlauf — `test_ai_tick_cache_walks_units_once_per_tick` nagelt das fest). Kosten je
Baustelle: **ein** Vergleich zweier ints, die beide schon gegen `change_version` gecacht sind.
Nie `find_path`, kein neuer Insel-Auslöser, den die KI nicht schon hätte.

- `ok = island >= 0 and _home_islands(cache).has(island)` → `note.strikes = 0`.
- sonst `note.strikes += 1`. **Zwei Strikes** (`AI_SITE_GUARD_STRIKES`, also 2 × 5 = 10 s)
  sind Pflicht: Insel-Labels dürfen bis `ISLAND_REFRESH_MS = 1000` veralten, und mitten in
  einer wachsenden Landbrücke ist ein einzelner Fehlschlag nichts.
- Bei `strikes >= AI_SITE_GUARD_STRIKES`, **höchstens eine Baustelle pro Guard-Lauf**:

| Zustand | Aktion | Grund |
|---|---|---|
| `not site.has_build_stage()` | `commands.demolish_building`, Zelle bannen, Eintrag aus `cache.sites`/`cache.stalled_sites` entfernen | 10d: sofort weg, **100 %** Erstattung, Slot im selben Tick frei |
| `site.has_build_stage()` | **nicht** abreißen: `note.abandoned = true` (keine Bestückung, blockiert das Tor nicht), Zelle bannen, Verfall übernimmt | **F8 + F9**: `begin_demolish()` macht daraus einen *Arbeiter*-Job und schaltet `_tick_decay` ab — ohne erreichbare Arbeiter blockiert die Baustelle den Slot **für immer**. Verfallen bringt zudem 100 % statt 75 % |

**Kein Platzier-/Abriss-Zyklus, vierfach:** Zellbann · zwei Strikes · höchstens ein Abriss pro
Lauf · die Vorabprüfung ist ab 2.1 **identisch** mit dem Urteil des Guards (F5), der Sweep kann
eine gebannte oder falsch angeschlossene Zelle gar nicht mehr vorschlagen.

**Bann mit Ablauf statt „für immer":** `_unreachable_plots` speichert künftig den Ablauf-Tick
statt `true`. `_unreachable_plots.has(cell)` bleibt wahr ⇒
`test_ai_discards_a_site_with_no_walkable_approach` kompiliert und besteht unverändert. Der
Ablauf behebt einen latenten Fehler: heute bleibt eine Zelle die **ganze Sitzung** gesperrt,
auch nachdem eine Landbrücke sie angeschlossen hat.

**Zusatz (klein, empfohlen):** ein `_self_scrap`-Flag um den Abriss legen und in
`_on_building_destroyed` respektieren — sonst löst jeder Selbstabriss `_rebuild_ticks = 15`
aus und pausiert den eigenen Bau 15 s. Gilt auch für das bestehende `_accept_or_scrap_site`.

---

## Teil 3 — Fahrzeuge: Abholung und Ausfahrt

### 3.1 `_tick_vehicle_crews(cache)`

Neue `TickCache`-Felder, **im vorhandenen Einzeldurchlauf** gefüllt (kein zusätzlicher Pass):

- `_idle_warriors: Array[Unit]` + `take_idle_warrior(n)` / `idle_warrior_left()`, delegiert an
  die bestehenden `_take`/`_left`-Statics — damit prüft auch die Krieger-Entnahme bei jeder
  Ausgabe erneut `State.IDLE` (der 10e-Bug, bei dem zwei Subsysteme denselben Feuerkrieger
  beauftragten).
- `ground_vehicles: Array[Unit]` — `&"siege"` und `&"fireram"`, aus dem bestehenden
  Drei-Arten-Zweig herausgezogen.
- `blocked_shops: Array[Building]` — nutzbare Werkstätten mit `exit_blocked()` (O(1)).

Läuft **vor** `_man_watchtowers`/`_man_airships`, damit ein blockierendes Fahrzeug den
geteilten Feuerkrieger-Pool zuerst sieht: eine blockierte Werkstatt freizumachen ist mehr wert
als eine Turmgarnison.

**Durchgang 1 — freimachen (Vorrang, läuft in JEDEM Zustand, auch unter Bedrohung).**
Für jede `blocked_shops`-Werkstatt: `e = ws.pending_engine`; ist
`e.boarded_count() < e.min_move_crew`, genau so viele Einheiten bestellen, dass
`min_move_crew` (= 1 bei allen drei Arten) erreicht wird. **Eine** Einheit befreit eine
Werkstatt — dieser Durchgang ist absichtlich geizig.

**Durchgang 2 — auffüllen** (übersprungen unter Bedrohung), Round-Robin, höchstens
`AI_VEHICLES_PER_TICK` Fahrzeuge:

```gdscript
## Zielbesatzung: genug, um zu FEUERN, plus einer — die Nachladezeit skaliert mit
## der Besatzung (SiegeEngine.fire_cooldown_for_crew).
func _target_crew(v: CrewedVehicle) -> int:
    return clampi(v.min_fire_crew + Balance.AI_VEHICLE_EXTRA_CREW,
        v.min_move_crew, v.max_crew)
```
→ Katapult 3 (`SIEGE_MIN_FIRE_CREW = 2`), Feuerramme 2, Luftschiff 2.

**Kandidatenreihenfolge** (Nutzerregel „Militär zuerst"):

1. **Idle Krieger** (neuer Pool).
2. **Idle Feuerkrieger** über `cache.take_idle_fw()`, aber nur solange
   `cache.idle_fw_left() > WATCHTOWER_MIN_MOBILE_FW` — exakt die Reserveregel, die
   `_man_watchtowers` und `_man_airships` schon teilen, damit die drei Verbraucher sich nicht
   aushungern.
3. **Prediger: ausgeschlossen.** Mechanisch erlaubt (`can_crew_siege()` sperrt nur Schamanin
   und Fahrzeuge), aber ein Prediger in `State.CREW` fällt aus `cache.army`, bekehrt nichts —
   und die KI zielt seit 10e bewusst auf 30 % Prediger. Ein Ein-Zeilen-Filter.
4. **Braves nur als Notnagel**, unter ausdrücklicher Überschussregel:
   ```gdscript
   func _braves_may_crew(cache: TickCache) -> bool:
       var spare: int = cache.brave_count - AIState.min_economy_braves(cache.population)
       return spare >= Balance.AI_VEHICLE_BRAVE_SURPLUS \
           or cache.army_count < Balance.AI_VEHICLE_MILITARY_SCARCE
   ```

**Die Armee wird nicht ausgeplündert — drei unabhängige Bremsen:**
(a) globales Budget: nie mehr als `AI_VEHICLE_ARMY_CREW_SHARE` (0,25) von `cache.army_count`
in Fahrzeugbesatzungen; die Differenz `army_count - army.size()` **ist** die Zahl der
Armee-Einheiten in `State.CREW` (der Cache zählt jede Kampfeinheit in `army_count`, überspringt
aber `State.CREW` für `cache.army`). (b) Boden: Abbruch bei
`cache.army.size() <= AIState.ARMY_RETREAT_SIZE` (4). (c) `AI_VEHICLES_PER_TICK`-Drossel, damit
eine frische Fahrzeugwelle über mehrere Sekunden bemannt wird.
Die State-Machine bleibt unberührt: `make_snapshot()` liest `cache.army_count`, das
`State.CREW` mitzählt — Bemannen kann den ATTACK→TRAIN-Rückzug nicht auslösen. Nur der
marschierende Trupp ändert sich: 2 Krieger werden 1 Katapult-Eintrag. Das ist der gewollte
Handel.

### 3.2 Sammelpunkt an der Werkstatt

Verifiziert: `BuildingManager._default_rally_point` legt den Rally Point auf die
**Eingangszelle**; `Workshop._dispatch_point()` verwirft ihn dann (näher als
`EXIT_CLEAR_RADIUS + 0.5`) und schickt das Fahrzeug 5 m die Eingangsnormale hinaus. Das
*reicht*, um `exit_blocked()` zu lösen — **der Blocker ist ausschließlich die fehlende
Besatzung.** Der Sammelpunkt ist Ordnung, nicht der Fix: unbemannte Fahrzeuge sind über
`_refresh_nav_block()` Navigationshindernisse, und ein Strom davon direkt vor dem Tor verstopft
den nächsten.

`_muster_point(shop)`: `nearest_walkable_cell` eines Punkts `AI_VEHICLE_MUSTER_DISTANCE` (12 m)
vor dem Eingang in Richtung `base_anchor` (BUILD/TRAIN) bzw. `_attack_target_position()`
(ATTACK). **Einmal je Werkstatt** gesetzt, erneuert nur bei Zustandswechsel oder wenn der Punkt
unbegehbar wird (`change_version`-Vergleich) — **nicht** jeden Tick, sonst zielt
`_dispatch_point()` geparkte Fahrzeuge neu.

`building.rally_point` direkt zu schreiben wäre eine Direktmutation, also ein neuer Befehl:

```gdscript
## Setzt den Sammelpunkt eines eigenen Gebaeudes (KI-Fahrzeugmuster). Die UI setzt
## ihn weiterhin direkt in SelectionManager._set_rally — hier unveraendert.
func set_rally_point(tribe: Tribe, building: Building, target: Vector3) -> bool
```
prüft `_tribe_active`, Eigentum, und snappt auf `nearest_walkable_cell`. **Dokumentierte
Inkonsistenz:** damit gibt es zwei Schreiber; die UI auf den Befehl zu migrieren wäre eine
UI-Änderung und ist per Nutzerentscheidung außerhalb dieser Phase.

### 3.3 Werkstattzahl an tatsächliche Produktion binden

`workshop_target(braves)` erlaubt bis 4 Werkstätten **je Art** → 12 Stück, zusammen ~170 Holz,
die unversorgt nichts produzieren und laut **F10** je Stück `O(Stapel × Gebäude)` **pro
Physikframe** kosten.

```gdscript
## Unproduktiv = produziert nicht und kann es auch nicht: kein Holz in Reichweite,
## niemand drinnen, oder Ausgang blockiert. Wer BY DESIGN stillsteht (Limit
## erreicht, pausiert), ist kein Fehlschlag. Kein Stapel-Scan: wood_stalled ist ein
## bool, exit_blocked() eine Distanz, inside_count() O(<=4).
func _shop_is_unproductive(ws: Workshop) -> bool:
	if ws.production_active or ws.paused or ws.product_cap_reached():
		return false
	return ws.wood_stalled or ws.inside_count() == 0 or ws.exit_blocked()
```

Neuer reiner `counts`-Schlüssel `shops_unproductive`; alle drei Werkstatt-Zweige in
`next_building_kind` werden auf `shops_unproductive == 0` gegattert. Was das bewusst **nicht**
tut: es blockiert nicht die *erste* Werkstatt einer Art (bei null Werkstätten ist der Zähler 0)
und es hält die Bauordnung nicht an — Wachturm und Zusatzlager stehen dahinter und feuern
weiter, ein dauerhaft ausgehungerter Werkstatt-Cluster lenkt die Investition also um statt den
Bau einzufrieren. Und weil eine frisch fertige Werkstatt `inside_count() == 0` hat, bis
`_staff_workshops` sie füllt, erzwingt das Tor von selbst „Werkstatt N+1 erst, wenn N besetzt
**und** versorgt **und** frei ist".

---

## Teil 4 — Holzverteilung

### 4.1 Gezielter Nachschub-Auftrag (KI-intern)

**`scripts\units\brave.gd`** — neues Feld `_supply_target: Building` **parallel** zum
vorhandenen `_haul_target: WoodDepot`. Begründung: `_haul_target` ist nicht bloß als Depot
*typisiert*, seine Semantik ist Depot-Semantik (`_haul_valid()` und der Festziel-Zweig in
`_tick_loose_deliver` gattern auf `storage_left() > 0`, und die „Ziel weg/voll"-Rückfallebene
beendet die Pendelei). Eine Baustelle hat kein `storage_left()`, ihr „voll"-Prädikat ist
`wants_more_wood()`. Den Typ zu weiten hieße `is WoodDepot`-Tests **innerhalb** von
`_haul_valid()` und im Pendel-Schwanz — gleich viele Zweige wie ein zweites Feld, aber die
Invarianten des durch Tests abgesicherten `order_depot_haul` über Typtests verstreut.

Um die „Festziel"-Logik nicht zu duplizieren, lesen beide über zwei neue Helfer:

```gdscript
## Festes Lieferziel dieser Fuhre (Depot-Pendel / Stapel-Relais zuerst, dann ein
## Nachschubauftrag), sonst null = ab ans naechste eigene Gebaeude.
func _fixed_delivery_target() -> Building
## Ob dieses Ziel noch Holz nehmen kann. DIE eine Stelle, die das Praedikat je
## Gebaeudeart kennt.
func _fixed_target_wants_wood(target: Building) -> bool
```

| Zielart | Prädikat |
|---|---|
| `WoodDepot` | `is_usable() and storage_left() > 0` (Verhalten unverändert) |
| `Workshop` (inkl. Unterklassen) | `is_usable() and wants_more_stock_wood()` |
| Baustelle | `wants_more_wood()` |
| beschädigt, fertig | `wants_more_repair_wood()` |
| `upgrading` (10f) | `wants_upgrade_wood()` |
| sonst | `false` |

**Auf der Zielseite ist kein neuer Code nötig:** `_tick_loose_deliver` legt bei `WoodDepot` ins
Regal und sonst einen Bodenstapel ab — und ein Bodenstapel am `delivery_point()` **ist** die
Lieferung (`Building._absorb_piles()`, `Workshop.stock_wood()`).

Berührte Funktionen:

| Funktion | Änderung |
|---|---|
| `order_supply_wood(target) -> bool` (neu) | `can_take_orders()`, gültig + eigener Stamm + `worker_can_reach`, `_fixed_target_wants_wood(target)`; dann **`_interrupt_tasks()` zuerst** (löscht das Feld — dieselbe Reihenfolgenfalle wie `order_chop_area`), dann setzen, `_choose_supply_task()`; ohne Quelle `_stop_all()` + `false` |
| `has_supply_job() -> bool` (neu) | `_supply_target != null and is_instance_valid(...)`. **Nie** `State.IDLE` — der Brave hat im Gründungstick noch nicht getickt (10e-Falle) |
| `_choose_supply_task()` (neu) | Quellwahl, siehe unten |
| `has_depot_haul()` | **+ `_supply_target == null`** — Leg 1 der Quellwahl benutzt `_haul_source` wieder, sonst antwortet ein Nachschub-Brave beiden Prädikaten mit `true` und `_tick_forward_haul` verbucht ihn falsch |
| `_haul_valid()` | Zielhälfte → `_fixed_target_wants_wood(_fixed_delivery_target())`, Quellhälfte unverändert |
| `_tick_pickup()` | Der Stapel-Relais-Zweig bekommt `_supply_target == null` als Zusatz-Guard. **Ohne ihn verwandelt sich der Nachschubauftrag still in ein Depot→Depot-Relais**, sobald der Quellstapel an einem eigenen Gebäude liegt — und der Bestand eines Depots liegt das immer. Die heikelste Interaktion der ganzen Änderung |
| `_tick_loose_deliver()` | (a) `carried_wood <= 0` → `_choose_supply_task()`; (b) Zielauflösung liest die beiden neuen Helfer; (c) Lieferschwanz: **vor** dem `_haul_source`-Pendel `if has_supply_job(): _haul_source = null; _choose_supply_task(); return` |
| `_tick_loose_chop()` | „am selben Baum bleiben, bis die Fuhre voll ist" wird `_fills_full_load() = has_chop_area() or has_supply_job()` — 1 Holz pro 40-m-Fuhre ist wertlos (dasselbe Argument wie in 10e für Flächenaufträge) |
| `_interrupt_tasks()` | `_supply_target = null` neben `_haul_source/_haul_target` — damit gilt das Ein-Auftrag-Prinzip gratis |
| `_loose_drop_target()` | **unverändert**, absichtlich: die Stapel-Konsolidierung gilt nur für den Nächstes-Gebäude-Pfad; ein Festziel liefert immer am `delivery_point()`, und von dort wird der Absorptionsradius gemessen |

**Quellwahl `_choose_supply_task()`**, nach jeder Fuhre neu (Muster `_try_fetch_wood`):

1. nächstes eigenes nutzbares `WoodDepot` mit `stored_wood() > 0`, gleiche Insel, dessen
   Grundriss **nicht** innerhalb `ABSORB_RADIUS` des Ziel-`delivery_point()` liegt (ein Regal,
   das das Ziel schon speist, darf nicht auf sich selbst umgeschaufelt werden) und das nicht
   das Ziel selbst ist → `_haul_source`, `Task.PICKUP` (nutzt `_tick_haul_pickup` mit
   `allow_direct` — wichtig, ein 1×1-Depot ist navigations-solid);
2. nächster Bodenstapel via `WoodPileManager.nearest_pile(...)` innerhalb
   `AI_SUPPLY_SOURCE_RADIUS`, gleiche Insel, mit dem Ziel-`delivery_point()` als `exclude_pos`
   und `ABSORB_RADIUS` als `exclude_radius`;
3. `tree_manager.best_tree(target.center_world(), position, Brave.JOB_TREE_RADIUS, true, safe_filter)`
   — derselbe Aufruf wie `_nearest_claimable_tree()`, mit dem Ziel in der Rolle von `job`.
   **10e-Lehre A1:** `radius` steuert Kandidatenfilter **und** Gehbudget
   (`radius * PATH_RADIUS_FACTOR`) — ein knapper Radius killt jeden entfernten Auftrag über
   `VERDICT_TOO_FAR`;
4. nichts gefunden → `_stop_all()`. **Ausdrücklich NICHT `target.mark_wood_stalled()`** — das
   würde den Rekrutierer 30 s um eine Baustelle herumführen und den eigenen Holzholzyklus einer
   Werkstatt unterdrücken, also das *Ziel* für das Versagen des *Lieferanten* bestrafen. Die KI
   merkt es an `has_supply_job() == false`.

Abbruch: Ziel ungültig / `health <= 0` → `_stop_all()` (getragenes Holz legt
`_interrupt_tasks` ab). Kein Bedarf mehr **mit leeren Händen** → `_stop_all()`; **mit Holz** →
nicht abbrechen, der Festziel-Zweig fällt in den bestehenden „Ziel weg/voll"-Pfad und liefert
wie loses Holz ab. Überschuss ist harmlos: 3 getragen bei Bedarf 2 ⇒ `_absorb_piles` nimmt 2,
der Rest bleibt als Bodenstapel am Ziel.

**`scripts\core\tribe_commands.gd`**:

```gdscript
## Braves tragen Holz zu EINEM bestimmten eigenen Gebaeude (KI-Holzlogistik): Quelle
## ist das naechste Regal, sonst ein Bodenstapel, sonst ein Baum; abgelegt wird am
## delivery_point des Ziels, wo das Ziel es absorbiert. NICHT-BRAVES WERDEN
## VOLLSTAENDIG IGNORIERT (Arbeiterauftrag — dieselbe Regel wie order_chop_area).
## KI-INTERN: kein UI-Aufrufer, bewusste Nutzerentscheidung.
func order_supply_wood(units: Array[Unit], target: Building) -> int
```

**Kein `supply_claims` am `Building`.** Die Buchführung bleibt in der KI (4.2). Ein Feld am
`Building` wäre eine neue Lebenszeit-Kopplung (leckt sie, überzählt `wood_incoming()` und eine
Baustelle wartet für immer auf Holz, das nie kommt) — für eine KI-interne Mechanik ist die
KI-seitige Liste die kleinere Änderung.

### 4.2 Bedarf umfasst Werkstätten und Baustellen

**Ausgehungerte Werkstatt billig erkennen** (F10: `wants_more_stock_wood()` kostet
`O(Stapel × Gebäude)` — die KI ruft es **nie**). Kaskade, billigstes zuerst:

1. `shop.wood_stalled` — ein bool, **gratis**, und der *richtige* Auslöser:
   `Brave._choose_workshop_task()` setzt ihn genau dann, wenn die eigenen Holzholer nichts
   Erreichbares fanden, und schickt sie **hinein** zurück. Eine stalled Werkstatt hat ihre
   Arbeiter also **drinnen** und 0 Bestand — das ideale Nachschubziel, und `_tick_active`
   schickt sie nicht wieder hinaus. `can_start_production()` prüft `wood_stalled` **nicht**,
   die Produktion startet also in dem Tick, in dem das Holz landet.
2. `not production_active and inside_count() == 0` — ihre Arbeiter sind draußen und scheitern.
   `O(≤ 4)`.
3. Nur für Kandidaten aus 1/2 und nur für ≤ `AI_SHOP_SUPPLY_PER_TICK` (2) Werkstätten je
   Holz-Tick (Round-Robin-Cursor, Muster `_anchor_cursor`): Bestätigung über den billigen Proxy
   `wood_pile_manager.wood_in_radius(shop.delivery_point(), Building.ABSORB_RADIUS) < shop.product_wood()`
   (`O(Stapel)`, kein Peer-Scan), und erst nach `AI_SHOP_SUPPLY_PATIENCE_TICKS` (3 Holz-Ticks
   ≈ 9 s) Kurzstand. **Die Geduld ist der Grund, warum der Nachschub nicht gegen den eigenen
   Holzholzyklus der Werkstatt kämpft:** eine bloß gerade holende Werkstatt wird in Ruhe
   gelassen; scheitern ihre Holer weiter, stallt sie (Fall 1) oder die Geduld läuft ab.

**`_tick_shop_supply(cache)`**, aufgerufen aus `_tick_wood_logistics` (also innerhalb der
`AI_WOOD_TICK_INTERVAL`-Drossel und des „unter Bedrohung übersprungen"-Guards):

```gdscript
## Nachschub-Trupps: {"target": Building, "units": Array[Unit]}. Mitgliedschaft aus
## Brave.has_supply_job(), NIE State.IDLE (dieselbe Falle wie _wood_crews).
var _supply_crews: Array[Dictionary] = []
var _shop_short_ticks: Dictionary = {}
var _shop_supply_cursor: int = 0
```

- `_prune_supply_crews()` in der Form von `_prune_wood_crews`.
- Ziele in dieser Priorität: `cache.stalled_sites` → ausgehungerte Werkstätten → Baustellen mit
  `wood_needed_total() - wood_incoming() > 0` ohne eigene Quelle → (10f) Hütten mit
  `upgrading and wood_stalled`. `demolishing` (F3) und `abandoned` ausgeschlossen.
- Je Ziel ≤ `AI_SUPPLY_BRAVES_PER_TARGET` (3) idle Braves, insgesamt ≤ `AI_MAX_SUPPLY_CREWS`
  (3) Trupps, nie unter `min_economy_braves` (Guard wie `_staff_workshops`). Ein Ziel mit
  bestehendem Trupp wird übersprungen.
- **Bedarfsrechnung korrigieren**, sonst legt jeder Tick einen weiteren Fäll-Trupp für Holz an,
  das schon unterwegs ist:
  ```gdscript
  var need: int = 0
  for site in cache.sites:
      if site.demolishing: continue
      need += maxi(0, site.wood_needed_total() - site.wood_incoming() - _supply_inbound(site))
  need += _shop_demand(cache)
  ```
  `_supply_inbound(b) = Brave.CARRY_CAPACITY * (Braves im Trupp für b)`.

**Das schließt eine echte Sackgasse:** heute wird eine stalled ferne Baustelle nur durch
`_send_escort_if_remote` „gerettet" — ein `order_move`, das hofft, dass
`_recruit_workers` die Braves aufsammelt, was bei `wood_stalled` **strukturell nicht
funktioniert**. Sie stirbt nach 120 s. Jetzt bekommt sie einen echten Nachschub-Trupp.

*Ausdrücklich außerhalb dieser Phase:* einen `order_chop_area`-Trupp auf den Hain **bei dieser
Baustelle** zu setzen. `_grove_candidates_cached` ist auf **einen** Ursprung gecacht — pro
Baustelle andere Haine abzufragen würde den Cache bei jedem Aufruf invalidieren und
`grove_candidates` (Bucket-Vollscan) mehrfach pro Tick auslösen. Sinnvoll erst mit einem
Per-Baustelle-Hain-Cache.

### 4.3 Holzregal an der Werkstatt

**Der Gewinn ist ein Selbstläufer:** `Workshop._available_stock_piles()` ist
`piles_in_radius(delivery_point(), ABSORB_RADIUS = 5.0)`, und ein `WoodDepot` hält seinen
Bestand als **echte `WoodPile`-Objekte** auf vier Slots. Landet das Regal innerhalb dieser 5 m,
**zählt `Workshop.stock_wood()` es als eigenen Bestand** — `wants_more_stock_wood()` bleibt
falsch, `_tick_active` schickt die Arbeiter **nie mehr hinaus**, sie hämmern durchgehend
Arbeitersekunden, und laut **F10** verschwindet damit auch der teure Zweig. `CAPACITY = 20` =
3 Katapulte / 5 Rammen / 2 Luftschiffe Puffer für **1 Holz** auf 1×1. Gefüllt wird es gratis
von vorhandener Mechanik: `Brave._tick_loose_deliver` zieht bei `has_chop_area()` ein Regal
innerhalb `HARVEST_DEPOT_PREFER_RADIUS = 40 m` einem näheren Gebäude vor — die bestehenden
Fäll-Trupps liefern von selbst dorthin. `_pile_reserved_by_peer` schützt nur gegen *andere
Werkstätten* und blockiert das nicht. Umgekehrt kann das Depot der Werkstatt nichts wegnehmen:
`WoodDepot._tick_active` adoptiert nur innerhalb `ADOPT_RADIUS = 1.2 m` um seine eigene Mitte.

**Geometrie — vier harte Randbedingungen:**

| Bedingung | Quelle | Folge bei Verstoß |
|---|---|---|
| `d(Regalmitte, shop.delivery_point()) <= ABSORB_RADIUS = 5.0` | `_available_stock_piles()` | das Regal ist kein Bestand, die ganze Idee fällt |
| nicht **auf** `shop.entrance_cell()` | `edge_spawn_position()` fällt auf den Perimeterring zurück | Fahrzeug-Spawn und `delivery_point()` springen, `exit_blocked()`-Geometrie verschiebt sich |
| **seitlicher Mindestabstand zur Eingangsnormalen** | `_dispatch_point()` = Eingang + Normale × 5; Fahrzeuge brauchen breite Korridore | ein 1×1 navigations-solides Regal 2 m vor dem Tor fängt das frische Fahrzeug ⇒ **dauerhaft `exit_blocked()`, also genau Problem A, verschlimmert** |
| kein **anderes** eigenes `delivery_point()` innerhalb `ABSORB_RADIUS` des Regals | `_absorb_piles()` hat kein Eigentumskonzept | eine Hütten-Baustelle 3 Zellen weiter frisst still den Werkstattbestand |

Empfehlung: Regalmitte **2,0 … 4,5 m** vom `delivery_point()` (0,5 m Reserve gegen
Höhen-Jitter), seitlicher Abstand ≥ 2,5 m von der Eingangsnormalen.

**Eigener, begrenzter Scan — `_find_plot` wird NICHT angefasst:**

```gdscript
## Regal-Bauplatz fuer `shop`: Ringsuche 2..AI_SHOP_DEPOT_SCAN_RINGS+1 um die
## Eingangszelle; erste Zelle, die (1) can_place_at 1x1 besteht, (2) im
## Absorptionsradius der Werkstatt liegt, aber ausserhalb des Ausfahrkorridors,
## (3) in keinem anderen eigenen Absorptionsradius liegt, (4) erreichbar ist.
func _find_shop_depot_plot(shop: Workshop, cache: TickCache) -> Vector2i
```

Zwei Gründe, warum das **nicht** über `_find_plot` läuft — beide aus der 10e-Messung:
(a) jeder zusätzliche Sweep multipliziert gegen das geteilte `_plot_budget`/
`_plot_candidates_left`; (b) `_find_supplied_plot` verlangt
`_trees_near_cell(cell) >= MIN_TREES_NEAR_PLOT (3)` **unabhängig von der Gebäudeart** — eine
Werkstatt in einer abgeholzten Spätspiel-Basis hätte dort keine drei Bäume, das Regal käme
**nie** zustande. Ein Lager ist per Definition kein Holzverbraucher; die Baumprüfung ist für
diese Art sachlich falsch. Auch `_plot_has_clearance` wird hier bewusst übersprungen (nah an
der Werkstatt zu stehen ist der ganze Zweck) — die „kein anderer Absorptionsradius"-Regel
ersetzt sie.

Kosten: `ring_cells` für Radien 2..4 = 16 + 24 + 32 = **72 Zellen**, je ein `can_place_at` und
zwei flache Distanzen; die „anderes Gebäude"-Prüfung nur für bestandene Zellen über
`cache.sites + cache.workshops + cache.depots` (kurze Listen); **höchstens ein**
`_plot_reachable`. Läuft nur in einem Bau-Tick, der `&"shop_depot"` gewählt hat, in der Praxis
≤ 3 Mal pro Partie. **`dbg_plot_cells`/`dbg_plot_us` bleiben damit unberührt** — das ist der
Grund für die eigene Funktion.

**Bauordnung** (`ai_state.gd`, rein), neuer Zweig **unmittelbar vor** den Werkstatt-Zweigen:

```gdscript
# Ein Regal fuer eine Werkstatt ohne: 1 Holz, 1x1, und es macht aus dem Holzhol-
# Zyklus der Werkstatt eine Standversorgung (ihr Absorptionsradius frisst das Regal).
# Mit Absicht VOR der naechsten Werkstatt: die stehenden zu fuettern ist mehr wert,
# als eine weitere leere hinzustellen.
if int(counts.get("shops_without_depot", 0)) > 0 \
        and int(counts.get("shop_depot", 0)) < Balance.AI_MAX_SHOP_DEPOTS:
    return &"shop_depot"
```

`&"shop_depot"` ist ein **zweiter Schlüssel auf dieselbe Szene** in `BUILD_SCENES` /
`BUILD_FOOTPRINTS` (`WOOD_DEPOT_SCENE`, `WOOD_DEPOT_FOOTPRINT`). `_tick_build` bekommt einen
dritten Fall neben dem bestehenden Forward-Depot-`prefer`-Fall und ruft
`_find_shop_depot_plot`. `_plot_orientation` bleibt 0 (bei 1×1 irrelevant).

**Klassifizierung im Cache** (`build_tick_cache`) muss **nach** der Gebäudeschleife laufen —
eine Werkstatt später in `tribe.buildings` ist noch nicht in `cache.workshops`:

```gdscript
# O(Lager x Werkstaetten), beide kurz (<= 6 x <= 12 = 72 flache Distanzen).
# Ein Werkstattregal darf NICHT auch als vorgeschobenes Lager zaehlen: es wuerde
# den "grove_far -> forward_depot"-Zweig befriedigen und das Hain-Lager unterdruecken.
for depot in cache.depots:
    for ws in cache.workshops:
        if depot.footprint_distance_to(flat(ws.delivery_point())) <= Building.ABSORB_RADIUS:
            cache.shop_depots.append(depot)
            cache.forward_depots.erase(depot)
            break
```

`AI_MAX_SHOP_DEPOTS = 3`, also eines je produktivem Werkstatt-Cluster, nicht je Werkstatt:
`_nearest_depot()` wählt das nächste Regal **mit Platz**, und ein von seiner Werkstatt
geleertes Regal hat immer Platz — jedes weitere zieht Fäll-Lieferungen vom Basislager ab.

### 4.4 Pendel-Trupps skalieren

`_tick_forward_haul` hat 2 Hauler hart verdrahtet → `AIState.haul_crew_count(cache.brave_count)`.

---

## Teil 5 — Kartengröße: Arena-Maß, Bedrohungserkennung, zwei Baumuster

### 5.1 Das Arena-Maß

**Die Kartengröße allein reicht nicht** — Insel (128) mit 4 Stämmen ist eng (36,2 Zellen
Basisabstand), Plateau (128) nicht (82 Zellen). Maßgeblich ist der Abstand zur nächsten
**feindlichen** Basis.

```gdscript
## Abstand von der eigenen Basis zum naechsten FEINDLICHEN Basisanker, in Zellen.
## Quelle: der Reinkarnationsplatz jedes fremden Stammes — er steht am Anker und
## bewegt sich nie. Faellt einer weg (10d-Selbstzerstoerung), zaehlt das naechste
## feindliche Gebaeude; ohne alles die halbe Kartenkante (nav_grid.terrain.size).
## Nebenprodukt und ebenso wichtig: _enemy_anchors, die Ankerpositionen selbst.
func _arena_span() -> float
```

Neu berechnet alle `AI_ARENA_TTL_TICKS` (60) — **ein** Durchlauf über
`building_manager.buildings` pro Minute, das einzige Mal, dass diese Phase fremde Gebäude
anfasst. `CELL_SIZE = 1.0`, Zellen sind also Meter; `nav_grid.terrain.size` liefert die
Kantenlänge (128 bzw. 256).

### 5.2 Bedrohungserkennung reparieren

Vier Änderungen, davon eine ohne jedes Tuning:

1. **`DEFEND_RADIUS` wird relativ.** `AIState.defend_radius(arena_span)` (rein):
   `clampf(arena_span * AI_DEFEND_RADIUS_FACTOR, AI_DEFEND_RADIUS_MIN, AI_DEFEND_RADIUS_MAX)`.
   Insel/4 (36,2) → 14 · Insel/2 (51,2) → 17,9 · Plateau (82) → 28,7 · Seenland/Bergpass
   (> 90) → 32 (heutiger Wert).
2. **Territoriumstest — der eigentliche Fix.** Ein Gegner zählt nur als Bedrohung, wenn er
   **näher an unserem Anker als an seinem eigenen** ist. Das entfernt „die Nachbarn stehen bei
   sich zu Hause" **vollständig** und ist ein Vergleich zweier schon berechneter Distanzen
   (`_enemy_anchors` aus 5.1, je Stammes-ID eine `Vector3`). Kein Schwellwert, nichts zu tunen.
3. **Wirtschafts-Stop staffeln.** `_tick_wood_logistics` (und `_tick_shop_supply`) setzt heute
   bei **jeder** Bedrohung aus. Neu: nur ab `threat.count >= AI_ECONOMY_HALT_ENEMIES` (3) —
   ein einzelner Späher darf die Holzwirtschaft nicht für das ganze Spiel abschalten. Ebenso
   `_tick_attack`: es läuft weiter, solange `threat.count < AI_ATTACK_ABORT_ENEMIES` (5) — ein
   Späher am Dorfrand darf keine laufende Angriffswelle zurückrufen.
4. **Miliz deckeln.** `_tick_defend` nimmt heute **alle** idle Braves
   (`take_idle(idle_left())`). Neu: höchstens `AI_MILITIA_MAX_SHARE` (0,5) des Idle-Pools, nie
   unterhalb von `min_economy_braves(population) / 2` Restbestand, und überhaupt erst ab
   `AI_MILITIA_MIN_BRAVES` (10) Braves. Begründung: ein Brave hat `BRAVE_POWER = 0.5` — 20
   Braves sterben für 10 Kampfkraft, und sie sind gleichzeitig die gesamte Wirtschaft. Die
   Miliz bleibt der letzte Ausweg, den sie sein soll.

### 5.3 Zwei Baumuster

```gdscript
## Baumuster nach Arena-Enge. "eng" = der Feind steht in Sichtweite (kleine Karte
## oder viele Staemme): kompakte, verteidigbare Basis, KEINE vorgeschobenen Lager
## (die laegen in Feindgebiet), Wachtuerme frueher und mehr, Armee frueher und
## kleinere erste Welle. "offen" = Verhalten wie bisher.
static func is_cramped(arena_span: float) -> bool     # arena_span < AI_CRAMPED_ARENA
static func plot_search_radius(arena_span: float) -> int
static func settlement_anchor_limit(arena_span: float) -> int
static func forward_depots_allowed(arena_span: float) -> bool
static func target_watchtowers(arena_span: float) -> int
static func army_attack_size(arena_span: float) -> int
static func pop_for_train(arena_span: float) -> int
```

| Größe | offen (heute) | eng | Begründung |
|---|---|---|---|
| `AI_PLOT_SEARCH_RADIUS` | 40 | **18** | 40 Zellen auf einer 128er-Karte reichen **an der Nachbarbasis vorbei**; der Sweep wird dabei auch billiger |
| `AI_MAX_SETTLEMENT_ANCHORS` | 4 | **2** | kompakte, verteidigbare Basis statt Streusiedlung |
| vorgeschobenes Lager | erlaubt | **aus** | `AI_FORWARD_DEPOT_DISTANCE` ist **35** — bei 36,2 Zellen Basisabstand kann `grove_far` nur Feindgebiet meinen. Die KI würde ihr Lager vor die feindliche Tür bauen |
| `AI_TARGET_WATCHTOWERS` | 2 | **3**, und im Ladder **vor** die Werkstätten | Kontakt kommt sofort |
| `ARMY_ATTACK_SIZE` | 12 | **8** | die KI braucht früh eine **echte** Armee, sonst hat sie nur Braves — genau das gemeldete Symptom |
| `POP_FOR_TRAIN` | 16 | **12** | BUILD → TRAIN früher |

Dazu: **`_expansion_anchor()`** (nächste Baumzelle) verwirft Zellen, die näher an einem
Feindanker als an unserem liegen — derselbe Territoriumstest wie 5.2.2, ein Vergleich.

`AIState.next_building_kind(counts)` bleibt rein und bekommt dafür zwei neue Schlüssel:
`"cramped"` (bool) und `"watchtower_target"` (int); der Controller füllt sie aus
`_arena_span()`. `next_state` bekommt `pop_for_train`/`army_attack_size` über den Snapshot
(`army_target` ist dort schon Vorbild).

**Was ausdrücklich NICHT passiert:** keine Sonderbehandlung nach `map_id`. Das Maß ist der
gemessene Basisabstand — damit funktioniert es auch für „Bergpass mit 2 Stämmen" (weit) und
„Seenland mit 4 Stämmen" (mittel), ohne eine Tabelle pflegen zu müssen, und für künftige Karten
automatisch.

---

## Teil 6 — Reinkarnationsplatz: kein Angriffsziel, für niemanden

### 6.1 Bestandsaufnahme (verifiziert)

**Es ist kein Schadens-, sondern ein Ziel-Bug.** Der Schaden ist seit 10d vollständig
ausgeschlossen: `ReincarnationSite.take_damage`, `apply_destruction_stages` und
`add_lava_contact` sind **No-ops**, und `SpellContext.check_terrain_integrity` überspringt ihn.
Aber alles darf weiter auf ihn *zielen* — und verbrennt dabei Zeit, Zauberladungen und eine
ganze Angriffswelle.

Die vorhandene Wahrheit heißt `Building.is_assailable_by_units()` (Default `true`,
`ReincarnationSite` → `false`) und wird an **fünf** Stellen respektiert:
`selection_manager.gd` (Spieler-Rechtsklick), `fireball.gd`, `unit.gd` (dreimal: Angriffsbefehl,
Scan, Auto-Scan).

**An vier Stellen wird sie nicht respektiert:**

1. `CrewedVehicle.order_attack_building` — **Katapult und Feuerramme nehmen ihn per Befehl an,
   vom Spieler wie von der KI.**
2. `CrewedVehicle._scan_enemy_building` — die Auto-Zielsuche nimmt das *nächste* feindliche
   Gebäude, und der Kreis steht am Basisanker, ist also meist genau das. Fahrzeuge parken und
   beschießen ein unverwundbares Ziel **für immer**.
3. `Airship.order_attack_building` — die Deck-Feuerkrieger ebenso.
4. `AIController._nearest_enemy_building`, `_enemy_buildings_near` und
   `_attack_target_position` — dadurch zielt die **Zauber-Heuristik** (Blitz, Vulkan, Absinken,
   Ebene) auf ihn **und** die ganze Angriffswelle marschiert auf ihn zu.

**Warum die Lücken entstanden sind, steht als veralteter Kommentar im Code.** `building.gd`
behauptet bei `is_assailable_by_units()` bis heute: *„only SPELLS and CATAPULTS may damage it —
those go through apply_destruction_stages()/take_damage() and are NOT gated by this flag."* Das
war der 7g-Stand; seit 10d ist es **falsch**. Und `selection_manager.gd` dokumentiert die
Katapult-Umgehung sogar ausdrücklich als gewollt („a selected catapult auto-bombards it once in
range") — genau das soll weg, **auch für den Spieler** (Nutzervorgabe).

### 6.2 Eine Wahrheit, richtig benannt

`is_assailable_by_units()` → **`is_attackable()`** (Default `true`, `ReincarnationSite` →
`false`), mit einem Kommentar, der den heutigen Stand sagt: **kein Angriffsziel** für Einheiten,
Fahrzeuge, Luftschiffe, die KI-Zauber-Heuristik und die KI-Zielwahl; der *Schaden* ist davon
unabhängig in `ReincarnationSite` selbst abgeschaltet. Der alte Name war die Einladung, den
nächsten Pfad ungeprüft zu lassen — die vier Lücken sind der Beweis. Sieben Aufrufstellen plus
`tests\test_building_assault.gd` (dort `test_reincarnation_site_not_assailable_by_units`
mitumbenennen), rein mechanisch.

### 6.3 Die vier Lücken schließen

| Stelle | Änderung |
|---|---|
| `CrewedVehicle.order_attack_building` | `if not building.is_attackable(): return`, direkt nach der `health`-Prüfung und **vor** der Eigen-Raider-Ausnahme (ein eigener Kreis kann keine Raider haben — er ist nicht betretbar) |
| `CrewedVehicle._scan_enemy_building` | `is_attackable()` in den Filter |
| `CrewedVehicle._building_target_valid` | ebenfalls — ein schon gefasstes Ziel muss fallen, wenn es die Regel nicht mehr erfüllt (Bekehrung, Ladestand) |
| `Airship.order_attack_building` | `is_attackable()` in die Eingangsprüfung |
| `AIController._nearest_enemy_building` / `_enemy_buildings_near` / `_attack_target_position` | `is_attackable()` in alle drei Filter |
| `selection_manager.gd` | Kommentar korrigieren: die Katapult-Umgehung existiert nicht mehr |
| `building.gd` | veralteten 7g-Kommentar durch den 10d/10g-Stand ersetzen |

**Ausdrücklich NICHT anfassen:** `Airship._nearest_reincarnation_site()` — das ist der
**Drift-Anker** des schwebenden Luftschiffs (`_tick_drift`) und hat mit Angriffen nichts zu tun.

**Spieler-Zauber bleiben erlaubt.** Ein Feuerball auf den Kreis ist ein No-op und die
Entscheidung des Spielers; gefiltert wird nur die **KI-Heuristik**, weil sie dort Ladungen
verbrennt. Die vom Nutzer verlangte Grenze ist „nicht als angreifbares Ziel" — und das sind die
Einheiten-, Fahrzeug- und Luftschiffbefehle, die die UI erteilt.

### 6.4 Nebenwirkung: die KI verfolgt endlich die echte Siegbedingung

Fällt der Kreis aus `_attack_target_position()` heraus und ist er das letzte feindliche
Gebäude, greift die **vorhandene** Rückfallebene „nächste feindliche **Einheit**". Genau das ist
die 10d-Siegkette: letzter Anhänger stirbt → Kreis versinkt von selbst → Schamanin stirbt →
Stamm ausgeschieden. Bisher parkte die Armee vor einem unverwundbaren Ring, während der Gegner
weiterlebte — der Nutzerreport in einem Satz. **Kein weiterer Eingriff nötig**, der Filter
allein schaltet die Zielwahl um.

**Keine neuen `Balance`-Konstanten.** Teil 6 ist reiner Bugfix und **völlig unabhängig** von den
Teilen 1–5 — er kann als Erster geliefert werden.

---

## Neue `Balance`-Konstanten

In `scripts\core\balance.gd`, Abschnitt `# === KI (Skirmish-Gegner) ===`:

```gdscript
# --- KI: Bautrupps ---
## Eine Hand je so vielen Planierzellen: Planieren ist Zellarbeit
## (Building.claim_flatten_cell), Aufbauen nicht (BUILD_RATE 0.2/s = 5 Arbeitersek.).
const AI_FLATTEN_CELLS_PER_WORKER: int = 6
## Trupp-Grenzen je Baustelle. AI_SITE_WORKERS_MAX liegt BEWUSST unter
## Building.MAX_WORKERS (10): die freien Plaetze bleiben dem passiven
## BuildingManager._recruit_workers, damit sich beide Systeme nicht verdraengen.
const AI_SITE_WORKERS_MIN: int = 2
const AI_SITE_WORKERS_MAX: int = 8
## Nach dem Fundament zaehlt nur Holznachschub: ein Traeger mehr je so vielen
## fehlenden Holz (Brave.CARRY_CAPACITY 3 je Fuhre).
const AI_WOOD_PER_EXTRA_BUILDER: int = 6
const AI_SITE_WORKERS_BUILD_MAX: int = 5
## Ab so vielen Arbeitern gilt eine Baustelle als versorgt (Tor fuer eine NEUE).
const AI_SITE_SUPPLIED_WORKERS: int = 2
## Anteil der Braves, der maximal ans Bauen gebunden wird, plus Bodensatz.
## Geklemmt auf AIState.min_economy_braves(population) — Bauen teilt die
## Wirtschaftsmannschaft auf, es frisst nicht den Armee-Anteil.
const AI_BUILDER_BRAVE_SHARE: float = 0.40
const AI_MIN_BUILDER_BRAVES: int = 4
## Baustellen, die pro Tick neu bestueckt werden (Befehls-Churn + take_idle_for).
const AI_SITES_STAFFED_PER_TICK: int = 3
## Braves werden nur aus diesem Umkreis gezogen. AUSNAHME: eine Baustelle mit NULL
## Arbeitern bekommt ihre Mindestbesatzung aus beliebiger Entfernung — "gar
## niemand" ist der gemeldete Fehler.
const AI_BUILDER_WALK_RADIUS: float = 80.0
## Ticks, die eine unversorgte Baustelle das Tor blockieren darf
## (Verklemmungsschutz), und Sperrfrist nach einem order_build ohne Zuweisung.
const AI_SITE_SUPPLY_GRACE_TICKS: int = 30
const AI_SITE_RETRY_TICKS: int = 10

# --- KI: Bauplatz-Absicherung ---
## Intervall (Ticks) der Nachkontrolle und Strikes, bis eine Baustelle als
## abgeschnitten gilt: Insel-Labels duerfen bis NavGrid.ISLAND_REFRESH_MS veralten,
## und eine wachsende Landbruecke braucht mehrere Ticks.
const AI_SITE_GUARD_INTERVAL: int = 5
const AI_SITE_GUARD_STRIKES: int = 2
## Ticks, die eine als unerreichbar erkannte Zelle gesperrt bleibt. NICHT ewig wie
## vor 10g: eine Landbruecke kann sie spaeter anschliessen.
const AI_PLOT_BAN_TICKS: int = 300
## Abstand im Anti-Aushunger-Durchgang: EIN Ring Luft statt gar keiner. Der
## Unterschied zwischen "eng gebaut" und "Eingang zugemauert".
const AI_PLOT_SPACING_RELAXED: int = 1

# --- KI: Fahrzeug-Besatzung ---
## Zielbesatzung = min_fire_crew + dieser Bonus (Nachladezeit skaliert mit der
## Besatzung), geklemmt auf min_move_crew..max_crew.
const AI_VEHICLE_EXTRA_CREW: int = 1
## Hoechstens dieser Anteil der Armee darf gleichzeitig in Fahrzeugen sitzen.
const AI_VEHICLE_ARMY_CREW_SHARE: float = 0.25
## Braves bemannen Fahrzeuge nur bei echtem Ueberschuss ueber die
## Wirtschaftsreserve oder wenn es kaum Militaer gibt (Nutzerregel).
const AI_VEHICLE_BRAVE_SURPLUS: int = 12
const AI_VEHICLE_MILITARY_SCARCE: int = 6
## Fahrzeuge, die pro Tick aufgefuellt werden (Blockierer haben Vorrang).
const AI_VEHICLES_PER_TICK: int = 3
## Sammelpunkt-Abstand vor der Werkstatt; MUSS ueber
## Workshop.EXIT_CLEAR_RADIUS + 0.5 liegen, sonst ignoriert _dispatch_point ihn.
const AI_VEHICLE_MUSTER_DISTANCE: float = 12.0

# --- KI: Holznachschub ---
const AI_SUPPLY_BRAVES_PER_TARGET: int = 3
const AI_MAX_SUPPLY_CREWS: int = 3
## Werkstaetten, die pro Holz-Tick genauer geprueft werden (die Bestaetigung kostet
## einen Stapel-Scan) — Round-Robin ueber die Ticks.
const AI_SHOP_SUPPLY_PER_TICK: int = 2
## So viele Holz-Ticks bleibt eine Werkstatt sich selbst ueberlassen, bevor die KI
## Braves schickt: sonst kaempft der Nachschub gegen ihre eigenen Holzholer.
const AI_SHOP_SUPPLY_PATIENCE_TICKS: int = 3
const AI_SUPPLY_SOURCE_RADIUS: float = 60.0

# --- KI: Holzregal an der Werkstatt ---
## Ein Regal im Absorptionsradius der Werkstatt IST deren Bestand
## (Workshop.stock_wood zaehlt es) — damit bleiben die Arbeiter drinnen.
const AI_MAX_SHOP_DEPOTS: int = 3
## Abstand zum Lieferpunkt. Obergrenze MUSS unter Building.ABSORB_RADIUS (5.0)
## bleiben, sonst zaehlt das Regal nicht.
const AI_SHOP_DEPOT_MIN_DIST: float = 2.0
const AI_SHOP_DEPOT_MAX_DIST: float = 4.5
## Seitlicher Mindestabstand zur Eingangsnormalen: das Regal darf die Ausfahrt des
## fertigen Fahrzeugs nicht zustellen, sonst blockiert es die Werkstatt dauerhaft.
const AI_SHOP_DEPOT_SIDE_CLEAR: float = 2.5
## Ringe (ab Radius 2) um die Eingangszelle, die abgesucht werden.
const AI_SHOP_DEPOT_SCAN_RINGS: int = 3
## Pendel-Trupps fuer vorgeschobene Lager (vorher hart 2).
const AI_BRAVES_PER_HAUL_CREW: int = 40
const AI_MAX_HAUL_CREWS: int = 3

# --- KI: Kartengroesse / Arena ---
## Neuberechnung des Basisabstands (ein Durchlauf ueber ALLE Gebaeude).
const AI_ARENA_TTL_TICKS: int = 60
## Unter diesem Basisabstand (Zellen = Meter) gilt die Arena als ENG und die KI
## schaltet auf das kompakte Baumuster. Insel 128 mit 4 Staemmen: 36,2 · mit 3:
## 44,3 · mit 2: 51,2 · Plateau 128: 82 · Seenland/Bergpass 256: deutlich mehr.
const AI_CRAMPED_ARENA: float = 60.0
## Verteidigungsradius relativ zum Basisabstand statt fixer 32 m: auf der Insel
## lagen die Nachbarbasen (36 Zellen) im alten Radius, wodurch _detect_threat
## DAUERHAFT feuerte — Holzwirtschaft aus, kein echter Angriff, Braves als Miliz.
const AI_DEFEND_RADIUS_FACTOR: float = 0.35
const AI_DEFEND_RADIUS_MIN: float = 14.0
const AI_DEFEND_RADIUS_MAX: float = 32.0
## So viele Gegner braucht es, damit die Wirtschaft aussetzt bzw. eine laufende
## Angriffswelle zurueckgerufen wird. Ein einzelner Spaeher darf beides nicht.
const AI_ECONOMY_HALT_ENEMIES: int = 3
const AI_ATTACK_ABORT_ENEMIES: int = 5
## Miliz: Anteil des Idle-Pools und Mindestbestand. Vorher nahm _tick_defend ALLE
## idle Braves — bei BRAVE_POWER 0.5 sterben 20 Braves fuer 10 Kampfkraft, und sie
## sind gleichzeitig die ganze Wirtschaft.
const AI_MILITIA_MAX_SHARE: float = 0.5
const AI_MILITIA_MIN_BRAVES: int = 10
## Kompaktes Baumuster (enge Arena) gegen die offenen Werte.
const AI_PLOT_SEARCH_RADIUS_CRAMPED: int = 18
const AI_MAX_SETTLEMENT_ANCHORS_CRAMPED: int = 2
const AI_TARGET_WATCHTOWERS_CRAMPED: int = 3
const AI_ARMY_ATTACK_SIZE_CRAMPED: int = 8
const AI_POP_FOR_TRAIN_CRAMPED: int = 12
```

`Building.APPROACH_SEARCH_RINGS = 3` gehört bewusst **nicht** nach `Balance` — es spiegelt die
vorhandene `grow`-Grenze in `edge_spawn_position()` und muss mit ihr an **einer** Stelle stehen.

---

## Umsetzungsschritte (Reihenfolge ist bindend)

**Voraussetzung: 10f ist committet.**

0. **Teil 6 zuerst** (unabhängig, kein neuer Zustand, keine Konstanten): Umbenennung
   `is_assailable_by_units` → `is_attackable`, die vier fehlenden Filter, beide veralteten
   Kommentare. → **Commit 1**, sofort spielbar und sofort prüfbar.
1. `ai_state.gd` + `balance.gd`: alle vier Statics und alle Konstanten. Rein, headless,
   schnell — deckt die weltfreien Tests sofort ab.
2. `building.gd`: `entrance_cell_for` / `approach_cell_for` extrahieren, `entrance_cell()` /
   `edge_spawn_position()` delegieren; Tests in `tests\test_economy.gd`. **Vor** Schritt 4,
   weil der Sweep sie braucht.
3. `ai_controller.gd`: `SiteNote`, `take_idle_for`, `_tick_build_crews`, Tor in `_tick_build`,
   `_send_escort_if_remote` aus `_tick_build` entfernen, Tick-Reihenfolge.
   → **Problem 1, eigenständig spielbar. Commit 2.**
4. `_plot_reachable` auf Anlaufzelle + Insel, `_home_island(s)`, `spacing`-Parameter, Bann mit
   Ablauf, `_reachable_plots` entfernen. **Hier messen** — das ist die Stelle, an der 10e
   regressiert ist.
5. `_tick_site_guard` + `_self_scrap`-Flag. → **Problem 2. Commit 3.**
6. `Brave.order_supply_wood` + `_fixed_delivery_target`/`_fixed_target_wants_wood` +
   `TribeCommands.order_supply_wood` + Tests. Reine Einheitenmechanik, ohne KI.
7. `_tick_shop_supply` + Bedarfsrechnung + `haul_crew_count`. Nützt sofort: rettet stalled
   Baustellen **und** Werkstätten, auch ohne Regale.
8. `_tick_vehicle_crews` + Cache-Erweiterungen + `set_rally_point`. → **Problem 3,
   unabhängig von 6/7. Commit 4.**
9. Werkstattregal: Cache-Klassifizierung → `_find_shop_depot_plot` → `&"shop_depot"` in
   `BUILD_SCENES`/`BUILD_FOOTPRINTS`/`_tick_build` → Bauordnungszweig.
10. Werkstatt-Tor (`shops_unproductive`) — **zuletzt** in diesem Block, weil es von 7–9
    abhängt: vor dem Nachschub gegattert würde die KI bei einer Werkstatt je Art einfrieren.
    → **Commit 5.**
11. Teil 5: `_arena_span`/`_enemy_anchors`, Territoriumstest in `_detect_threat`, relativer
    `defend_radius`, gestaffelter Wirtschafts-Stop, Miliz-Deckel. → **eigenständig spielbar und
    für kleine Karten der wichtigste Fix.**
12. Teil 5.3: die sieben reinen Profil-Statics + `"cramped"`/`"watchtower_target"` in der
    Bauordnung + `_expansion_anchor`-Territoriumstest. → **Commit 6.**
13. `CLAUDE.md` §5 korrigieren („Reinkarnationsplatz nur per Zauber/Katapult zerstörbar" ist
    7g-Stand und widerspricht §7) und §7 um „ist kein Angriffsziel" ergänzen.
14. Messung dokumentieren, PROGRESS.md (Abweichungen + Messtabelle im 10e-Format), Checkbox in
    `00_overview.md`, Push.

---

## Tests

**Reine Statics** (`tests\test_ai.gd`, weltfrei):
`test_site_worker_target_scales_with_footprint_while_grading`,
`test_site_worker_target_drops_after_the_foundation`,
`test_site_worker_target_leaves_room_for_the_passive_recruiter`,
`test_builder_budget_is_capped_by_the_actual_demand`,
`test_builder_budget_never_exceeds_the_economy_crew`,
`test_builder_budget_leaves_the_early_game_a_wood_crew`,
`test_site_is_supplied_accepts_a_wood_starved_site`,
`test_site_is_supplied_releases_the_gate_after_the_grace_period`,
`test_haul_crew_count_scales_with_braves`.

**Bautrupps** (Welt, Ein-Tick-Zusicherungen):
`test_ai_puts_workers_on_its_own_construction_site` (Kernfix),
`test_ai_staffs_a_site_the_recruiter_cannot_reach` (> 30 m),
`test_ai_sends_the_nearest_braves_to_a_site`,
`test_ai_does_not_reorder_braves_already_on_a_site` (zwei Ticks; dieselben Objekte in
`site.workers`, `task_cell`-Claim und `carried_wood` überleben),
`test_ai_skips_wood_stalled_sites_when_staffing`,
`test_ai_skips_a_site_being_demolished` (**F3**),
`test_ai_reserves_builders_before_training`,
`test_ai_opens_no_second_site_while_the_first_has_no_workers`,
`test_an_unsupplyable_site_stops_blocking_after_the_grace_period`.

**Erreichbarkeit / Nachkontrolle:**
`test_plot_reachability_is_an_island_compare` (Graben-Welt: abgelehnt; Graben aufgefüllt +
`update_region` ⇒ angenommen — der alte Ewigkeits-Negativcache hätte für immer „nein" gesagt),
`test_plot_requires_a_walkable_approach_cell`,
`test_relax_pass_still_requires_a_reachable_entrance`,
`test_plot_ban_expires_so_a_landbridge_reopens_the_ground`,
`test_home_island_falls_back_to_the_braves_when_the_base_is_enclosed`,
`test_site_guard_scraps_a_site_that_lost_its_walkable_approach`,
`test_site_guard_needs_two_strikes`,
`test_site_guard_abandons_instead_of_demolishing_a_half_built_site` (**F8/F9**),
`test_site_guard_does_not_walk_the_buildings_list` (`dbg_building_passes` bleibt 1),
`test_scrapping_a_dead_site_does_not_pause_construction`.
In `tests\test_economy.gd`: `test_approach_cell_for_matches_the_live_delivery_point`,
`test_approach_cell_for_reports_none_when_the_plot_is_enclosed`.
**Ersetzt:** `test_plot_reachable_success_cache` (der Positiv-Cache verschwindet) — die einzige
bewusste Test-Löschung, in PROGRESS.md als Abweichung dokumentieren.

**Neu `tests\test_wood_supply.gd`** (Brave-Ebene, ohne KI):
`test_supply_order_takes_only_braves`,
`test_supply_brave_sources_from_the_nearest_rack`,
`test_supply_brave_falls_back_to_a_ground_pile`,
`test_supply_brave_chops_when_nothing_is_stored`,
`test_supply_brave_fills_the_carry_capacity`,
`test_supply_delivery_lands_in_the_workshop_stock`,
`test_supply_job_does_not_relay_into_another_depot` (der `_tick_pickup`-Guard — die heikelste
Interaktion),
`test_supply_job_ends_when_the_target_is_satisfied`,
`test_supply_job_ends_when_the_target_is_destroyed`,
`test_supply_job_delivers_a_full_load_when_the_target_fills_up`,
`test_supply_job_never_marks_the_target_stalled`,
`test_new_order_cancels_the_supply_job`,
`test_supply_and_depot_haul_predicates_are_disjoint`,
`test_supply_brave_skips_a_rack_that_already_feeds_the_target`,
`test_depot_haul_still_works` (Regressionswächter für das nicht angetastete `_haul_target`).

**Fahrzeuge / Werkstätten** (`tests\test_ai.gd`):
`test_ai_crews_a_blocking_vehicle_with_one_unit`,
`test_ai_prefers_warriors_over_braves_for_vehicle_crews`,
`test_ai_never_crews_a_preacher`,
`test_ai_uses_braves_for_vehicles_only_on_surplus`,
`test_ai_never_strips_the_attack_wave_for_vehicle_crews`,
`test_ai_sets_a_workshop_muster_point_off_the_pad`,
`test_tick_cache_hands_out_each_idle_warrior_once`,
`test_shop_supply_targets_a_stalled_workshop`,
`test_shop_supply_leaves_a_fresh_shop_to_its_own_fetchers` (Geduld),
`test_shop_supply_does_not_double_staff_one_shop`,
`test_supply_crew_survives_the_tick_it_was_created_in`,
`test_supply_inbound_wood_is_not_ordered_twice`,
`test_stalled_site_gets_a_supply_crew`,
`test_build_order_places_a_shop_rack_before_the_next_workshop`,
`test_build_order_gates_the_next_workshop_on_a_working_one`,
`test_build_order_ignores_a_cap_reached_shop_when_gating`,
`test_shop_rack_plot_lies_inside_the_shop_absorb_radius`,
`test_shop_rack_plot_keeps_the_vehicle_exit_clear`,
`test_shop_rack_plot_avoids_another_buildings_absorb_radius`,
`test_shop_rack_is_not_counted_as_a_forward_depot`,
`test_shop_rack_plot_does_not_touch_the_shared_plot_budget` (`dbg_plot_cells` unverändert —
der 10e-Regressionswächter),
`test_ai_tick_cache_walks_units_once_per_tick` (bestehenden Wächter nach den neuen Feldern
erneut zusichern).

**Kartengröße / Arena** (`tests\test_ai.gd`; die reinen Statics sind weltfrei):
`test_defend_radius_shrinks_on_a_cramped_arena`,
`test_is_cramped_matches_the_island_four_tribe_spacing` (36,2 → eng; 82 → offen),
`test_cramped_profile_shrinks_the_plot_search_radius`,
`test_cramped_profile_forbids_forward_depots`,
`test_cramped_profile_attacks_with_a_smaller_army`,
`test_arena_span_uses_the_nearest_enemy_reincarnation_site`,
`test_arena_span_falls_back_to_the_map_edge_without_enemy_sites`,
`test_enemy_at_its_own_base_is_not_a_threat` (**der Kernfix** — Welt mit zwei Ankern 36 Zellen
auseinander und Feindeinheiten an *deren* Anker: `_detect_threat()` bleibt leer),
`test_enemy_inside_our_territory_is_a_threat` (Gegenkontrolle),
`test_a_single_scout_does_not_halt_the_wood_logistics`,
`test_a_single_scout_does_not_recall_an_attack_wave`,
`test_militia_keeps_half_the_idle_braves`,
`test_no_militia_below_the_minimum_brave_count`,
`test_expansion_anchor_avoids_enemy_territory`,
`test_ai_on_a_cramped_map_fields_real_army_before_attacking` (Integrationszusicherung über
mehrere Ticks: keine `order_attack` auf Braves, solange die Armee unter
`army_attack_size(arena)` liegt).

**Reinkarnationsplatz** — Erweiterung `tests\test_building_assault.gd` (dort liegen die
bestehenden Zusicherungen `test_reincarnation_site_not_assailable_by_units` → umbenennen auf
`test_reincarnation_site_is_not_attackable`, und
`test_reincarnation_site_ignores_spells_catapults_and_lava` bleibt als Schadenswächter):
`test_catapult_refuses_an_order_on_the_reincarnation_site`,
`test_catapult_auto_scan_skips_the_reincarnation_site` (der Kreis als **nächstes** feindliches
Gebäude — genau die gemeldete Situation),
`test_fire_ram_refuses_an_order_on_the_reincarnation_site`,
`test_airship_refuses_an_order_on_the_reincarnation_site`,
`test_vehicle_drops_a_building_target_that_became_unattackable`,
`test_player_right_click_on_the_circle_stays_a_move_order` (in `tests\test_ui_logic.gd`).
In `tests\test_ai.gd`:
`test_ai_spell_heuristic_ignores_the_reincarnation_site`,
`test_ai_attack_target_skips_the_reincarnation_site`,
`test_ai_marches_at_enemy_units_when_only_the_circle_is_left` (die 10d-Siegkette).

**Erweiterung `tests\test_workshop.gd`:**
`test_rack_inside_the_absorb_radius_counts_as_stock`,
`test_rack_outside_the_absorb_radius_is_not_stock` (Negativkontrolle für
`AI_SHOP_DEPOT_MAX_DIST`),
`test_fed_workshop_keeps_its_workers_inside`,
`test_fed_workshop_starts_production_without_a_fetch_trip`,
`test_occupied_neighbour_does_not_drain_a_fed_rack`.

---

## Messung und Verifikation

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_earlygame.gd -- map=bergpass sim=600
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_earlygame.gd -- map=seenland sim=600
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_earlygame.gd -- map=island sim=600
```

**Neu: `island` gehört in die Messreihe.** `benchmark_earlygame` läuft heute auf Bergpass und
Seenland (beide 256) — genau die Karten, auf denen der Fehler aus Teil 5 **nicht** auftritt.
Mit 4 Stämmen auf Insel muss der Lauf zeigen, dass die KI dort überhaupt eine Armee aufbaut
(neuer Zähler `dbg_militia_orders` gegen 0 in den ersten Minuten) und dass die Holzlogistik
läuft (`dbg_supply_runs`/Fäll-Trupps > 0 statt dauerhaft 0).

- **Suite grün, Output frei von `SCRIPT ERROR`** — abgebrochene Testmethoden melden trotzdem
  „0 failed". Der Ladecheck instanziiert den `AIController` **nie** (Menüpfad); maßgeblich ist
  dort die Suite.
- **Neue statische Zähler** am `AIController`, in die Benchmark-Fensterzeile aufgenommen wie
  `dbg_plot_*` (inkl. Reset): `dbg_site_orders`, `dbg_builders_assigned`, `dbg_sites_unstaffed`,
  `dbg_site_scraps`, `dbg_supply_runs`, `dbg_vehicles_crewed`, `dbg_shops_blocked`,
  `dbg_militia_orders`, `dbg_threat_ticks`.
  **Wall-Clock-Vergleiche der 4-Wege-KI-Schlacht sind nicht aussagekräftig** (PROGRESS.md
  „Phase 10e → Messung": zwei Läufe auf identischem Code lieferten 8,90 ms und 18,72 ms, und
  die Läufe divergieren chaotisch). Abnahmekriterium sind die Zähler: `dbg_sites_unstaffed`
  gegen 0, `dbg_vehicles_crewed > 0`, `dbg_shops_blocked` klein.
- **Bauplatzsuche:** Zeile `plots: %d scans, %d cells, %.1f ms` plus „schlimmster KI-Tick" und
  `islands: %d fills, %.1f ms` vor/nach vergleichen. **Erwartung:**
  `dbg_plot_us / dbg_plot_scans` **sinkt** (das A\* ist weg), `dbg_plot_scans` **sinkt** (das
  Tor spart Suchen), `dbg_plot_cells / dbg_plot_scans` bleibt gleich oder steigt leicht (Sweeps
  geben später auf, weil die A\*-Deckelung nicht mehr greift). **Insel-Fills müssen in der
  Häufigkeit unverändert bleiben** (je Fill 42–52 ms). Referenz 10e: Bergpass 154,5 ms /
  Seenland 127,3 ms pro teuerstem 30-s-Fenster.
- **Gegenrechnung (F10):** eine gefütterte Werkstatt verlässt `_tick_active` früh und spart
  `O(Stapel × Gebäude)` **pro Physikframe**; das Werkstatt-Tor entfernt bis zu 8 solcher
  Gebäude. Netto ist eine **Verbesserung** plausibel — aber nur behaupten, wenn gemessen.

## Manuelle Prüfung (Nutzer)

- Langes Skirmish: **jede** KI-Baustelle hat innerhalb weniger Sekunden Arbeiter. Keine
  Geisterbaustellen, die 2 Minuten stehen und dann verfallen.
- Keine KI-Gebäude an Stellen, an die niemand kommt; keine Baustelle, die die Tür eines
  Nachbargebäudes zumauert. Eine Landbrücke auf ein früher abgelehntes Stück Land wird später
  wieder bebaut.
- Werkstätten produzieren **fortlaufend**: fertige Katapulte/Feuerrammen werden zügig bemannt,
  verlassen den Bauplatz, sammeln sich am Sammelpunkt und kommen in Wellen mit.
- Neben Werkstätten stehen Holzregale, die sich sichtbar füllen; Nachschub-Braves laufen zu
  ausgehungerten Werkstätten und Baustellen.
- Die KI baut **nicht** mehr Werkstätten, während bestehende leer stehen.
- **Insel mit 4 Stämmen** (der akute Kleinkarten-Fall): die KI wirft **keine Braves** mehr gegen
  den Nachbarn, sondern baut auf, bildet aus und greift mit einer echten Armee an; ihre
  Holzwirtschaft läuft sichtbar; ihre Basis bleibt kompakt und sie baut **kein** Lager vor der
  feindlichen Tür. Ein einzelner eigener Späher an ihrem Dorfrand hält ihre Wirtschaft nicht an.
- **Reinkarnationsplatz:** Rechtsklick mit Katapult, Feuerramme oder Luftschiff auf einen
  feindlichen Kreis wird **nicht** angenommen (der Klick bleibt ein Bewegungsbefehl); ein
  Katapult, das an einem Kreis vorbeifährt, beschießt ihn **nicht** mehr von selbst. Die KI
  verschwendet keine Blitze/Vulkane mehr darauf und ihre Angriffswelle geht auf die
  **Einheiten** los, wenn nur noch der Kreis steht.
- **Bergpass/Seenland** verhalten sich wie vorher (Expansion, vorgeschobene Lager, spätere,
  größere Wellen) — das Profil darf die großen Karten nicht mitverändern.
- FPS im KI-Spätspiel unverändert oder besser.

## Risiken

1. **Wiederholung der 10e-Bauplatz-Regression** (gemessen: 3–4× teurer, schlimmster KI-Tick
   > 2×). Diese Phase fasst **Budgets, Ankerliste und Prüfreihenfolge nicht an** und legt den
   Regal-Scan bewusst **neben** `_find_plot`. Schritt 4 ist ein eigener Messpunkt.
2. **Das Regal steht in der Ausfahrt** — der schlimmste Fehlermodus des Entwurfs: ein 1×1
   navigations-solides Gebäude 2 m vor dem Werkstatt-Tor kann das frische Fahrzeug einsperren
   und `exit_blocked()` dauerhaft machen, würde also Problem A *verursachen*. Abgesichert
   durch `AI_SHOP_DEPOT_SIDE_CLEAR` und `test_shop_rack_plot_keeps_the_vehicle_exit_clear`;
   im Zweifel liefert `_find_shop_depot_plot` lieber `-1` (kein Regal) als eine schlechte Zelle.
3. **Eine spätere Baustelle neben dem Regal frisst es.** `_absorb_piles()` hat **kein**
   Eigentumskonzept; die „kein anderer Absorptionsradius"-Regel gilt nur zum
   Platzierungszeitpunkt. Symptom: eine Werkstatt stallt wieder, nachdem die Basis um sie
   gewachsen ist. Billiger Fix, falls es auftritt: die Regalzellen in eine kleine
   „freihalten"-Menge legen, die `_plot_has_clearance` mitliest.
4. **Das Regal wird zum Liefermagnet.** `_nearest_depot()` bevorzugt das nächste Regal *mit
   Platz*, und ein von seiner Werkstatt geleertes hat immer Platz — Fäll-Trupps könnten Holz
   zu den Werkstätten statt zu den Baustellen routen. `AI_MAX_SHOP_DEPOTS = 3` begrenzt das;
   im Spieltest den Füllstand des Basislagers beobachten.
5. **Weniger Armee im Frühspiel.** Das Budget zieht vor `_tick_train` (bei 10 Braves sind 4 auf
   der Baustelle) — obendrauf auf die 10e-Anhebung (`ARMY_ATTACK_SIZE 8→12`) und die
   10f-Verteuerung des Wohnraums. Erwünscht, aber die einzige Stellschraube ist
   `AI_BUILDER_BRAVE_SHARE`.
6. **Bemannen verkleinert den marschierenden Trupp** (2 Krieger → 1 Katapult-Eintrag). Die drei
   Bremsen deckeln es bei 25 % der Armee; ob ein Katapult zwei Krieger *wert* ist, ist eine
   Balance-, keine Codefrage — `AI_VEHICLE_ARMY_CREW_SHARE` nach dem Spieltest nachziehen.
7. **`take_idle_for` skaliert mit dem Idle-Pool** (O(Pool) je Baustelle, gedeckelt durch
   `AI_SITES_STAFFED_PER_TICK = 3`). Bei 1000 Einheiten ~1500 Distanzquadrate/Tick —
   vernachlässigbar, aber zu benennen: der Pool ist die einzige mit der Bevölkerung wachsende
   Struktur.
8. **Nachschub-Holz ist für das Ziel unsichtbar** (der Brave steht nicht in `target.workers`).
   Nur die KI-eigene `_supply_crews`-Buchführung verhindert Überbestellung; sie ist auf
   `AI_MAX_SUPPLY_CREWS` begrenzt, Worst Case sind ein paar verschwendete Fuhren.
9. **Abriss-Fallen:** ab Baustufe blockiert ein Abriss den Slot dauerhaft (F8) → nur
   `abandoned`; jeder Abriss löst `_rebuild_ticks = 15` aus → `_self_scrap`-Flag; nach dem
   Abriss enthält `cache.sites` ein zerstörtes Gebäude → der Guard muss den Cache reparieren
   und alle Konsumenten `is_instance_valid` **und** `health > 0` prüfen.
10. **Wechselwirkung mit 10f.** Mehr, kleinere Hütten heißt mehr Gebäude, mehr Baustellen und
    mehr Holzbedarf; der Ausbau-Job (`order_upgrade`) ist ein **vierter** Holzverbraucher und
    muss in 4.2 Priorität 4 wirklich mitgezählt werden, sonst hungern ausbauende Hütten die
    Baustellen aus.
11. **Der Territoriumstest kann zu freundlich werden.** Ein Gegner, der seine Basis verloren
    hat, hat keinen Anker mehr — dann fällt der Test auf „immer Bedrohung" zurück (richtig) —
    aber ein Gegner, dessen Anker *nahe an unserem* liegt, hat ein größeres „eigenes"
    Territorium als gedacht. Deshalb bleibt `defend_radius` als zweite, unabhängige Grenze
    daneben stehen; beide müssen erfüllt sein.
12. **Das kompakte Profil kann die KI zu passiv machen.** Suchradius 18 auf einer engen Karte
    mit wenig Holz um die Basis kann heißen: kein gültiger Bauplatz mehr. Abgesichert durch die
    bestehende Relax-/Fehlschlag-Mechanik (`_plot_fail_ticks`) und dadurch, dass der
    Förster-Zweig weiterhin greift; im Spieltest auf „KI baut gar nichts mehr" achten und dann
    `AI_PLOT_SEARCH_RADIUS_CRAMPED` anheben.
13. **`benchmark_earlygame` deckte den Kleinkarten-Fall bisher nicht ab** (nur 256er-Karten) —
    die Insel-Messreihe ist neu und ihre Baseline muss erst erhoben werden, es gibt also keinen
    Vorher-Wert aus 10e zum Vergleichen. Ehrlich als „erste Messung" kennzeichnen.
14. **Die Umbenennung `is_assailable_by_units` → `is_attackable` ist mechanisch, aber
    projektweit** (7 Aufrufstellen + 1 Test). `--check-only` fängt so etwas nicht zuverlässig;
    maßgeblich ist die Suite plus `--headless --quit`. Nicht anfassen: der gleichnamig klingende
    Drift-Anker `Airship._nearest_reincarnation_site()`.
15. **CLAUDE.md muss mit.** §5 trägt noch die 7g-Formulierung „Reinkarnationsplatz nur per
    Zauber/Katapult zerstörbar"; §7 sagt seit 10d korrekt „unverwundbar". Der Widerspruch war
    genau der Grund für die vier offenen Zielpfade und wird in dieser Phase mitkorrigiert.
16. **`Workshop._tick_active` bleibt strukturell teuer** (F10). Dieser Plan *reduziert* die
    Kosten, behebt sie aber nicht — gehört als eigener Punkt in `plans\bugs_backlog.md`.

## Definition of Done

- [ ] Testsuite grün, Output ohne `SCRIPT ERROR`, `--headless --quit` fehlerfrei
- [ ] Neue Diagnosezähler + Vorher/Nachher-Tabelle in PROGRESS.md (10e-Format)
- [ ] Bauplatzsuche ohne Regression gegen den 10e-Stand (Bergpass **und** Seenland),
      Insel-Fill-Häufigkeit unverändert
- [ ] Insel-Messreihe (4 Stämme) erhoben: `dbg_militia_orders` früh gegen 0, Holzlogistik läuft
- [ ] Ersetzter Test (`test_plot_reachable_success_cache`) als Abweichung dokumentiert
- [ ] Manuelle Prüfung durch den Nutzer bestanden — **auf Insel und auf Bergpass**
- [ ] PROGRESS.md ergänzt, Checkbox 10g in `00_overview.md` abgehakt, `CLAUDE.md` §5/§7
      korrigiert
- [ ] `is_attackable()` an **allen** Zielwahl-Pfaden respektiert (Einheiten, Fahrzeuge,
      Luftschiff, KI-Zauber, KI-Zielwahl); beide veralteten Kommentare ersetzt
- [ ] Sechs Commits gepusht (Reinkarnationsplatz · Bautrupps · Erreichbarkeit · Fahrzeuge ·
      Holzverteilung · Arena)
