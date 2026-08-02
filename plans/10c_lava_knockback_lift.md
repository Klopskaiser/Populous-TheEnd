# Phase 10c — Lava-Überarbeitung, Rückstoß & Anheben

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

1. **Lava** wird von einer orangen, nicht wirklich fließenden Flüssigkeit zu
   einer **roten, zähen, langsam fließenden Masse**, die dem Gelände folgt.
   Vulkan: **2 statt 4** Lavastöße, dafür langsamerer, geländefolgender Fluss.
   Erdbeben: Lava tritt **an der oberen Bruchkante** aus und läuft die Kante
   hinunter in die Senke. Lebensdauer zentral in `Balance` (Startwert **5 s**),
   Katapultlava mit eigenem Wert. **Performance ist Abnahmekriterium.**
2. **Umherwirbeln von Einheiten:** Feuerball und Feuerregen bekommen einen
   etwas größeren Schubbereich und heben Getroffene leicht an; der Blitz erhält
   einen **stärkeren** Schub-/Hebeeffekt als der Feuerball; Feuerkrieger können
   Ziele anheben (ein Teil der bestehenden Umwerf-Chance wird dorthin
   umverteilt); **jeder** Feuerballtreffer auf eine **bereits fliegende**
   Einheit verstärkt den Hebeeffekt.

## Bestandsaufnahme (vor Umsetzung verifiziert)

- **Zwei Lava-Entitäten, kein Zellzustand:** `scripts/spells/lava_surge.gd`
  (radiale Fläche, `EXPAND_SPEED 3.2`, `LIFETIME 5.4`, `ImmediateMesh`-Streifen,
  `_band_color` :117 orange) und `scripts/spells/lava_flow.gd` (Band bergab,
  `FLOW_SPEED 3.0`, `_advance` :95, `_downhill` :113 stoppt unter
  `MIN_SLOPE 0.04`, `_point_color` :215 orange).
- Erzeuger: `volcano_zone.gd` (`SURGE_INTERVAL 4.5`, `LIFETIME 20` → **4**
  Stöße), `earthquake.gd:114` `_spawn_fault_lava` (3 Flows bei Offset -3/0/+3
  **auf** der Bruchlinie), `siege_shot.gd:193` (`LAVA_RADIUS 0.8`).
- **Erdbeben-Fehler im Bestand:** die Flows werden in `execute()` gespawnt,
  also **bevor** der 2-s-`TerrainMorph` die Kante überhaupt geöffnet hat — sie
  laufen über noch flaches Gelände und versacken sofort.
- **Perf-Fallen im Bestand:** `LavaFlow._ignite_touching_units` (:127) stellt
  **eine Raumabfrage pro Segment** (bis ~16 pro Prüfung, ×3 Flows je Erdbeben);
  `_touch_buildings` (:151) ist O(Gebäude × Segmente).
- Rückstoß-Kern: `Unit.displace` (:1413), `apply_knockback` (:1427),
  `throw_airborne` (:1695) — **stapelt bereits die Geschwindigkeit, wenn das
  Ziel schon fliegt** (:1698), genau der benötigte Primitiv;
  `_land_from_throw` (:1847) wandelt Restgeschwindigkeit in ein Ausrollen.
- **Latenter Fehler:** `displace()` (:1413) blockt nur `DEAD`/`rides_airborne()`
  — ein **THROWN**-Ziel bekommt heute noch einen Bodenschub von
  `Fireball._impact` (:154).
- Quellen: `units/fireball.gd:154` (Feuerkrieger: `apply_knockback` +
  `ROLL_CHANCE`/`ROLL_CHANCE_ROLLING` + Nachbar-Rollen; fliegende Ziele nehmen
  `FIREWARRIOR_AIRBORNE_MULT = 2` Schaden), `spells/fireball_bolt.gd:84`
  (`THROW_BACK 5.0`, `THROW_UP 6.0`, Direkt 60 @ 0.8 m / Splash 30 @ 2.5 m),
  `spells/lightning.gd:66` (Nachbarn im `NEIGHBOR_RADIUS` bekommen **nur**
  `start_roll`), `spells/firestorm.gd` (12 Bolts über `FireballBolt`).
