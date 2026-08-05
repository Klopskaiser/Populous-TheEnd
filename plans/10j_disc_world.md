# Phase 10j — Scheibenwelt im Weltall: runde Karten, Sternenhimmel, Sturz ins All

> **UMGESETZT am 2026-08-05.** Ist-Stand, Messwerte und Stolpersteine stehen in
> [PROGRESS.md](PROGRESS.md); dieser Plan bleibt als Entwurf stehen. **Vier seiner
> Annahmen haben sich am Code als falsch erwiesen** — sie sind unten an der jeweiligen
> Stelle korrigiert, damit niemand ihnen später wieder folgt:
>
> - **K1 — „drei Karten brauchen echten Neuentwurf" ist falsch.** `_corner_cells()`
>   setzt die Anker bei `(0,5 − 0,18) · size · √2 = 0,4525 · size`, also *innerhalb*
>   des Radius `0,5 · size`. Nötig war nur die Ankerfraktion 0,18 → 0,22 (Randabstand
>   6,9 → 15,4 Zellen bei 144). Kein Generator wurde inhaltlich angefasst.
> - **K2 — Terrain-Zauber können die Scheibe nicht vergrößern.** Die Maske sitzt IN
>   `is_walkable()`, und `NavGrid.update_region()` ist der einzige Solidity-Writer:
>   eine angehobene Void-Zelle kann nie begehbar werden. Die sechs geplanten Edits an
>   den Verform-Funktionen entfielen; ein Test belegt die Invariante stattdessen.
> - **K3 — der Plan nannte kein Rand-Mesh.** „Nackte Felskante" beschreibt nur die
>   Farbe; ohne Geometrie ist die Scheibe papierdünn. Neu: `TerrainRim` mit Felsband
>   **und geschlossener Unterseite** (Nutzerentscheidung).
> - **K4 — `_snap_to_ground()` war nie der unumgehbare Backstop**, den sein Kommentar
>   behauptete: die C2-Kernels in `UnitManager` schreiben `position` direkt. Sie sind
>   über A\* bzw. `is_cell_walkable` gesichert, aber die Garantie lautet anders als
>   dokumentiert — der Kommentar ist berichtigt.
>
> **Nutzervorgaben, die im Plan noch fehlen:** alle vier Karten wachsen um ×1,128
> (Insel/Plateau 144, Seenland/Bergpass 288), damit die **Scheibenfläche der alten
> Quadratfläche entspricht** (99,4 %) — die Scheibenwelt kostet keine Spielfläche. Und
> die Scheibe ist **endlich mit Unterseite**, keine bodenlose Wand.

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Abhängigkeit:** [Phase 10i](10i_construction_bugfix_combat_balance.md) sollte
> abgeschlossen sein — sie fasst dieselben Unit-Bewegungspfade an, die diese Phase
> umbaut.

## Ziel

Die Karten wirken arcadig: ein Quadrat, das an einer harten Kante endet, unter
einem flachen hellblauen Hintergrund. Ziel ist Immersion ohne die Kugelwelt des
Originals: **die Karte ist eine schwebende Scheibe im Weltall.** Runder Rand,
Sternenhimmel, und was über die Kante geschleudert wird, fällt ins Nichts.

> **Direkter Widerspruch zu Commit `95b0e73`, den diese Phase auflöst.** Dort wurde
> eine unsichtbare Mauer eingezogen, weil die Schamanin auf Plateau aus der Karte
> geflogen ist — sie stand danach auf unsichtbarem Boden außerhalb der Welt. Der
> **Bug war nicht das Verlassen der Karte, sondern dass draußen Boden existierte**:
> `TerrainData.get_height()` **clampt die Eingabekoordinaten** und setzt damit die
> Randhöhe unendlich nach außen fort. 10j behebt genau das — draußen ist kein Boden
> mehr — und macht die Mauer überflüssig. Das Verlassen der Karte wird von einem
> Fehler zu einer Spielmechanik.

## Nutzer-Festlegungen (2026-08-05)

| Thema | Entscheidung |
|---|---|
| Alle Karten | **rund** |
| Schamanin am Rand | Sie stürzt wie alle, stirbt aber **hörbar** (ihr Todesschrei), der Töter bekommt den Mana-Bonus, sie **respawnt** am Reinkarnationsplatz |
| Kartenrand | **Nackte Felskante**; Wasserfall **nur dort, wo Wasser am Rand liegt** (heute nur Insel). Erhält Spielfläche. |
| Sturz | Einheiten **und Fahrzeuge** stürzen ins All und sterben **lautlos offscreen** |

## Der eine Hebel

