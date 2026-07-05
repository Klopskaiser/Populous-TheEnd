# Phase 5 — Schamanin, Reinkarnation & alle 5 Zauber

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Das Magiesystem ist komplett: Schamanin (genau eine pro Stamm, respawnt am
Reinkarnationsplatz), `Spell`-Framework mit Manakosten/Cooldown, alle 5 Zauber aus
CLAUDE.md §6 — inklusive Landbridge mit **Laufzeit-Terrainverformung** (der
Architektur-Härtetest: `raise_area` → Chunk-Rebuild → Kollisions-Update →
NavGrid-Update). Deutsche Zauberleiste mit Hotkeys 1–5.

## Voraussetzungen

Phasen 1–4: TerrainData (`raise_area`), Terrain (`apply_deformation`), NavGrid
(`update_region`), Unit-States (PANIC, THROWN, CAST), Kampfsystem, Building
(HP/Zerstörung), TribeCommands, ReincarnationSite (Platzhalter aus Phase 3).

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/units/shaman.gd` + `scenes/units/shaman.tscn` | `class_name Shaman extends Unit`. Genau 1 pro Tribe (`tribe.shaman`), Cast-Animation, eigenes Sprite. Castet den vom Spieler gewählten Zauber auf Zielposition (läuft ggf. in Cast-Reichweite). Tod → `Events.unit_died` → ReincarnationSite startet Respawn-Timer |
| `scripts/buildings/reincarnation_site.gd` (erweitert) | Respawn-Logik in `tick`: Schamanin tot → `respawn_timer` runterzählen → neue Shaman-Instanz am Platz spawnen, `tribe.shaman` neu setzen. Kein Respawn, solange Schamanin lebt. Ohne Reinkarnationsplatz kein Respawn (Verlustrisiko) |
| `scripts/spells/spell.gd` | `class_name Spell extends RefCounted`. `id: StringName`, `display_name_de: String`, `mana_cost: float`, `cooldown: float`, `cooldown_remaining` (per `tick(delta)`), `execute(tribe: Tribe, target: Vector3, ctx) -> bool`. `ctx` = Zugriff auf TerrainData/Terrain/NavGrid/UnitManager/BuildingManager (Injektion → headless testbar). `TribeCommands.cast_spell(tribe, spell_id, target)` prüft Mana + Cooldown + lebende Schamanin, zieht Mana ab, ruft `execute` |
| `scripts/spells/blast.gd` | „Druckwelle": Feindeinheiten im Radius erhalten **Knockback** — radialer Wurf als Tween-/Parabel (State THROWN, kein Y-Snapping während des Flugs), Landeposition auf begehbare Zelle geclampt, leichter Schaden |
| `scripts/spells/lightning.gd` | „Blitz": tötet die dem Zielpunkt nächste **feindliche** Einheit sofort (`take_damage(genug)`); visuell weißer Zylinder-Strahl kurz eingeblendet. Keine Feindeinheit im Umkreis → Cast schlägt fehl (kein Mana-Abzug) |
| `scripts/spells/swarm.gd` | „Insektenschwarm": Feindeinheiten im Radius → State PANIC für `panic_duration` (Zufallsbewegung auf begehbare Nachbarzellen, ignoriert Befehle/Angriffe); Timer läuft in `tick` ab → zurück zu IDLE |
| `scripts/spells/landbridge.gd` | „Landbrücke": `terrain_data.raise_area(target_xz, radius, amount)` → `terrain.apply_deformation(rect)` (Chunk-Rebuild + `HeightMapShape3D.map_data`-Update, **einmal** pro Cast) → `nav_grid.update_region(rect)`. Ergebnis: vorher Wasser, nachher begehbares Land |
| `scripts/spells/tornado.gd` | „Tornado": wandernder Wirbel (Node mit `tick`, zufällige Drift um den Zielpunkt, begrenzte Lebensdauer). Gebäude im Radius: kontinuierlicher HP-Schaden → Zerstörung (`Events.building_destroyed`, NavGrid-Footprint frei). Einheiten: vertikaler Wurf-Arc (THROWN wie Blast) |
| `scenes/ui/spell_bar.tscn` + `scripts/ui/spell_bar.gd` | Zauberleiste (deutsch): „Druckwelle", „Blitz", „Schwarm", „Landbrücke", „Tornado"; Hotkeys 1–5; zeigt Manakosten + Cooldown (ausgegraut, wenn nicht castbar oder Schamanin tot). Klick/Hotkey → Zielmodus (Cursor-Indikator) → Terrain-Klick → `TribeCommands.cast_spell`; Esc bricht ab |
| Spieler-Setup in `main.gd` | Blaue Schamanin + Reinkarnationsplatz gehören zur Startaufstellung beider Tribes |
| `tests/test_spells.gd`, `tests/test_shaman_respawn.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `spell.gd`-Framework + `cast_spell` in TribeCommands (Mana/Cooldown/Schamanin-Prüfung);
   Dummy-Spell für Framework-Tests.
