# Phase 6 — Schamanin, Reinkarnation & alle 5 Zauber

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Das Magiesystem ist komplett: Schamanin (genau eine pro Stamm, respawnt am
Reinkarnationsplatz), `Spell`-Framework mit **Ladungssystem wie im Original**
(Mana wird automatisch in Zauber-Ladungen umgewandelt, Casts verbrauchen Ladungen —
kein separater Cooldown), alle 5 Zauber aus CLAUDE.md §6 — inklusive Landbridge mit
**Laufzeit-Terrainverformung** (der Architektur-Härtetest: `raise_area` →
Chunk-Rebuild → Kollisions-Update → NavGrid-Update). Der Zauber-Tab der Sidebar
(Phase 4) wird verdrahtet: Ladungs-Pips, Hotkeys 1–5, Schamanin-Porträt.

## Voraussetzungen

Phasen 1–5: TerrainData (`raise_area`), Terrain (`apply_deformation`), NavGrid
(`update_region`), Unit-States (PANIC, THROWN, CAST), Kampfsystem, Building
(HP/Zerstörung), TribeCommands, ReincarnationSite (Platzhalter aus Phase 3),
Zauber-Tab der Sidebar mit Anzeige-API `set_spell_state` und
Schamanin-Porträt-Button (Phase 4).

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/units/shaman.gd` + `scenes/units/shaman.tscn` | `class_name Shaman extends Unit`. Genau 1 pro Tribe (`tribe.shaman`), Cast-Animation, eigenes Sprite. Castet den vom Spieler gewählten Zauber auf Zielposition (läuft ggf. in Cast-Reichweite). Tod → `Events.unit_died` → ReincarnationSite startet Respawn-Timer |
| `scripts/buildings/reincarnation_site.gd` (erweitert) | Respawn-Logik in `tick`: Schamanin tot → `respawn_timer` runterzählen → neue Shaman-Instanz am Platz spawnen, `tribe.shaman` neu setzen. Kein Respawn, solange Schamanin lebt. Ohne Reinkarnationsplatz kein Respawn (Verlustrisiko) |
| `scripts/spells/spell.gd` | `class_name Spell extends RefCounted`. `id: StringName`, `display_name_de: String`, **Ladungssystem:** `charge_cost: float` (Mana je Ladung), `max_charges: int`, `charges: int`, `charge_progress: float` (Teilfüllung der nächsten Ladung, für die Pips). **Aufladung zentral in `Tribe.tick(delta)`:** verfügbares Mana wird automatisch in Ladungen umgewandelt — Round-Robin über die Zauber, billigster zuerst; je Umwandlung `mana -= charge_cost`, `charges += 1`, nur solange `charges < max_charges`; sind alle Zauber voll, sammelt sich Mana ungenutzt an. `execute(tribe: Tribe, target: Vector3, ctx) -> bool`. `ctx` = Zugriff auf TerrainData/Terrain/NavGrid/UnitManager/BuildingManager (Injektion → headless testbar). `TribeCommands.cast_spell(tribe, spell_id, target)` prüft `charges > 0` + lebende Schamanin, verbraucht 1 Ladung, ruft `execute`; schlägt `execute` fehl (z. B. Lightning ohne Ziel), bleibt die Ladung erhalten. **Kein separater Cooldown** — die Wiederaufladezeit ergibt sich aus der Mana-Rate |
| `scripts/spells/blast.gd` | „Druckwelle": Feindeinheiten im Radius erhalten **Knockback** — radialer Wurf als Tween-/Parabel (State THROWN, kein Y-Snapping während des Flugs), Landeposition auf begehbare Zelle geclampt, leichter Schaden |
| `scripts/spells/lightning.gd` | „Blitz": tötet die dem Zielpunkt nächste **feindliche** Einheit sofort (`take_damage(genug)`); visuell weißer Zylinder-Strahl kurz eingeblendet. Keine Feindeinheit im Umkreis → Cast schlägt fehl (keine Ladung verbraucht) |
| `scripts/spells/swarm.gd` | „Insektenschwarm": Feindeinheiten im Radius → State PANIC für `panic_duration` (Zufallsbewegung auf begehbare Nachbarzellen, ignoriert Befehle/Angriffe); Timer läuft in `tick` ab → zurück zu IDLE |
| `scripts/spells/landbridge.gd` | „Landbrücke": `terrain_data.raise_area(target_xz, radius, amount)` → `terrain.apply_deformation(rect)` (Chunk-Rebuild + `HeightMapShape3D.map_data`-Update, **einmal** pro Cast) → `nav_grid.update_region(rect)`. Ergebnis: vorher Wasser, nachher begehbares Land |
| `scripts/spells/tornado.gd` | „Tornado": wandernder Wirbel (Node mit `tick`, zufällige Drift um den Zielpunkt, begrenzte Lebensdauer). Gebäude im Radius: kontinuierlicher HP-Schaden → Zerstörung (`Events.building_destroyed`, NavGrid-Footprint frei). Einheiten: vertikaler Wurf-Arc (THROWN wie Blast) |
| Zauber-Tab + Schamanin-Porträt der Sidebar verdrahten | **Kein neues UI** — Buttons, Pip-Reihen und `set_spell_state(id, charges, max_charges, charge_progress, castable)` existieren seit Phase 4. Pro Zauber den Anzeige-Zustand füttern (ausgegraut, wenn keine Ladung oder Schamanin tot); Klick/Hotkey 1–5 → Zielmodus (Cursor-Indikator) → Terrain-Klick → `TribeCommands.cast_spell`; Esc bricht ab. **Schamanin-Porträt aktivieren:** Klick selektiert die Schamanin/springt zu ihr; während sie tot ist, zeigt das Porträt den Respawn-Countdown |
| Spieler-Setup in `main.gd` | Blaue Schamanin + Reinkarnationsplatz gehören zur Startaufstellung beider Tribes |
| `tests/test_spells.gd`, `tests/test_shaman_respawn.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `spell.gd`-Framework + Ladungs-Aufladung in `Tribe.tick` + `cast_spell` in
   TribeCommands (Ladungs-/Schamanin-Prüfung); Dummy-Spell für Framework-Tests.
