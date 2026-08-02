# Phase 10b — Zauberformeln, Effektsounds, Sound-Prioritäten

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Zwei zusammenhängende Sound-Themen:

1. **Zauberformel + Effektsound getrennt.** Jeder Zauber bekommt einen eigenen
   Sprech-Sound der Schamanin, der **beim Beginn des Cast-Vorgangs** losgeht
   (nicht bei der Auslösung). Der Sound des Zaubers selbst (z. B. Donner beim
   Blitz) kommt erst, wenn der Effekt **tatsächlich eintritt**. Die Zauberzeit
   wird auf **1,0 s für alle Zauber** vereinheitlicht und ist in `Balance`
   einstellbar.
2. **Prioritätensystem.** Wenn zu viele Sounds gleichzeitig laufen, gewinnen
   wichtige: **Prio 1** = Zauberformeln + Schamanentod, **Prio 2** = Tode von
   Belagerungswaffen und Zeppelinen, **Prio 3** = alles Übrige.

## Bestandsaufnahme (vor Umsetzung verifiziert)

- `scripts/core/audio_manager.gd` (Autoload): Pool aus 8 `AudioStreamPlayer3D`
  (SFX) + 4 `AudioStreamPlayer` (UI), Auflösung der Dateien per Konvention
  über `AssetLibrary` (`assets/audio/sfx/<name>.ogg`), fehlende Datei = Stille.
- **Bug im Bestand:** `play_sfx` (:90-93) nimmt einen blinden Round-Robin-Index
  und verwirft den Sound, wenn **dieser eine** Slot noch spielt — auch wenn 7
  der 8 Slots frei sind. Gleiches Muster in `play_ui` (:107) und
  `combat_audio.gd:62`. Der neue Allokator behebt das nebenbei.
- Zaubersound heute: `Shaman._emit_spell_cast()` (shaman.gd:175) →
  `Events.spell_cast` → `AudioManager._on_spell_cast` (:254) →
  `play_sfx("spell_<id>", target_pos)`. Also **bei der Auslösung**, am **Ziel**,
  ohne jeden Einschlags-Hook. `_on_spell_cast` ist der einzige Abnehmer des
  Signals.
- Cast-Ablauf: `TribeCommands.cast_spell` (:272) → `Shaman.order_cast` (:57) →
  `_tick_cast` (:139) mit Wind-up-Start bei :157-159. **Zwei Sofort-Pfade ohne
  Wind-up:** Wachturm-Besatzung (:71-78) und Luftschiff-Deck (:79-91).
- `Balance.SHAMAN_CAST_TIME = 0.6` (:60), aliasiert als `Shaman.CAST_TIME`.
- 11 Zauber (`Spell.create_default_set()` spell.gd:47). Effekte laufen als
  Projektile (`UnitManager.register_projectile` :708, Tick :716) — **außerhalb
  des Szenenbaums in Tests**.
- Es existieren **keine Audiodateien** (nur `.gitkeep`); alles ist stumm außer
  `CombatAudio` mit seinem prozeduralen Synthesizer.
- Cast-Tests sind dauerunabhängig (`MAX_TICKS 400` = 40 s) — die Erhöhung auf
  1,0 s bricht keinen bestehenden Test.

## Dokumentierte Auslegungen

- **Namenskonvention ohne Asset-Umbenennungen:** `spell_<id>.ogg` bleibt, wird
  aber von „bei der Auslösung" auf „wenn der Effekt eintritt" umdefiniert. Neu
  hinzu kommt die Familie `spell_voice_<id>.ogg`.
- **Eigentümer-Regel:** *Die Entität, die den Effekt erzeugt, spielt seinen
  Sound.* Nur die Zauberformel kommt von der Schamanin. Damit bleibt das System
  wartbar, wenn Zauber später umgebaut werden.
- **Sofort-Casts (Wachturm/Luftschiff) spielen die Formel trotzdem** — sie wird
  gesprochen, auch wenn Formel und Effekt dort zusammenfallen. Das
  Prioritätssystem garantiert, dass die Formel den Slot bekommt.
- **`CombatAudio` bleibt ein eigenes Subsystem** (eigener Pool, eigener
  Synthesizer, höchste Ereignisdichte). Es nutzt aber **denselben Allokator**,
  damit auch dort keine Sounds mehr grundlos verworfen werden. Kampftreffer
  konkurrieren nicht um die Slots der Zauberformeln.

## Deliverables