- Messwerkzeug: `tests/benchmark_stress.gd` (fester Seed `BENCH_SEED`, castet
  alle 5 s). `_tick_projectiles` steckt dort heute in `rest_us` zusammen mit
  `_apply_idle_regroup` — **Lavakosten sind aktuell nicht sichtbar.**

## Dokumentierte Auslegungen

- **`LavaSurge` und `LavaFlow` bleiben getrennte Klassen** (3 Produktionsorte,
  10+ Testzusicherungen hängen daran). Geteilt wird das **Modell**, nicht die
  Geometrie: „ein gemeinsames Modell, zwei Formen".
- **Farben bleiben presentation-lokal** in `LavaCommon`, nicht in `Balance`
  (Projektkonvention).
- **Vulkan-Intervall 3,5 s ist kein freier Wert.** Gebäude nehmen pro
  `LAVA_BUILDING_STAGE_TIME 5.0` Kontaktsekunden eine Zerstörungsstufe, und der
  Zähler verfällt nach `LAVA_BUILDING_CONTACT_GRACE 1.0` ohne Kontakt. Mit
  `LAVA_MOLTEN_TIME 3.0` deckt Stoß 1 (t≈3,0) bis t≈6,0 ab; Stoß 2 bei t=6,5
  lässt 0,5 s Lücke < Grace → 3,0 + 3,0 = 6,0 ≥ 5,0 → der Vulkan zerstört
  weiterhin Gebäudestufen. **Ab ~4,5 s Abstand würde der Gebäudeschaden des
  Vulkans still verschwinden.** Alternativ-Stellschraube:
  `LAVA_BUILDING_STAGE_TIME` auf 3.0 senken.