2. `shaman.gd` + Startaufstellung; Cast-Flow UI → TribeCommands → Shaman läuft in
   Reichweite → `execute`.
3. **Landbridge zuerst** (architektonisch kritischster Zauber): Kette
   raise_area → apply_deformation → update_region; Test mit konkreter Wasserzelle.
4. Lightning, Swarm (PANIC-State in `unit.gd`), Blast (THROWN-State + Parabel), Tornado.
5. `reincarnation_site.gd`-Respawn + `test_shaman_respawn.gd`.
6. Zauber-Tab + Schamanin-Porträt verdrahten (`set_spell_state`, Zielmodus, Hotkeys,
   Respawn-Countdown).
7. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

`tests/test_spells.gd` (Spells mit injiziertem ctx headless ausführen):
- **Framework (Ladungssystem):** zu wenig Mana → keine Ladung entsteht, `charges` bleibt 0,
  `cast_spell` → false ohne Seiteneffekt; Aufladung über Ticks: Mana sinkt je
  `charge_cost`, `charges` steigt bis `max_charges`, danach fließt kein Mana mehr in
  diesen Zauber (sammelt sich an); Round-Robin: bei knappem Mana werden mehrere Zauber
  fair bedient (billigster zuerst); erfolgreicher Cast verbraucht genau 1 Ladung, Mana
  unverändert; fehlgeschlagenes `execute` → Ladung bleibt; tote Schamanin → kein Cast.
- **Landbridge:** konkrete Wasserzelle (`is_walkable == false`, kein NavGrid-Pfad über
  die Wasserstraße) → nach Cast: Zelle begehbar, `find_path` liefert Pfad über die neue
  Brücke, `HeightMapShape3D.map_data`-Werte im Rect erhöht.
- **Lightning:** genau die nächstgelegene Feindeinheit stirbt, eigene/weiter entfernte
  Einheiten leben; ohne Feind im Umkreis wird keine Ladung verbraucht.
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
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Zauber-Tab: Pips füllen sich mit steigendem Mana; Hotkeys 1–5; Ausgrauung ohne
  Ladung bzw. bei toter Schamanin; Schamanin-Porträt selektiert/springt zur Schamanin
  und zeigt den Respawn-Countdown, wenn sie tot ist.
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
- [ ] Checkbox Phase 6 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 6: Schamanin & Zauber" && git push`
