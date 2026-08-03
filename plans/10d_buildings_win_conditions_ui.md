# Phase 10d — Siegbedingungen, Abriss, Bauverfall, Erreichbarkeit, UI-Bugs

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Sechs zusammengehörige Gebäude-/Regel-Themen:

1. **Siegbedingungen überarbeitet.** Der Schamanenkreis wird **unangreifbar**
   und zerstört sich **selbst**, sobald der Stamm außer der Schamanin keine
   Anhänger mehr hat. Ist danach auch die Schamanin gefallen, werden **alle**
   restlichen Fahrzeuge und Gebäude des Stammes zerstört, der Spieler scheidet
   aus und kann keine Aktionen mehr durchführen.
2. **Gebäude abreißbar** per `Entf`.
3. **Bauverfall:** unfertige Gebäude ohne Baufortschritt verfallen nach 2 min.
4. **Keine Bauarbeiter für unerreichbare Baustellen.**
5. **Bauauftrag mit Selektion:** beim Platzieren selektierte Braves bauen mit.
6. **UI-Bugs:** Angriffsbefehl bleibt nach Linksklick armiert; bekehrte
   Einheiten zählen weiter in der Selektion.

## Bestandsaufnahme (vor Umsetzung verifiziert)

- `GameState.is_tribe_defeated` (:106): besiegt = keine lebende Einheit **und**
  kein nutzbares `Hut`/`ReincarnationSite`. `check_defeats` (:89) läuft im
  1-s-Takt, `_evaluate_match_end` (:119) beendet die Partie.
- `ReincarnationSite.is_assailable_by_units()` (:37) blockt nur Nahkampf und
  Feuerkrieger. **Zauber, Katapulte, Lava und Terrainverformung umgehen das
  vollständig** (dokumentiert in `building.gd:511-513`).
- **Es gibt heute keinerlei Abriss-/Abbruch-Funktion** — weder in `Building`,
  noch in `TribeCommands`, noch in der UI.
- **Es gibt keinen Verfall** einer Baustelle: nur `wood_stalled` (30-s-Recheck,
  `building.gd:1177`) und der Ausstieg eines Braves nach
  `SEEK_FAIL_QUIT_STREAK 6` (`brave.gd:1203`).
- `BuildingManager._recruit_workers` (:104) zieht **ohne jede
  Erreichbarkeitsprüfung** idle Braves im Umkreis von 30 m ein.
  `TribeCommands.can_place_at` (:69) prüft ebenfalls keine Erreichbarkeit (nur
  die KI hat `_plot_reachable` :966).
- `Building.delivery_point()` → `edge_spawn_position()` (:264) liefert
  **garantiert eine begehbare Zelle** — damit ist eine O(1)-Inselprüfung exakt,
  ohne A*.
- `Building._update_construction_visual()` (:1514) leitet beide Darstellungen
  (Stufentextur bzw. Y-Skalierung) aus `build_progress` ab → Abriss kann
  einfach `build_progress` rückwärts laufen lassen.
- `Brave.order_build` (:226) ruft `_interrupt_tasks()` **vor** `building.join()`
  — ein an einer vollen Baustelle abgewiesener Brave hat sein Holz schon
  fallen gelassen (Bestandswart).
- `SelectionManager`: `attack_arm_active` (:58) wird nur vom **Rechtsklick**
  konsumiert (:159) und von Esc gelöscht (:190) — ein Linksklick lässt den
  roten „Angriff"-Cursor stehen. `_prune_selection` (:591) läuft **nur** auf
  Befehlspfaden, nicht pro Frame; `cursor_count_label.gd` liest `selected`
  jeden Frame.
- `Unit.convert_to_tribe` (unit.gd:2100) setzt `selected = false` direkt und
  feuert `converted`; `UnitManager._on_unit_converted` (:1334) hängt bereits
  daran — idealer Aufhängepunkt.

## Dokumentierte Auslegungen (Nutzer-Festlegungen)

- **Schamanenkreis: komplett unverwundbar** — kein Schaden von Einheiten,
  Zaubern, Katapulten, Lava oder Terrainverformung. Er verschwindet
  ausschließlich über die neue Selbstzerstörung.