Das Projekt hat **keinen** Begriff von „Zelle gültig/ungültig" — die Welt *ist* das
Quadrat, und Gültigkeit == `in_bounds()`. Zwei Dinge spielen uns aber zu:

- `TerrainData.generate_island()` hat **schon** einen radialen Falloff. Die Insel
  ist bereits eine Scheibe, nur von quadratischem Wasser umgeben.
- `MapGenerator.round_mask()` und `Minimap.round_mask` existieren bereits — bisher
  **rein kosmetisch für die Minimap**, ohne Spielbedeutung.

**Der Schlüssel:** `NavGrid.update_region()` ist laut eigenem Kommentar der
**einzige** Solidity-Writer:

```gdscript
var solid: bool = _building_cells.has(cell) or not terrain.is_walkable(cell)
```

Eine Maske in `TerrainData.is_walkable()` / `is_grass()` zieht damit **automatisch**
mit: A-Stern, `walkable_map`, PathWorker-Klon, Fahrzeuggitter, Insel-Labels,
Baum-Spawns, Einheiten-Spawns, KI-Bauplatzsuche und `can_place_at`. Das ist die
„einmal statt zwanzig Mal"-Stelle.

`AStarGrid2D.region` **muss** rechteckig bleiben (Engine-Vorgabe) — die Scheibe
wird über *solid points* modelliert, nicht über die Region.

---

## Teil 1 — Die Scheibe als Datenmodell

- `TerrainData`: `in_disc(cell) -> bool` (bzw. `disc_radius`), eingezogen in
  `is_walkable()` und `is_grass()`. **Vorsicht beim Layout:** `heights` ist
  **vertex**-indiziert (`verts²`), Begehbarkeit **zell**-indiziert (`size²`) — die
  Maske gehört an die Zell-Seite, sonst gibt es Randfehler.
- **`get_height()` braucht eine Void-Variante.** Heute clampt es die Koordinaten
  und liefert draußen die Randhöhe (die Ursache des ursprünglichen Bugs). Neu:
  `has_ground(x, z) -> bool`. **Ohne das fällt niemand, weil überall Boden ist.**
- `average_height()` mittelt heute über **alle** `heights` — mit einer Void-Fläche
  würde das die Reiseflughöhe des Luftschiffs verfälschen. Nur über die Scheibe
  mitteln.
- `world_clamp_limit()` → radiale Variante `clamp_into_world(td, pos)`. Betrifft die
  **frei wandernden Effekte**, die weiterhin drinbleiben müssen: `tornado_vortex.gd`
  (2 Stellen), `supertornado.gd`, `swarm_cloud.gd`, `tornado_debris.gd` — plus die
  **handkopierte Duplikatformel** in `airship.gd`, vor der der Doc-Kommentar an
  `world_clamp_limit` ausdrücklich warnt.
- `nearest_walkable_cell()` clampt **erst** aufs Rechteck und sucht dann im Radius
  `MAX_SNAP_RADIUS = 32`. Auf einer Scheibe liegt die Ecke bis `0.2 * size` von
  Land entfernt — auf **256er-Karten schlägt das Snapping fehl** (53 Zellen > 32).
  Muss radial klemmen.
- Terrain-verformende Zauber (`raise_area`, Erdbeben, Vulkan, Ebene, Absinken)
  clampen auf das Quadrat und könnten heute **Land in den Void bauen**. Sie werden
  radial begrenzt: man kann die Welt nicht vergrößern.

## Teil 2 — Karten radial

- `MapGenerator.round_mask()` → **true für alle** (die Minimap ist damit sofort
  rund, sie kann das schon).
- **Blocker:** `_corner_anchors` setzt die Startanker von `seenland` und `plateau`
  in die Ecken — Abstand vom Zentrum `≈ 0.64 * size` bei einem Scheibenradius von
  `0.5 * size`. Diese Anker liegen **außerhalb der Scheibe**. Beide Karten brauchen
  radiale Anker (Muster: `_circle_anchors`, von `island`).
- `bergpass`: die drei Pässe bei `x ∈ {s/4, s/2, 3s/4}` liegen teils außerhalb →
  radial neu setzen.
- `island` ist praktisch fertig.
- **Rand = nackte Felskante** (Nutzerentscheidung): die Generatoren laufen bis an
  den Scheibenrand durch und brechen dort ab. Kein erzwungener Wasserring — die
  Spielfläche bleibt erhalten. Wasser am Rand entsteht nur, wo die Karte es ohnehin
  hat (Insel).

## Teil 3 — Sturz ins All