- **Lift ersetzt beim Feuerkrieger den Bodenschub** (weniger Horizontale,
  dafür leichtes Abheben), die Summe der Chancen bleibt unverändert.

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Gemeinsames Modell** | `scripts/spells/lava_common.gd` (neu, `class_name LavaCommon`, nur Statics) | `COLOR_HOT = Color(1.0, 0.22, 0.04)`, `COLOR_MID = Color(0.62, 0.06, 0.02)`, `COLOR_SCORCH = Color(0.07, 0.05, 0.04)`; `color_for(age, molten_time, cooled, scorch)`; `downhill(td, x, z)` (Länge = Gefälle); `flow_speed(slope) = LAVA_FLOW_SPEED * clamp(1 + LAVA_SLOPE_BIAS * slope, 0, 3)` — bergauf 0, die Lava staut sich; `ignite_all(um, at, radius, source)` |
| **Radialfläche** | `scripts/spells/lava_surge.gd` | `_radius` → `_sector_radius`/`_sector_front_time` (`LAVA_SECTORS = 20`). Pro Prüfschritt je Sektor **eine** Gefälleprobe am Frontpunkt, Vorschub über `flow_speed` → bergauf staut es, bergab läuft es. `is_molten()` = „irgendein Sektor im Glühfenster". Zündung: **eine** Raumabfrage über den größten Radius, dann Sektorzuordnung per `atan2`. `LIFETIME` wird zu `var lifetime` (Katapult setzt eigenen Wert). Zähflüssigere Optik: `RING_STEP 0.8 → 1.0`, langsamere Wulstbewegung |
| **Band** | `scripts/spells/lava_flow.gd` | `FLOW_SPEED` → `LavaCommon.flow_speed(slope)` pro Schritt; Steuerung `lerp(dir, downhill, 0.45 → 0.6)`; neues `start_delay` (Kopf bleibt stehen und folgt nur der Terrainhöhe); `SEGMENT_SPACING 0.45 → 0.6` + harte Obergrenze `MAX_SEGMENTS = 28`; `HALF_WIDTH 0.5 → 0.65`, Kopfwulst 1.35 → 1.5, langsamere Wellen. **Perf:** `_ignite_touching_units` (:127) auf **eine** Abfrage über einen Hüllkreis umstellen; `_touch_buildings` (:151) mit Hüllkreis-Vorfilter |
| **Vulkan** | `scripts/spells/volcano_zone.gd` | `VOLCANO_SURGE_COUNT 2` (gezählte Stöße, robust gegen spätere Lifetime-Änderungen), `VOLCANO_SURGE_INTERVAL 3.5`. Der dauerhafte Flächen-Zündradius (:87) schrumpft von `LAVA_REACH 7.5` auf den Krater (`RADIUS * 0.6`), damit die Flanken von der **echten** geländefolgenden Lava bestimmt werden |
| **Erdbeben** | `scripts/spells/earthquake.gd` | `_spawn_fault_lava` (:114): Startpunkte auf die **Hebungsseite** der Bruchkante versetzt (`EARTHQUAKE_LAVA_EDGE_OFFSET`), Richtung die Kante hinab, `start_delay = EARTHQUAKE_LAVA_DELAY` (behebt den Bestandsfehler), Lifetime/Glühdauer aus `Balance`, `scorch = false` bleibt |
| **Katapult** | `scripts/units/siege_shot.gd` | `_spawn_lava` (:193): `surge.lifetime = Balance.LAVA_CATAPULT_LIFETIME`; `LAVA_RADIUS` und das `damage_buildings`-Flag bleiben |
| **Rückstoß-Primitiv** | `scripts/units/unit.gd` | `apply_lift(dir, horizontal, vertical, fall_damage = 0)`: Früh-Ausstieg bei `DEAD`/`rides_airborne()`; Richtung flach + normalisiert mit Zufalls-Fallback bei ~Null (der Blitz übergibt heute unnormalisierte, evtl. Null-Vektoren); bei bereits fliegendem Ziel `horizontal * LIFT_AIRBORNE_PUSH_FACTOR` und `vertical + LIFT_AIRBORNE_BONUS`, sonst direkt. Baut auf `throw_airborne` auf, das die Geschwindigkeit bereits stapelt |
| **Feuerball/Feuerregen** | `scripts/spells/fireball_bolt.gd` | Lokale `THROW_BACK`/`THROW_UP` entfallen; `_explode()` fragt über `max(SPLASH_RADIUS, FIREBALL_PUSH_RADIUS)` ab — Einheiten zwischen 2,5 und 3,2 m nehmen **keinen** Schaden, werden nur geschoben/gehoben; `apply_lift(...)` statt `throw_airborne(...)` |
| **Blitz** | `scripts/spells/lightning.gd` | `NEIGHBOR_RADIUS` → `LIGHTNING_PUSH_RADIUS`; Nachbarn bekommen `apply_lift(...)` statt `start_roll(...)` (das Ausrollen entsteht beim Landen über `_land_from_throw` von selbst) |
| **Feuerkrieger** | `scripts/units/fireball.gd` | `_impact()` (:146-174) umgebaut. **Reine** statische Entscheidungsfunktion `impact_outcome(r, lift_chance, roll_chance) -> int` (Muster: `SiegeShot.roll_chance_for_slope`). Fliegendes Ziel → nur `apply_lift`, kein Bodenschub (behebt zugleich den latenten `displace`-Fehler). Sonst: LIFT ersetzt den Rückstoß, ROLL wie bisher, PUSH = reiner Rückstoß |
| **Messung** | `tests/benchmark_stress.gd` | `rest_us` in `regroup_us` + `proj_us` aufteilen und `proj` ausgeben; `&"volcano"` in die `SPELLS`-Liste aufnehmen |
| **Tests** | `tests/test_spells.gd`, `tests/test_combat.gd` | siehe unten |