- **Abriss-Erstattung: ohne Baustufe 100 %, ab Baustufe 75 %.**
- **„Keine Baustufe erreicht"** = Baustelle mit `build_progress == 0`. Fertige
  Gebäude gelten immer als „mit Baustufe".
- **„Ausgeschieden"** heißt: keine Befehle mehr (UI und KI), keine Produktion,
  keine Zauber. Der Stamm bleibt als Datenobjekt bestehen, damit die
  Siegauswertung und die Statistik konsistent bleiben.

### Nachgetragene Festlegungen (2026-08-04, vor der Umsetzung geklärt)

- **Niederlage: die Hütten-Klausel entfällt.** Besiegt = keine lebende Einheit
  mehr. Begründung: eine Hütte produziert seit 7i nur **mit** Besatzung, und
  Besatzung sind selbst Einheiten — ein Stamm mit 0 Einheiten konnte nie mehr
  etwas erzeugen, wäre aber mit der alten Regel nie ausgeschieden und hätte die
  ganze Siegkette blockiert.
- **Abriss-Anzeige:** kein neuer 3D-Text. Das Projekt enthält **kein**
  `Label3D`; der vorhandene Fortschrittsbalken über dem Gebäude zeigt den
  Abriss und füllt dabei **rot** statt gold.
- **Abriss ist endgültig** — kein `cancel_demolish()`.
- **Sofort-Abriss bleibt bei `build_progress == 0`.** Damit fällt auch die
  *fertig planierte* Baustelle darunter (der Fortschritt steigt erst ab
  `foundation_done`): „platzieren → planieren lassen → abreißen" ist bewusst
  ein billiges Geländewerkzeug.

## Korrigierte Zeilenangaben (Stand 2026-08-04)

Die Bestandsaufnahme oben war teils veraltet:

| oben genannt | tatsächlich |
|---|---|
| `brave.gd` `order_build` :226, `_job_active` :452, `_choose_job_task` :462, `_tick_construct` :752, `SEEK_FAIL_QUIT_STREAK` :1203 | :220 / :436 / :446 / :736 / Konstante :52, Auswertung :1183 |
| `building.gd` `_update_construction_visual` :1514 | :1545 |
| `unit.gd` `convert_to_tribe` :2100 | :2440 |
| `ai_controller.gd` `_plot_reachable` :966 | :937 |
| `reincarnation_site.gd` `is_assailable_by_units` :37 | :34 |