**Die Mauer aus `95b0e73` wird abgebaut:** der Clamp in `_snap_to_ground()`,
`_clamp_world_xz()`, `_bounce_off_world_edge()` und die Roll-Reflexion in
`_tick_roll`. An ihre Stelle tritt: **draußen ist kein Boden.**

- Neues Flag `_falling_into_void`, geschnitten wie das vorhandene `_drowning` — das
  hat schon genau die Infrastruktur, die wir brauchen: eigener Zustand, eigene
  Verfallskurve, Renderer zieht die Tiefe (`corpse_sink_depth()`).
- `_tick_thrown()`: `land_y = maxf(ground, SEA_LEVEL)` darf über dem Void **nicht**
  greifen — die Einheit fällt weiter. Bestehender Fail-Safe ist
  `THROWN_MAX_DURATION` (30 s), der heute mit `_snap_to_ground(); _die()` endet;
  für den Void wird daraus direkt Entfernen.
- **Lautlos ist geschenkt:** `death_sfx_key()` liefert bei leerem Key nichts, und
  `AudioManager._on_unit_died()` hat den `if key == &"": return` schon eingebaut.
  Das Void-Flag schaltet den Basis-Key auf leer; **`Shaman.death_sfx_key()`
  ignoriert das Flag** → ihr Schrei bleibt (Nutzerentscheidung).
- **Schamanin-Respawn und Mana-Bonus:** beides läuft heute schon automatisch,
  sobald sie `DEAD` ist (`reincarnation_site.gd`) bzw. über `_grant_kill_bonus()`
  (`shaman.gd`). Aufpassen: der Bonus hängt an `last_attacker`, und
  `throw_airborne()` setzt den **nicht** — er kommt vom Treffer, der sie geworfen
  hat. Genau dafür ein Test.
- **Entfernen:** unter `VOID_FALL_DEPTH` wird die Einheit entsorgt. Der Ausgang
  existiert: `corpse_expired` → `UnitManager._on_corpse_expired()` (`unregister` +
  `queue_free`). Keine Renderer-Arbeit nötig — es gibt keine Höhen-Kullung, ein
  tief fallender Körper ist einfach außer Sicht.
- **Falle:** `water_splash_active()` fragt `_is_water_at()`, das über `get_height`
  läuft. Ohne vorgeschaltete Void-Prüfung erscheint ein **Spritzring im Nichts**,
  wenn der Sturz das SEA_LEVEL-Band durchquert.
- **Wer stürzt:** nur durch Wurf, Rückstoß oder Rollen. Laufende Einheiten
  erreichen den Void nie (unbegehbar). Bodenfahrzeuge stürzen mit; **Luftschiffe
  behalten ihren Clamp** — sie werden befehligt, nicht geschleudert.
- Ein Klick in den Void erteilt **keinen Befehl** (statt wie heute stillschweigend
  auf den Rand zu klemmen, `SelectionManager._screen_to_ground`) — der Void ist
  kein Ort.

## Teil 4 — Sternenhimmel, Felskante, Wasserfall

- **Himmel:** das Environment ist ein *inline* SubResource in `scenes/main.tscn` mit
  `background_mode = 1` (flache Farbe) — es gibt **kein Sky, kein
  ProceduralSkyMaterial und keinen Nebel** im ganzen Projekt. Umstellen auf
  `BG_SKY` mit Sternenhimmel.
  **Wichtig:** `ambient_light_source = 3` (COLOR) **bleiben lassen** — ein
  Sky-Ambient über schwarzem Himmel macht die ganze Karte finster. Die Sonne
  (`DirectionalLight3D "Sun"`) bleibt als fernes Zentralgestirn.
- **Terrain-Mesh:** `_build_chunk_mesh()` cullt schon Zellen unter
  `SEA_LEVEL - SEABED_CULL_MARGIN` und nullt komplett untergetauchte Chunks.
  **Genau dieser Cull-Test ist der Ansatzpunkt:** „außerhalb der Scheibe"
  ergänzen, dann verschwindet die Geometrie ohne weitere Arbeit.
- **Wasserfläche:** heute eine quadratische `PlaneMesh` über `[0..size]` — sie würde
  über den Scheibenrand in den Void ragen und muss rund werden (Achtung: die Wellen
  sind Vertex-Displacement, die Subdivision bis 160 muss erhalten bleiben).