## Neue Balance-Konstanten

```gdscript
# --- LAVA: Fluss, Lebensdauer, Kostendeckel ---
## Lebensdauer JEDER Lava-Instanz nach dem Spawn (Vulkan, Erdbeben, ...).
const LAVA_LIFETIME: float = 5.0
## Katapult-Pfütze: eigener Wert, Verhalten sonst identisch.
const LAVA_CATAPULT_LIFETIME: float = 5.0
## Zähflüssig: Grundtempo der Front (m/s) — vorher 3,0-3,2.
const LAVA_FLOW_SPEED: float = 0.9
## Hangabhängigkeit: Tempo = FLOW_SPEED * (1 + BIAS * Gefälle), bergauf 0.
const LAVA_SLOPE_BIAS: float = 2.5
## Unter diesem Gefälle staut sich die Lava zur Pfütze.
const LAVA_MIN_SLOPE: float = 0.04
## Glühdauer einer frisch überströmten Stelle (Schadensfenster).
const LAVA_MOLTEN_TIME: float = 3.0
## Kostendeckel: Kontaktprüfung und Mesh-Neubau (Sekunden).
const LAVA_CONTACT_INTERVAL: float = 0.25
const LAVA_VISUAL_INTERVAL: float = 0.2

# --- Vulkan ---
const VOLCANO_SURGE_COUNT: int = 2
## ACHTUNG: > LAVA_MOLTEN_TIME + LAVA_BUILDING_CONTACT_GRACE schaltet den
## Gebäudeschaden des Vulkans still ab (Herleitung im Plan).
const VOLCANO_SURGE_INTERVAL: float = 3.5

# --- Erdbeben-Lava ---
const EARTHQUAKE_LAVA_STREAMS: int = 3
## Versatz von der Bruchlinie auf die HEBUNGSSEITE (obere Kante).
const EARTHQUAKE_LAVA_EDGE_OFFSET: float = 0.8
## Wartezeit, bis der TerrainMorph die Kante geöffnet hat.
const EARTHQUAKE_LAVA_DELAY: float = 1.2
const EARTHQUAKE_LAVA_RANGE: float = 3.5

# --- Rückstoß & Anheben ---
## Feuerball-Zauber und jeder Feuerregen-Bolt: Schubradius etwas GRÖSSER als
## der Schadensradius (2,5) — Randtreffer werden nur geschoben, nicht verletzt.
const FIREBALL_PUSH_RADIUS: float = 3.2
const FIREBALL_PUSH_SPEED: float = 5.0
const FIREBALL_LIFT_SPEED: float = 6.5
## Blitz: stärker als der Feuerball.
const LIGHTNING_PUSH_RADIUS: float = 2.6
const LIGHTNING_PUSH_SPEED: float = 7.0
const LIGHTNING_LIFT_SPEED: float = 9.0
## Feuerkrieger: Teil der Umwerf-Chance wird zu "Anheben" — Summe unverändert.
const FW_FIREBALL_ROLL_CHANCE: float = 0.06
const FW_FIREBALL_LIFT_CHANCE: float = 0.04
const FW_FIREBALL_ROLL_CHANCE_ROLLING: float = 0.30
const FW_FIREBALL_LIFT_CHANCE_ROLLING: float = 0.10
## Ein Lift ERSETZT den Bodenschub: weniger Horizontale, kleiner Hüpfer.
const FW_FIREBALL_LIFT_PUSH: float = 1.2
const FW_FIREBALL_LIFT_UP: float = 3.0
## Treffer auf bereits fliegende Ziele: der Lift wird IMMER verstärkt.
const LIFT_AIRBORNE_BONUS: float = 4.0
const LIFT_AIRBORNE_PUSH_FACTOR: float = 0.5
```

## Umsetzungsschritte