Außerdem sachlich abweichend: **es gibt keinen Stammes-Holzvorrat**
(`tribe.gd:5-6`) — jede Erstattung wird als Bodenstapel über
`WoodPileManager.deposit()` gespawnt; und ein einzelner `_tribe_active(tribe)`
-Guard reicht nicht, weil 17 der 18 mutierenden `TribeCommands`-Methoden keinen
`Tribe` bekommen (es gibt daher zusätzlich `_unit_active(unit)`).

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Unverwundbarer Kreis** | `scripts/buildings/reincarnation_site.gd`, `scripts/spells/spell_context.gd` | `take_damage()`, `apply_destruction_stages()`, `add_lava_contact()` als No-op überschreiben; `is_assailable_by_units()` bleibt `false`. Ausnahme in `SpellContext.check_terrain_integrity` (:50) — der Kreis wird weder durch Fundamentbruch noch durch Flutung zerstört |
| **Selbstzerstörung** | `scripts/buildings/reincarnation_site.gd` | In `_tick_active` (:48): hat der Stamm außer der Schamanin **keine** lebende Einheit mehr → `destroy()` (normales Versinken). Danach ist kein Respawn mehr möglich |
| **Ausscheiden** | `scripts/core/tribe.gd`, `scripts/core/game_state.gd` | Neue Flagge `Tribe.eliminated: bool` + `Tribe.eliminate()` (zerstört alle restlichen Gebäude und Fahrzeuge, leert Zauberladungen). `GameState.check_defeats` ruft `eliminate()` genau einmal beim Übergang auf „besiegt". `is_tribe_defeated` bleibt inhaltlich, bekommt aber `tribe.eliminated` als Kurzschluss |
| **Aktionssperre** | `scripts/core/tribe_commands.gd`, `scripts/ai/ai_controller.gd`, `scripts/ui/selection_manager.gd` | Jede mutierende Methode in `TribeCommands` steigt bei `tribe.eliminated` früh aus (zentraler Guard-Helfer `_tribe_active(tribe)`); `AIController.tick_ai` (:171) steigt aus; die Spieler-UI verweigert Selektion/Befehle |
| **Abriss (Datenebene)** | `scripts/buildings/building.gd` | Felder `demolishing`, `_demolish_start_progress`, `_demolish_refund_total`, `_demolish_refund_paid`. API: `has_build_stage()`, `has_worker_room()`, `demolish_refund_total()`, `begin_demolish() -> bool` (true = sofort abgerissen), `work_demolish(amount) -> bool`, `_pay_demolish_refund()`, `_finish_demolish()`, optional `cancel_demolish()`. `build_progress` läuft rückwärts, `_update_construction_visual()` zeigt es automatisch |
| **Abriss (Gates)** | `scripts/buildings/building.gd` | `is_usable()` → `... and not demolishing`; `tick()` überspringt `_tick_active`/`_tick_repair_absorb` beim Abriss; **kritisch:** `_tick_construction` überspringt `_absorb_piles()` beim Abriss, sonst frisst die Baustelle ihre eigene Erstattung; `_on_disabled()` wirft Besatzung/Trainees/Insassen beim Start des Abrisses raus; Overlay zeigt „Abriss" |
| **Abriss (Braves)** | `scripts/units/brave.gd` | Neue Task `DEMOLISH`, `order_demolish(building)`, `_tick_demolish(delta)` (Spiegel von `_tick_construct` :752 mit `BUILD_RATE * DEMOLISH_RATE_FACTOR`); `_job_active()` (:452) um `job.demolishing` erweitern; `_choose_job_task()` (:462) verzweigt **vor** dem Reparaturzweig; laufende Fremd-Teilaufgaben werden beim Start des Abrisses beendet. Die Animation stimmt bereits (`State.BUILD` + `_working` → `attack`) |
| **Abriss (API/Hotkey)** | `scripts/core/tribe_commands.gd`, `scripts/ui/selection_manager.gd`, `project.godot` | `demolish_building(tribe, building) -> bool`, `order_demolish(units, building) -> int`; neue Input-Action `demolish_building` = `Entf` (physical keycode 4194312); Tastendruck wirkt auf **alle** selektierten eigenen Gebäude |
| **Bauverfall** | `scripts/buildings/building.gd` | Fortschritts-Signatur `Vector3(build_progress, wood_delivered, offene Flatten-Zellen)`; ändert sie sich nicht für `CONSTRUCTION_STALL_TIMEOUT`, dann `_decay_stalled_site()` → Erstattung + `destroy()` |
| **Erreichbarkeit** | `scripts/buildings/building.gd` | `approach_island() -> int` (Insel-Label der garantiert begehbaren Anlaufstelle, Cache gegen `NavGrid.change_version`; -1 = keine Anlaufstelle) und `worker_can_reach(from) -> bool` (O(1); bei `nav_grid == null` freizügig, damit Headless-Tests laufen) |
| **Erreichbarkeit (Gates)** | `scripts/core/building_manager.gd`, `scripts/core/tribe_commands.gd`, `scripts/units/brave.gd` | `_recruit_workers` überspringt Baustellen ohne Anlaufstelle und Braves auf anderer Insel; `order_build`/`order_repair`/`order_demolish` filtern gleich, geben die Zahl der tatsächlich zugewiesenen Braves zurück und schicken Überzählige nur zum Bauplatz; `Brave._tick_job` prüft 1×/s und lässt bei Unerreichbarkeit das Holz fallen statt hängen zu bleiben. Zusätzlich der Join-Reihenfolge-Wart aus der Bestandsaufnahme |
| **Bau mit Selektion** | `scripts/ui/build_menu.gd`, `scripts/ui/selection_manager.gd` | `SelectionManager.selected_braves()`; `BuildMenu` reicht sie nach erfolgreicher Platzierung an `TribeCommands.order_build` weiter (lange Wege sind ausdrücklich erlaubt) |
| **UI-Bug a** | `scripts/ui/selection_manager.gd` | `cancel_armed_modes()` (löscht `attack_arm_active`, `unload_arm_active`, Zustände + `queue_redraw()`); Aufruf bei **Linksklick**, bei Esc und beim Konsumieren des Rechtsklicks |
| **UI-Bug b** | `scripts/core/events.gd`, `scripts/core/unit_manager.gd`, `scripts/ui/selection_manager.gd` | Neues Signal `unit_converted(unit)`, gefeuert aus `UnitManager._on_unit_converted`; der SelectionManager entfernt die Einheit sofort (O(1) pro Bekehrung, **kein** Pro-Frame-Pruning) |
| **Tests** | `tests/test_demolition.gd`, `tests/test_construction_decay.gd` (neu), `tests/test_economy.gd`, `tests/test_ui_logic.gd`, `tests/test_ai.gd`, `tests/test_shaman_respawn.gd` | siehe unten |