- **Wasserfall** (nur wo der Rand unter `SEA_LEVEL` liegt): ein **statisches,
  vertikales Band-Mesh** am Rand mit einem Shader, der die UV nach unten scrollt und
  nach unten ausfadet. Ein Draw-Call, kein `tick()`, keine Partikel.
  `shaders/water.gdshader` liefert `deep`/`crest` und `wave_at()` zum
  Weiterverwenden, damit die Oberkante an die Wellen der Fläche ankoppelt und die
  Naht nicht aufreißt. **`GPUParticles3D` gibt es im Projekt nirgends** — Partikel
  wären hier ein Fremdkörper; der Baukasten ist MultiMesh + animiertes Mesh
  (`WaterFxRenderer`, `LavaFlow`, `VolcanoZone`).
- **Kamera:** Pan-Käfig in `camera_rig.gd` rechteckig → radial, aber mit **Marge
  nach außen**, damit man die Kante frontal ansehen kann. `_clamp_to_terrain()` hält
  die Kamera per `maxf(ground, SEA_LEVEL)` über Wasser — über dem Void klebt sie
  dadurch auf Meereshöhe und braucht eine eigene Regel.
- **Minimap:** `round_mask` → true; dazu ein Kreis-Guard in `_move_camera_to()` —
  ein Klick in die transparente Ecke schickt die Kamera heute in den Void.
- **`HeightMapShape3D` bleibt zwangsläufig rechteckig.** Der Void behält damit eine
  Trefferfläche für Maus-Raycasts; deshalb muss `_screen_to_ground()` Void-Treffer
  **explizit verwerfen**.

## Neue Konstanten

```gdscript
# --- Scheibenwelt (Phase 10j) ---
## Scheibenradius als Anteil der halben Kartenkante (1.0 = einbeschrieben).
const WORLD_DISC_RADIUS_FRAC: float = 1.0
## Tiefe unter dem Meeresspiegel, ab der eine ins All gestürzte Einheit entsorgt
## wird (sie ist längst außer Sicht).
const VOID_FALL_DEPTH: float = 120.0
## Höhe des Wasserfall-Bands am Rand und Scrollgeschwindigkeit seiner UV.
const WATERFALL_HEIGHT: float = 40.0
const WATERFALL_SCROLL_SPEED: float = 1.6
```

`WORLD_EDGE_MARGIN` und `WORLD_BOUNCE_RESTITUTION` werden **entfernt** — mit ihnen
die Mauer.

## Umsetzungsschritte

1. **Teil 1** (Datenmodell) — `in_disc` + `has_ground` + Maske in `is_walkable`.
   Danach sofort die Suite: hier fallen die Karten- und Terrain-Tests auf.
2. **Teil 2** (Karten radial) — ohne das sind `seenland` und `plateau` unspielbar,
   weil ihre Startanker im Void liegen. Der größte inhaltliche Posten.
3. **Teil 3** (Sturz) — Mauer abbauen, Void-Flag, lautloser Tod, Entfernen.
4. **Teil 4** (Optik) — Himmel, Mesh-Cull, runde Wasserfläche, Wasserfall, Kamera,
   Minimap.
5. `plans/PROGRESS.md`, `CLAUDE.md` §3 (Terrain/Welt), Checkbox in
   [00_overview.md](00_overview.md), Commit/Push.

## Tests

**Zu ERSETZEN** (sie sichern die Mauer, die genau umgedreht wird) — alle in
`tests/test_combat.gd`: `test_thrown_unit_bounces_off_the_world_edge`,
`test_thrown_unit_bounces_out_of_a_world_corner`,
`test_rolling_unit_bounces_off_the_world_edge`,
`test_rolling_unit_bounces_out_of_a_world_corner`,
`test_snap_to_ground_pulls_a_unit_back_into_the_world`,
`test_knockback_cannot_shove_a_unit_out_of_the_world`, plus der Kommentarblock, der
die Mauer als „invariant of every movement path" beschreibt.

**Neu `tests/test_void_fall.gd`:**
`test_thrown_unit_past_the_rim_keeps_falling`,
`test_falling_unit_is_removed_below_the_void_depth`,
`test_void_death_is_silent` (leerer `death_sfx_key()`),
`test_shaman_void_death_keeps_her_cry`,
`test_shaman_void_death_grants_the_kill_bonus_and_respawns`,
`test_rolling_unit_can_tumble_over_the_rim`,
`test_walking_unit_never_reaches_the_void` (unbegehbar — der Regelfall),
`test_no_splash_ring_appears_in_the_void`,
`test_airship_still_cannot_leave_the_map`.

**Neu `tests/test_disc_world.gd`:**
`test_cells_outside_the_disc_are_unwalkable`,
`test_has_ground_is_false_outside_the_disc` (der Kern: draußen kein Boden),
`test_average_height_ignores_the_void`,
`test_nearest_walkable_cell_works_from_a_void_corner_on_a_256_map` (der belegte
Snapping-Fehlschlag),
`test_trees_never_spawn_outside_the_disc`,
`test_terrain_deforming_spells_cannot_extend_the_disc`,
`test_all_maps_report_round_mask`,
`test_every_map_anchor_lies_inside_the_disc_and_is_walkable` (**der Blocker-Test**
für seenland/plateau).