1. **Perf-Baseline aufnehmen** (`benchmark_stress`, `benchmark_mass`,
   `diag_stress_battle`) und Zahlen in PROGRESS.md festhalten. Vorher die
   `proj_us`-Aufspaltung im Benchmark einbauen, sonst ist Lava unsichtbar.
2. **`Unit.apply_lift` + Balance-Konstanten + die drei Aufrufer** + Tests.
   (Unabhängig von der Lava, kleineres Risiko, gleich spürbar.)
3. **`LavaCommon`** anlegen → `--headless --import`.
4. **`LavaSurge`** auf Sektoren + gemeinsames Modell umstellen.
5. **`LavaFlow`** auf gemeinsames Modell + `start_delay` + die beiden
   Perf-Korrekturen umstellen.
6. **Vulkan** (2 Stöße, Krater-Zündradius) und **Erdbeben** (Kante + Delay)
   und **Katapult** (eigene Lifetime) anpassen.
7. **Perf-Messung** gegen die Baseline, Bestandstests nachziehen.
8. Doku, PROGRESS.md, Commit/Push.

## Perf-Abnahme (verbindlich)

```bash
"C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe" --path D:\game\Populous-TheEnd --headless -s res://tests/benchmark_stress.gd
```

Kriterien:
- `proj`-Phase **Ø ≤ 1,0 ms** und **≤ 3,0 ms** im schlechtesten 150-Tick-Block.
- Gesamt-Ø und schlechtester Tick innerhalb **+5 %** der Baseline.
- In-Game „Stresstest" mit FPS-Overlay: Vulkan + Erdbeben ins Getümmel
  casten, FPS-Untergrenze unverändert.

Bei Überschreitung in dieser Reihenfolge nachziehen: `LAVA_CONTACT_INTERVAL`
0.25 → 0.3, `LAVA_VISUAL_INTERVAL` 0.2 → 0.25, `LAVA_SECTORS` 20 → 16,
`MAX_SEGMENTS` 28 → 20.

## Tests

**Lava (neu in `tests/test_spells.gd`):**
- `test_lava_colour_is_red` — `LavaCommon.color_for(...)` mit `r > 0.85`, `g < 0.30`.
- `test_lava_flow_speed_law` — `flow_speed(0) == LAVA_FLOW_SPEED`,
  `flow_speed(0.4) > flow_speed(0.1)`, `flow_speed(-0.5) == 0`.
- `test_lava_flows_slowly_downhill` — geneigte Karte, nach 2 s liegt
  `_travelled` im Rahmen des Gesetzes ±10 % und deutlich unter `3.0 * 2.0`.
- `test_lava_lifetime_constants` — Default-Flow `== LAVA_LIFETIME`,
  Katapult-Surge `== LAVA_CATAPULT_LIFETIME`.
- `test_volcano_spawns_exactly_two_surges`.
- `test_earthquake_lava_starts_on_upper_edge` — je Flow liegt der Startpunkt
  auf der Hebungsseite und die Richtung zeigt die Kante hinab.
- `test_earthquake_lava_waits_for_the_scarp` — `_travelled == 0` vor,
  `> 0` nach `EARTHQUAKE_LAVA_DELAY`.
- `test_lava_surge_follows_terrain` — geneigte Karte: Bergab-Sektor > 1,5 ×
  Bergauf-Sektor.
- `test_lava_flow_single_query_equivalence` — eine Einheit unter einem
  mittleren Segment entzündet weiterhin (sichert die Hüllkreis-Umstellung).

**Rückstoß/Lift (`tests/test_spells.gd` + `tests/test_combat.gd`):**
- `test_fireball_bolt_pushes_beyond_damage_radius` — Brave bei 3,0 m:
  volle Gesundheit, aber `THROWN`.
- `test_fireball_bolt_lift_amplifies_airborne_target` — y-Geschwindigkeit
  steigt um mindestens `LIFT_AIRBORNE_BONUS`.