## Neue Balance-Konstanten

```gdscript
# --- Abriss & Bauverfall ---
## Kein Baufortschritt erreicht -> volles Holz zurück.
const DEMOLISH_REFUND_UNBUILT: float = 1.0
## Ab Baustufe 1 (und bei fertigen Gebäuden): drei Viertel zurück.
const DEMOLISH_REFUND_BUILT: float = 0.75
## Abrissrate als Faktor auf Brave.BUILD_RATE (Vorgabe: gleiche Rate).
const DEMOLISH_RATE_FACTOR: float = 1.0
## Sekunden ohne Baufortschritt, nach denen eine Baustelle verfällt.
const CONSTRUCTION_STALL_TIMEOUT: float = 120.0
const CONSTRUCTION_STALL_REFUND: float = 1.0
```

## Umsetzungsschritte

1. **Grundlagen:** Balance-Konstanten, `Building.approach_island/
   worker_can_reach/_refund_wood/has_worker_room`, `Events.unit_converted`.
2. **UI-Bugfixes** (a + b) — klein, unabhängig, sofort prüfbar.
3. **Erreichbarkeits-Gates** + Join-Reihenfolge-Wart in `Brave`.
4. **Bauverfall** (braucht `_refund_wood`).
5. **Abriss** (braucht `_refund_wood` und die Gates).
6. **Bau mit Selektion** (braucht `order_build -> int`).
7. **Siegbedingungen** (Kreis unverwundbar → Selbstzerstörung → Ausscheiden →
   Aktionssperre).
8. Verifikation, PROGRESS.md, Commit/Push.

## Tests

**Neu `tests/test_demolition.gd`:**
`test_demolish_unbuilt_site_is_instant_and_refunds_all`,
`test_demolish_after_build_stage_needs_workers`,
`test_demolish_refund_is_75_percent`,
`test_demolish_pays_refund_progressively`,
`test_demolished_building_frees_nav_footprint`,
`test_demolishing_site_does_not_reabsorb_its_refund`,
`test_demolishing_building_is_unusable_and_ejects_occupants`,
`test_recruiter_drafts_braves_for_demolition`,
`test_demolish_rejects_foreign_building`,
`test_demolish_rejects_reincarnation_site`.

**Neu `tests/test_construction_decay.gd`:**
`test_stalled_site_decays_after_timeout`,
`test_flatten_progress_resets_the_decay_timer`,
`test_wood_delivery_resets_the_decay_timer`,
`test_decayed_site_refunds_delivered_wood_as_piles`,
`test_working_site_never_decays`.

**Erweiterung `tests/test_economy.gd`:**
`test_unreachable_site_gets_no_workers`,
`test_order_build_skips_unreachable_braves`,
`test_order_build_moves_surplus_braves_to_the_plot`,
`test_worker_drops_wood_when_site_becomes_unreachable`,
`test_approach_island_cache_invalidates_on_navgrid_change`,
`test_refused_worker_keeps_its_carried_wood`.