**Anzupassen:** `tests/test_maps.gd` (Anker-Walkability/Erreichbarkeit aller vier
Karten, `round_mask`-Erwartung, Plateau-Ecke), `tests/test_terrain.gd`
(`test_generate_island_border_under_water`), `tests/test_spells.gd`
(`world_clamp_limit`), `tests/test_stumble_roll.gd` (30-s-Wurf-Cap — er wird für den
Void-Sturz umgedeutet).

## Verifikation

Neben Suite und Ladecheck ist hier die **manuelle Prüfung** der eigentliche Test,
weil fast alles optisch ist:

- Jede der vier Karten laden: runder Rand, Sternenhimmel, Karte gut lesbar
  (Ambient!), Startbasen liegen auf Land und sind erreichbar.
- An den Rand pannen und die Kante frontal ansehen — kein Z-Fighting, kein Loch in
  der Wasserfläche, Wasserfall auf der Insel sichtbar.
- Eine Einheit mit Feuerball/Tornado über die Kante schleudern: sie fällt aus dem
  Bild und verschwindet **lautlos**.
- Dasselbe mit der Schamanin: **Todesschrei**, Mana-Bonus beim Gegner, Respawn am
  Reinkarnationsplatz.
- Klick ins Nichts: **kein** Bewegungsbefehl, kein Zauber landet dort.
- Landbrücke Richtung Rand: baut kein Land in den Void.
- `benchmark_stress` / `benchmark_earlygame`: die Scheibe macht ~21,5 % der Zellen
  dauerhaft solid — Pfadsuche und Insel-Labels sollten dadurch eher **billiger**
  werden. Wenn nicht, ist etwas an der Maske falsch.

## Risiken

1. **Spielfläche schrumpft um ~21,5 %** (Kreis in Quadrat). Kartenwerte (Baumzahl,
   Startabstände, KI-Suchradien) sind darauf nicht abgestimmt.
2. **Drei Karten brauchen echten Neuentwurf**, nicht nur eine Maske — ihre
   Startanker liegen außerhalb der Scheibe. Das ist der größte Einzelposten und der
   Grund, diese Phase nicht zu unterschätzen.
3. **`HeightMapShape3D` bleibt rechteckig** — der Void behält eine unsichtbare
   Klickfläche. Jede Stelle, die auf Raycast-Treffer vertraut, braucht die
   Void-Prüfung; wird eine vergessen, kann man ins Nichts befehlen.
4. **Die Mauer fällt weg** — damit ist die Fehlerklasse aus dem ursprünglichen
   Report wieder offen, nur mit gewollter Wirkung. Der Unterschied ist, dass es
   draußen keinen Boden mehr gibt: statt unsichtbar herumzustehen, stirbt die
   Einheit. **Sollte 10j abgebrochen werden, muss die Mauer zurück**, sonst ist der
   alte Bug wieder da.
5. **Ambient-Licht:** schwarzer Himmel + Sky-Ambient = finstere Karte. Die
   `ambient_light_source = 3`-Einstellung ist kein Detail, sondern die Bedingung
   dafür, dass die Karte lesbar bleibt.
6. **Wasserfall nur auf der Insel** (Nutzerentscheidung „nackte Felskante"). Drei
   von vier Karten sehen am Rand nüchtern aus — bewusster Tausch für Spielfläche.
   Falls das optisch enttäuscht, ist ein Wasserring pro Karte die Rückfallebene.

## Definition of Done

- [ ] Alle vier Karten rund, Startanker innerhalb der Scheibe und erreichbar
- [ ] Außerhalb der Scheibe gibt es **keinen Boden** (`has_ground` false) und keine
      begehbare Zelle
- [ ] Sternenhimmel steht, Karte bleibt gut lesbar
- [ ] Geschleuderte Einheiten und Bodenfahrzeuge stürzen ins All und sterben
      lautlos; die Schamanin hörbar, mit Mana-Bonus und Respawn
- [ ] Wasserfall am Rand, wo Wasser liegt; keine Wasserfläche über dem Void
- [ ] Kein Befehl und kein Zauber landet im Void
- [ ] Terrain-Zauber können die Scheibe nicht vergrößern
- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung durch den Nutzer bestanden
- [ ] PROGRESS.md ergänzt, Checkbox in [00_overview.md](00_overview.md), Commit/Push