- `test_lightning_neighbours_are_lifted_not_just_rolled` — Nachbar bei 2,2 m
  endet `THROWN` (wäre im alten 1,5-m-Radius gar nicht erfasst worden).
- `test_lightning_lift_stronger_than_fireball` — Konstantenvergleich.
- `test_firewarrior_fireball_outcome_split` — erschöpfend auf der reinen
  Funktion, plus Invariante `FW_FIREBALL_LIFT_CHANCE + FW_FIREBALL_ROLL_CHANCE
  == 0.10`.
- `test_firewarrior_fireball_always_lifts_airborne_target` — kein Rückstoß,
  mehr Höhe.
- `test_apply_lift_ignores_deck_passengers`.
- `test_apply_lift_zero_direction_fallback`.

**Bestandstests, die angepasst werden müssen** (im Commit auflisten):
`test_earthquake_spawns_short_fault_lava`, `test_volcano_cone_lava_and_permanence`,
`test_volcano_lava_contact_wrecks_buildings` (**beweist die 3,5-s-Herleitung**),
`test_volcano_zone_ignites_units_continuously` (Krater-Zündradius),
`test_lava_flow_ignites_burns_and_panics`, `test_lava_surge_building_damage_flag`,
sowie `tests/test_siege.gd:685/702/1132` und `tests/test_airship.gd:369/408`
(nur Lifetime — sollten durchlaufen).

## Manuelle Prüfung

- Vulkan: zwei deutlich getrennte, rote, zähe Lavawellen, die den Hang
  hinunterlaufen statt symmetrisch aufzupoppen; Gebäude nehmen weiterhin
  Zerstörungsstufen.
- Erdbeben: Lava tritt oben an der Kante aus und läuft in die Senke.
- Katapult: kleine rote Pfütze, verhält sich wie die übrige Lava.
- Feuerball/Feuerregen: Getroffene fliegen weiter und heben ab; am Rand
  werden sie nur geschoben.
- Blitz: Umstehende werden sichtbar stärker weggeschleudert als beim Feuerball.
- Feuerkrieger: gelegentliches Anheben statt Umwerfen; ein zweiter Treffer auf
  ein fliegendes Ziel schleudert es sichtbar höher.
- FPS im Massenkampf mit Lava.

## Risiken

1. **Gebäudeschaden des Vulkans kann still verschwinden**, wenn
   `VOLCANO_SURGE_INTERVAL` über `LAVA_MOLTEN_TIME + LAVA_BUILDING_CONTACT_GRACE`
   steigt. Wahrscheinlichste Regression des ganzen Blocks —
   `test_volcano_lava_contact_wrecks_buildings` ist der Wächter.
2. **`is_molten()` ändert seine Semantik** mit Sektor-Radien; `_touch_buildings`
   und `test_lava_surge_building_damage_flag` hängen daran.
3. **Balance-Nebenwirkungen des Lifts:** fliegende Einheiten sind lava-immun
   (`is_airborne()`-Skip) und nehmen doppelten Feuerkriegerschaden
   (`FIREWARRIOR_AIRBORNE_MULT`). Mehr Lift = Feuerball-Kombos stärker gegen
   Feuerkrieger, schwächer gegen Lava. Zudem mehr Ertrinkungstode an Küsten
   (siehe 10a).
4. **Nerf-Wirkung:** 2 langsame Stöße decken deutlich weniger Fläche ab als 4
   schnelle. Beim Spieltest bewusst gegenprüfen.
5. **Seeded Benchmark divergiert** nach jedem Schritt — pro Schritt neu
   baselinen, nicht über Schritte hinweg vergleichen.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Perf-Kriterien erfüllt und Zahlen in PROGRESS.md dokumentiert
- [ ] Manuelle Prüfung durch den Nutzer bestanden
- [ ] Checkbox 10c in [00_overview.md](00_overview.md) abgehakt, Commit/Push