**Erweiterung `tests/test_ui_logic.gd`** (reiner Zustand, kein Viewport):
`test_cancel_armed_modes_clears_attack`,
`test_left_click_cancels_armed_attack`,
`test_converted_unit_leaves_selection`,
`test_selected_braves_filters_dead_and_foreign`.

**Erweiterung `tests/test_ai.gd` / `tests/test_shaman_respawn.gd`
(Siegbedingungen):**
`test_reincarnation_site_ignores_spell_damage`,
`test_reincarnation_site_ignores_lava_and_catapult`,
`test_reincarnation_site_survives_terrain_flooding`,
`test_site_self_destructs_without_followers`,
`test_site_survives_while_one_brave_lives`,
`test_last_shaman_death_eliminates_tribe_and_razes_everything`,
`test_eliminated_tribe_rejects_all_commands`,
`test_eliminated_ai_stops_ticking`.

## Manuelle Prüfung

- Schamanenkreis mit Blitz, Vulkan, Katapult und Erdbeben beschießen → er
  nimmt keinerlei Schaden.
- Alle Anhänger eines Stammes töten, Schamanin am Leben lassen → der Kreis
  versinkt; danach die Schamanin töten → alle restlichen Gebäude und Fahrzeuge
  verschwinden, der Stamm ist raus.
- Baustelle ohne Fortschritt mit `Entf` abreißen → sofort weg, volles Holz
  liegt am Platz.
- Halbfertiges und fertiges Gebäude abreißen → Braves arbeiten sichtbar daran,
  Holz erscheint portionsweise, Gebäude schrumpft/verliert Stufen.
- Gebäude auf eine unerreichbare Insel setzen → **keine** Braves laufen los,
  nach 2 min verfällt die Baustelle und das Holz liegt am Platz.
- Braves selektieren, Gebäude platzieren → sie laufen von selbst hin.
- Angriffsbefehl mit `F` armieren, dann links klicken → roter Cursor
  verschwindet sofort.
- Eigene Einheiten selektieren und bekehren lassen → die Anzahl am Cursor
  fällt sofort.

## Risiken

1. **Wieder-Aufsaugen der Erstattung:** ohne den `_absorb_piles`-Guard frisst
   eine abzureißende Baustelle ihr eigenes Holz alle 0,5 s. Tragende Zeile.
2. **`Building.destroy()` setzt `under_construction = false`** — jede
   Erstattung muss **vor** `destroy()` laufen.
3. **Insel-Flutfüllungen:** die neuen `worker_can_reach`-Aufrufer können
   `NavGrid._ensure_islands()` häufiger auslösen. Hart gedeckelt auf
   1 Füllung/s, aber auf einer 256²-Karte sind das ~65k Zellen — vor/nachher
   `dbg_island_fills`/`dbg_island_us` in `tests/benchmark_earlygame.gd`
   vergleichen.
4. **Sofortiger Wohnraumverlust** beim Abriss einer bemannten Hütte
   (`is_usable()` false → Kapazität 0). Bevölkerung über Kapazität blockiert nur
   neue Spawns, tötet niemanden — gegenprüfen, dass `Tribe._emit_population`
   das verkraftet.
5. **Verfall und KI-Wiederaufbau:** eine verfallende KI-Baustelle löst
   `Events.building_destroyed` und damit den eigenen 15-Tick-Wiederaufbau-
   Cooldown aus. Gewollte Drosselung, aber in holzarmen Starts beobachten.
6. **Ausscheiden ist irreversibel** — die Sperre muss wirklich alle Pfade
   abdecken (UI, KI, Gebäudeproduktion, Zauberladungen), sonst geistert ein
   toter Stamm weiter.

## Definition of Done

- [x] Testsuite grün (**3273/3273**, dreimal identisch), `--headless --quit` fehlerfrei
- [x] `benchmark_earlygame` ohne Insel-Flutfüllungs-Regress (10/446 ms → 10/439 ms)
- [ ] Manuelle Prüfung durch den Nutzer bestanden
- [x] PROGRESS.md ergänzt, Checkbox 10d in [00_overview.md](00_overview.md) abgehakt
- [x] Commit/Push