| Bereich | Datei(en) | Inhalt |
|---|---|---|
| **Allokator** | `scripts/core/audio_manager.gd` | Konstanten `PRIO_AUTO 0`, `PRIO_CRITICAL 1`, `PRIO_IMPORTANT 2`, `PRIO_NORMAL 3`, `STEAL_SAME_PRIO_MS 250`. Neue Slot-Zustandsarrays `_sfx_prio: PackedInt32Array`, `_sfx_start_ms: PackedInt64Array`. **Reine statische Funktion** `pick_slot(playing, prios, starts, want_prio, cursor, now_ms) -> int` (Array-basiert, damit ohne Autoload/Szenenbaum/`AudioServer` testbar) |
| **Prio-Ableitung** | `scripts/core/audio_manager.gd` | `static default_priority(name) -> int`: `spell_voice_*` und `shaman_death` → 1; `airship_death`, `siege_death_burn`, `siege_death_burst` → 2; Rest → 3. Die Death-Keys sind die tatsächlichen Rückgaben von `death_sfx_key()` (`airship.gd:106`, `crewed_vehicle.gd:115`) — beim Umsetzen gegenprüfen |
| **API** | `scripts/core/audio_manager.gd` | `play_sfx(name, pos, min_interval_ms = 0, priority = PRIO_AUTO)`. Throttle-Zeitstempel wird **erst gesetzt, wenn der Sound wirklich startet** (heute verbrennt ein verworfener Sound das Zeitfenster). `play_ui` nutzt denselben Allokator mit Prio 3 |
| **Kampfsound** | `scripts/core/combat_audio.gd` | `_on_combat_hit` (:53) nutzt `AudioManager.pick_slot(...)` über die eigenen 12 Slots mit `want_prio = PRIO_NORMAL` und ohne Same-Prio-Steal. Verhalten sonst identisch. Header-Kommentar mit der Begründung, warum CombatAudio getrennt bleibt |
| **Signal** | `scripts/core/events.gd` | Neu: `signal spell_cast_started(spell_id: StringName, pos: Vector3)`. `spell_cast` (Release) bleibt bestehen, verliert aber seinen Sound-Abnehmer |
| **Zauberformel** | `scripts/units/shaman.gd` | Feld `_voice_played` (Reset in `order_cast` :57 und `_cancel_cast` :114); `_emit_spell_voice(spell)`; Aufruf in `_tick_cast` (:157-159) beim Wind-up-Start sowie in beiden Sofort-Pfaden (:71-78, :79-91) **vor** `spell.cast(...)`. Die Latch-Flagge verhindert Stottern, wenn die Schamanin an der Reichweitenkante pendelt (`_casting` kippt dort pro Tick) |
| **Helfer** | `scripts/core/spell_audio.gd` (neu, `class_name SpellAudio`) | `static voice_name(id)`, `static effect_name(id)`, `static play_voice(from, id)`, `static play_effect(from, id, pos, min_interval_ms = 0, suffix = &"")`. **Kapselt den `is_inside_tree()`-Guard** — `get_node_or_null("/root/...")` außerhalb des Baums ist in Godot ein Fehler, und alle Zauber-Entitäten laufen in Tests außerhalb des Baums |
| **Cast-Zeit** | `scripts/core/balance.gd` | `SHAMAN_CAST_TIME: 0.6 → 1.0` mit Kommentar (Wind-up = Zauberformel) |
| **Effekt-Hooks** | diverse Zauberdateien | siehe Tabelle unten |
| **Doku** | `assets/README.md`, `docs/game_mechanics.md`, `CLAUDE.md` §6 | Neue `spell_voice_<id>.ogg`-Tabelle (11 Ids), Umdefinition von `spell_<id>.ogg`, neue Zusatznamen, Prio-Stufen; Cast-Zeit 1,0 s |
| **Tests** | `tests/test_audio_priority.gd` (neu), `tests/test_spells.gd` | siehe unten |

### Effekt-Sound-Hooks (vollständig)

| Zauber | Sound | Ort |
|---|---|---|
| Feuerball | `spell_fireball` | `spells/fireball_bolt.gd::_explode()` (:54), am Einschlagpunkt, `min_interval_ms = 60` (Feuerregen feuert 12 Bolts durch dieselbe Klasse) |
| Feuerregen | `spell_firestorm` + die 12 Bolt-Einschläge | `spells/firestorm.gd::FirestormShower._launch_bolt` (:73), einmalig beim ersten Bolt |
| Blitz | `spell_lightning` | `spells/lightning.gd::_spawn_beam(at, ctx)` (:143) — für **jeden** Ausgang (Gebäude, Luftschiff, Fahrzeug, Einheit, nur Brennbares) |
| Tornado | `spell_tornado` einmalig + `AudioManager.start_loop(&"spell_tornado_loop", vortex)` | `spells/tornado.gd` / `tornado_vortex.gd`. Loop-Aufräumen ist automatisch: `AudioManager._process` (:202) gibt den Slot frei, sobald der Besitzer freigegeben wird |
| Supertornado | `spell_supertornado` + Loop **nur für den Haupttrichter** | `spells/supertornado.gd` — keine Loops für die 2 Satelliten (Loop-Cap ist 4 pro Name) |
| Schwarm | `spell_swarm` + `spell_swarm_loop` | `spells/swarm.gd` / `swarm_cloud.gd` |
| Landbrücke, Ebene, Absinken, Erdbeben, Vulkan | `spell_<id>` | **gemeinsam:** `TerrainMorph` bekommt `var sfx_id: StringName = &""` und spielt beim **ersten** Schritt in `tick()`. Jeder Zauber setzt `morph.sfx_id = id` nach `morph.setup(...)` (je eine Zeile) |
| Vulkanausbruch | `spell_volcano_erupt` | `spells/volcano_zone.gd::_spawn_surge` (:75) — einer pro Ausbruch |
| Lava (alle Quellen) | `lava_start`, `min_interval_ms = 250` | `LavaSurge._ready` / `LavaFlow._ready` |