2. `shaman.gd` + Startaufstellung; Cast-Flow UI → TribeCommands → Shaman läuft in
   Reichweite → `execute`.
3. **Landbridge zuerst** (architektonisch kritischster Zauber): Kette
   raise_area → apply_deformation → update_region; Test mit konkreter Wasserzelle.
4. Lightning, Swarm (PANIC-State in `unit.gd`), Blast (THROWN-State + Parabel), Tornado.
5. `reincarnation_site.gd`-Respawn + `test_shaman_respawn.gd`.
6. Zauberleiste (UI, Hotkeys, Cooldown-Anzeige).
7. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

`tests/test_spells.gd` (Spells mit injiziertem ctx headless ausführen):
- **Framework:** `cast_spell` bei zu wenig Mana → false, Mana unverändert; bei laufendem
  Cooldown → false; Erfolg → Mana um `mana_cost` reduziert, Cooldown gesetzt und tickt ab;
  tote Schamanin → kein Cast möglich.
- **Landbridge:** konkrete Wasserzelle (`is_walkable == false`, kein NavGrid-Pfad über
  die Wasserstraße) → nach Cast: Zelle begehbar, `find_path` liefert Pfad über die neue
  Brücke, `HeightMapShape3D.map_data`-Werte im Rect erhöht.
- **Lightning:** genau die nächstgelegene Feindeinheit stirbt, eigene/weiter entfernte
  Einheiten leben; ohne Feind im Umkreis kein Mana-Abzug.
- **Swarm:** Feindeinheiten im Radius sind PANIC, bewegen sich über Ticks (Position
  ändert sich), ignorieren `order_move`; nach `panic_duration` wieder IDLE und steuerbar.
- **Blast:** Feindeinheit im Radius hat nach Abschluss des Wurfs (Ticks) eine andere,
  begehbare Position mit größerer Distanz zum Epizentrum; während THROWN kein Y-Snapping.
- **Tornado:** Gebäude im Wirkbereich verliert getickt HP bis zur Zerstörung;
  Footprint-Zellen danach wieder begehbar.

`tests/test_shaman_respawn.gd`:
- Schamanin töten → `tribe.shaman` tot/null; ReincarnationSite ticken → vor Ablauf des
  Timers keine neue Schamanin, nach Ablauf genau **eine** neue am Platz,
  `tribe.shaman` gesetzt.
- Lebende Schamanin → Site spawnt nichts (nie zwei Schamaninnen).
- Zerstörte/fehlende Site → kein Respawn.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Zauberleiste zeigt 5 deutsche Zauber; Hotkeys 1–5; Ausgrauung bei Manangel/Cooldown.
- **Landbrücke** über eine Wasserstraße casten: Terrain hebt sich sichtbar (nur lokale
  Chunks, kein Ruckler), Einheiten laufen anschließend hinüber, Maus-Raycast trifft die
  neue Höhe korrekt.
- Blast wirft rote Einheiten sichtbar im Bogen zurück; Lightning tötet gezielt eine;
  Swarm lässt Gegner wuseln; Tornado wandert, zerlegt ein Gebäude, wirft Einheiten hoch.
- Schamanin sterben lassen → Zauber gesperrt → nach Wartezeit Respawn am
  Reinkarnationsplatz, Zauber wieder verfügbar.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden (insb. Landbrücke im Live-Spiel)
- [ ] Checkbox Phase 5 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 5: Schamanin & Zauber" && git push`