## Umsetzungsschritte

1. **Allokator + Prio-Ableitung + `test_audio_priority.gd`.** Keine
   Spielmechanik-Kopplung, sofort verifizierbar.
2. **`CombatAudio`** auf den gemeinsamen Allokator umstellen.
3. **`SpellAudio` + `Events.spell_cast_started` + Shaman-Anbindung +
   `SHAMAN_CAST_TIME 1.0`**; `_on_spell_cast` im AudioManager entfernen.
   Danach `--headless --import` (neue Datei mit `class_name`).
4. **Effekt-Hooks** gemäß Tabelle, Zauber für Zauber.
5. Doku, Verifikation, PROGRESS.md, Commit/Push.

## Tests

**Neu `tests/test_audio_priority.gd`** (rein statisch, ohne Autoloads):

- `test_pick_slot_uses_any_free_slot` — Cursor zeigt auf einen belegten Slot,
  Slot 5 ist frei → 5, nicht -1. *(Regressionsschutz gegen den Bestandsbug.)*
- `test_prio1_steals_oldest_prio3` — voller Pool, alle Prio 3 mit gestaffelten
  Startzeiten → ältester Index.
- `test_prio3_never_evicts_prio1_or_2` — voller Pool aus Prio 1/2, Wunsch 3 → -1.
- `test_prio2_steals_only_prio3` — gemischter Pool → einer der Prio-3-Slots,
  der ältere.
- `test_equal_prio3_full_pool_drops` — Massenschlacht bleibt gedrosselt.
- `test_same_prio_steal_needs_age` — voller Prio-1-Pool: junge Opfer → -1,
  Opfer älter als `STEAL_SAME_PRIO_MS` → dessen Index.
- `test_default_priority_mapping` — `spell_voice_fireball` 1, `shaman_death` 1,
  `airship_death` 2, `siege_death_burst` 2, `unit_death` 3, `spell_lightning` 3.

**Erweiterungen `tests/test_spells.gd`:**

- `test_cast_time_is_one_second` — `Balance.SHAMAN_CAST_TIME == 1.0`; Schamanin
  in Reichweite, 9 × `tick(0.1)` → nicht ausgelöst, ein Tick später → ausgelöst.
- `test_spell_voice_emitted_at_windup_start` — nach dem ersten Tick in
  Reichweite ist `_voice_played` gesetzt, während der Zauber noch nicht
  ausgelöst hat.
- `test_spell_voice_not_repeated_at_range_edge` — Zähler bleibt bei 1, auch
  wenn `_casting` mehrfach kippt.
- `test_instant_tower_cast_emits_voice` — Wachturm-Setup aus
  `tests/test_watchtower.gd:298`: `order_cast` liefert true, Formel gespielt,
  Zauber im selben Aufruf ausgelöst.
- `test_spell_audio_names` — `SpellAudio.voice_name(&"fireball")` /
  `effect_name(&"lightning")`.

## Manuelle Prüfung

*(Nur eingeschränkt möglich, solange keine Audiodateien existieren.)* Prüfbar
ist die Verdrahtung über Debug-Ausgaben oder eingelegte Testdateien:

- Zauber wirken → Formel startet sofort beim Cast-Beginn (Schamanin steht noch,
  Cast-Animation läuft), Effektsound erst beim Einschlag/Ausbruch.
- Massenschlacht + Zauber → die Formel ist hörbar, wird nicht von Kampftreffern
  verdrängt.
- Cast-Zeit fühlt sich mit 1,0 s spürbar, aber nicht zäh an.

## Risiken

1. **Neue `class_name`-Datei (`SpellAudio`)** ist ohne `--headless --import`
   unsichtbar → „Identifier not declared".
2. **`get_node_or_null("/root/...")` außerhalb des Szenenbaums ist ein Fehler**,
   nicht `null`. Alle Effekt-Hooks laufen in Tests außerhalb des Baums — der
   Guard in `SpellAudio` ist deshalb Pflicht und darf nicht umgangen werden.
3. **`Events`-Verbindung** muss in `AudioManager._ready()` (:65-71) ergänzt
   werden, sonst bleibt die Formel stumm.
4. **Throttle-Semantik ändert sich** (Zeitstempel erst beim echten Start) —
   gewollt, aber es macht Sounds insgesamt etwas häufiger hörbar.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Doku (assets/README.md, docs/game_mechanics.md, CLAUDE.md §6) aktualisiert
- [ ] PROGRESS.md ergänzt, Checkbox 10b in [00_overview.md](00_overview.md) abgehakt
- [ ] Commit/Push
