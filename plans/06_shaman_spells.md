# Phase 6 — Schamanin, Reinkarnation, Zauber & Gebäudezerstörung

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Überarbeitet 2026-07-06** (Nutzerwunsch): neue Zauberwerte (Feuerball statt Blast,
> Ladungszahlen, Schadenswerte relativ zum Brave-Leben), Schamanin-Werte + Kill-Bonus,
> und drei neue Kernmechaniken: **Panik**, **Umherschleudern (THROWN→ROLL)** und
> **Gebäudezerstörung in 4 Stufen**.

## Ziel

Das Magiesystem ist komplett: Schamanin (genau eine pro Stamm, respawnt am
Reinkarnationsplatz), `Spell`-Framework mit **Ladungssystem wie im Original**
(Mana wird automatisch in Zauber-Ladungen umgewandelt, Casts verbrauchen Ladungen —
kein separater Cooldown), alle 5 Zauber — inklusive Landbrücke mit
**Laufzeit-Terrainverformung** (der Architektur-Härtetest: `raise_area` →
Chunk-Rebuild → Kollisions-Update → NavGrid-Update). Dazu die neuen Mechaniken
Panik, Schleuderphysik und Gebäudezerstörung/-reparatur. Der Zauber-Tab der Sidebar
(Phase 4) wird verdrahtet: Ladungs-Pips, Hotkeys 1–5, Schamanin-Porträt.

**Referenzwert für alle Schadensangaben:** `BRAVE_HP = 60` (Brave-Leben).

## Voraussetzungen

Phasen 1–5: TerrainData (`raise_area`), Terrain (`apply_deformation`), NavGrid
(`update_region`), Unit-States inkl. **ROLL** (Phase 5d: Falllinie, Rollschaden
`ROLL_DPS`, Wasser = Sofort-Tod), Kampfsystem (`take_damage(amount, attacker)`,
`last_attacker`, Knockback-System), Building (HP, `take_damage`/`destroy`,
Footprint-Freigabe), TribeCommands, ReincarnationSite, Zauber-Tab der Sidebar mit
`set_spell_state` und Schamanin-Porträt-Button (Phase 4).

## Schamanin (neue Werte)

- **HP: 240** (= 4 × Brave-Leben), **Nahkampf: `melee_strength = 2.0`**
  (= 2 × Brave-Schaden; Basis-Schadenswerte Punch/Kick/Shove unverändert).
- **Kill-Bonus:** Wird eine Schamanin getötet, erhält der Stamm des Tötenden
  (`last_attacker.tribe`) einen **einmaligen Manaboost von 15 %, direkt als
  Ladungen ausgezahlt**. *Auslegung (Annahme, siehe „Offene Auslegungen"):*
  Bonus-Mana = `0.15 × Σ(charge_cost × max_charges)` über alle Zauber des
  Empfängers, wird sofort durch die normale Ladungs-Umwandlung geschickt
  (überschüssiges Mana bleibt im Pool).
- Respawn wie geplant: Tod → ReincarnationSite zählt `respawn_timer` runter →
  neue Schamanin am Platz, `tribe.shaman` neu gesetzt; ohne Site kein Respawn.

## Neue Kernmechaniken

### 1. Umherschleudern (THROWN → ROLL)

- `Unit.throw_airborne(impulse: Vector3, opts)` — State **THROWN**: skriptete
  Parabel (kein Y-Snapping, keine Befehle, Separation aus — Ausnahme in
  UnitManager existiert seit 3c). Landung: optionaler **Sturzschaden**, dann
  Übergang in **ROLL mit Anfangsgeschwindigkeit** statt fester Dauer.
- `start_roll` wird erweitert: optionale Anfangsgeschwindigkeit, die über
  Reibung abklingt — auf **ebenem Boden schnelles Ausrollen und Aufstehen**,
  an Hängen übernimmt die bestehende Falllinien-Logik (5d). Rollschaden wie
  gehabt (`ROLL_DPS`), **Wasser (geworfen oder gerollt) = Sofort-Tod**,
  Landeposition/Rollweg auf begehbare Zellen geclampt (Gebäudezellen stoppen).

### 2. Panik (PANIC)

- State **PANIC**: Einheit rennt in zufällig wechselnden Richtungen von der
  Panikquelle weg (begehbare Nachbarzellen), ignoriert Befehle und Angriffe,
  ist aber angreifbar. Dauer pro Auslösung **6 s**, danach zurück zu IDLE.
  Schamaninnen sind **immun** gegen Panik.

### 3. Gebäudezerstörung (4 Zerstörungsstufen)

Stufe ergibt sich aus dem Schadensanteil (`1 - hp/max_hp`), Helfer auf
`Building`: `destruction_stage() -> int` und `apply_destruction_stages(n)`
(= `n × 30 %` der Max-HP als Schaden):

| Stufe | Schwelle | Zustand |
|---|---|---|
| 0 | < 30 % Schaden | intakt, voll nutzbar (bisheriges Verhalten) |
| 1 | ≥ 30 % | **nicht nutzbar**, reparierbar per Rechtsklick |
| 2 | ≥ 60 % | wie 1, mehr sichtbare Schäden |
| 3 | ≥ 90 % | wie 1, fast zerstört |
| 4 | 100 % | Gebäude **versinkt im Boden** (kurze Versink-Animation, dann `destroy()`), Footprint wieder begehbar/bebaubar |

- **Nicht nutzbar (Stufe 1–3) = keinerlei Produktion:** kein Hütten-Spawn,
  kein Training (laufender Trainee + Warteschlange werden freigelassen wie bei
  `destroy()`), `production_progress()` = −1; Kapazität zählt nicht zur
  Bevölkerungsgrenze *(Annahme, siehe unten)*.
- **Reparatur kostet Holz proportional zum reparierten Schaden:**
  Gesamtbedarf = `floor(Schadensanteil × wood_cost)` (Beispiel: Hütte mit 90 %
  Schaden → 90 % der Hütten-Holzkosten, abgerundet). Ablauf analog Bau-Phase 2:
  Rechtsklick mit selektierten Braves auf ein beschädigtes eigenes Gebäude →
  `order_repair` (TribeCommands) → Brave-Task REPAIR (hinlaufen, hämmern,
  HP-Regeneration mit fester Rate); Arbeiter beschaffen Holz wie beim Bau
  (Stapel/Bäume → Eingang, Absorption), der **Reparaturfortschritt ist auf das
  gelieferte Holz gedeckelt** (1 Holz repariert `max_hp / wood_cost` HP).
  Stufe sinkt automatisch mit steigenden HP, ab < 30 % Schaden wieder nutzbar.
- **Visual (Placeholder-Schiene):** pro Stufe werden mehr „herausgebrochene
  Stücke" gezeigt — dunkle Loch-Quader/entfernte Mesh-Teile am prozeduralen
  Modell, je höher die Stufe, desto mehr. Echte Texturen können später
  dieselben Stufen-Hooks nutzen.

## Zauber (Werte-Übersicht)

Alle `max_charges` wie unten; `charge_cost` je Zauber vorläufig (Start-Werte,
Feinbalance in Phase 8). Ziel-/Wirkungsangaben: „Feind" = Einheiten fremder Tribes.

| # | Zauber | max_charges | Effekt |
|---|---|---|---|
| 1 | **Feuerball** (ersetzt „Blast/Druckwelle") | 4 | Projektil zum Zielpunkt. **Flächenschaden am Einschlag: 30** (½ Brave-Leben) in kleinem Umkreis; **Direkttreffer: 60** (1 × Brave-Leben). Getroffene Einheiten werden **zurückgeschleudert und in die Luft gehoben** (kleiner Bogen, THROWN) und landen im **Rollzustand**; ohne Hang kommen sie schnell zum Stehen |
| 2 | **Landbrücke** | 4 | Kein Schaden, reine Terrainverformung in **breiter Linie** vom Startpunkt zum Zielpunkt: Zeigt man über Wasser auf Wasser/eine andere Küste, wird die Linie **auf Küstenniveau angehoben**; zeigt man auf Land (z. B. über eine Schlucht), wird die Zwischenlinie **auf das Niveau des Zielpunkts** gehoben. Bei unterschiedlicher Start-/Zielhöhe entsteht eine **begehbare Schräge** |
| 3 | **Blitz** | 4 | Trifft Einheiten **oder Gebäude**. Einheit: **240 Schaden** (4 × Brave-Leben); bei einem Einzeltreffer kommen **angrenzende Einheiten ins Rollen** (ohne Hang nur kurz). Gebäude: **+2 Zerstörungsstufen** *(Auslegung, s. u.)* |
| 4 | **Insektenschwarm** | 4 | Spawnt einen Schwarm mit **10 s Lebenszeit**, der zufällig umherwandert. Feinde nahe am Schwarm geraten in **Panik (6 s)** und erleiden **leichten Schaden** (~3 HP/s im Schwarmradius). **Schamanin immun** gegen den Panikeffekt |
| 5 | **Tornado** | 3 | Windhose am Zielpunkt, **8 s Lebenszeit**, wandert zufällig. Über Gebäuden: **+1 Zerstörungsstufe alle 2 s**. Einheiten im Weg werden **bis zur Tornadospitze hochgewirbelt**, kurz mitgetragen und mit **hoher Geschwindigkeit weggeschleudert**; Landung → Rollen bis die Geschwindigkeit abgeklungen ist, dann aufstehen. **Sturzschaden 30** (½ Brave-Leben) + Rollschaden wie üblich; Sturz/Rollen ins **Wasser = Sofort-Tod** |

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/units/shaman.gd` + `scenes/units/shaman.tscn` | `class_name Shaman extends Unit`. **HP 240, melee_strength 2.0**, panik-immun. Genau 1 pro Tribe (`tribe.shaman`), Cast-Animation, eigenes Sprite (Kind in `UnitRenderer.KINDS` ergänzen). Castet den gewählten Zauber auf Zielposition (läuft ggf. in Cast-Reichweite). Tod → **Kill-Bonus an den Stamm des Tötenden** (`last_attacker`) + `Events.unit_died` → ReincarnationSite startet Respawn-Timer |
| `scripts/buildings/reincarnation_site.gd` (erweitert) | Respawn-Logik in `tick`: Schamanin tot → `respawn_timer` runterzählen → neue Shaman-Instanz am Platz spawnen, `tribe.shaman` neu setzen. Kein Respawn, solange sie lebt; ohne Site kein Respawn |
| `scripts/spells/spell.gd` | `class_name Spell extends RefCounted`. `id`, `display_name_de`, **Ladungssystem:** `charge_cost: float`, `max_charges: int`, `charges: int`, `charge_progress: float`. **Aufladung zentral in `Tribe.tick(delta)`:** Mana → Ladungen (Round-Robin, billigster zuerst), voll = Mana sammelt sich. `execute(tribe, target, ctx) -> bool` (`ctx` = TerrainData/Terrain/NavGrid/UnitManager/BuildingManager — Injektion, headless testbar). `TribeCommands.cast_spell` prüft `charges > 0` + lebende Schamanin, verbraucht 1 Ladung; schlägt `execute` fehl, bleibt die Ladung erhalten. **`grant_bonus_mana(tribe, amount)`**-Pfad für den Schamanin-Kill-Bonus (läuft durch dieselbe Umwandlung) |
| `scripts/spells/fireball_spell.gd` | „Feuerball" (Name so, weil `scripts/units/fireball.gd` = Feuerkrieger-Projektil): Werte s. Tabelle; Wurf über `throw_airborne` (kleiner Bogen), Landung → Roll mit schnellem Ausrollen auf Ebenem |
| `scripts/spells/landbridge.gd` | „Landbrücke": Linien-Verformung Start→Ziel (breiter Korridor). Wasser-Ziel/Küste → auf Küstenniveau (`sea_level` + Marge) anheben; Land-Ziel → Zwischenlinie aufs Zielniveau, Höhenverlauf als **begehbare Rampe** (Hangneigung unter `is_walkable`-Schwelle) interpolieren. Danach `terrain.apply_deformation(rect)` (**einmal** pro Cast) + `nav_grid.update_region(rect)`. Startpunkt = Cast-Ursprung der Schamanin (nächstgelegene eigene Küsten-/Standzelle Richtung Ziel) |
| `scripts/spells/lightning.gd` | „Blitz": Zielauflösung am Klickpunkt — Gebäude → `apply_destruction_stages(2)`; sonst nächste Feindeinheit → 240 Schaden, angrenzende Einheiten (~1,5 m) → kurze Mini-Rolle (eben) bzw. Hang-Rolle. Visuell weißer Zylinder-Strahl. Kein Ziel im Umkreis → Cast schlägt fehl (Ladung bleibt) |
| `scripts/spells/swarm.gd` + Schwarm-Node | „Insektenschwarm": Schwarm-Entity mit `tick` (Zufallsdrift, 10 s Lebenszeit, headless testbar); Feinde im Radius → PANIC (6 s, bei anhaltender Nähe erneuert) + ~3 HP/s; Schamanin panik-immun |
| `scripts/spells/tornado.gd` + Tornado-Node | „Tornado": wandernder Wirbel (`tick`, Zufallsdrift, 8 s). Gebäude unter dem Wirbel: alle 2 s `apply_destruction_stages(1)`. Einheiten im Weg: Hochwirbeln zur Spitze (THROWN-Sonderpfad: Aufstieg + kurzes Mittragen), dann Wegschleudern mit hoher Geschwindigkeit → Landung mit Sturzschaden 30 → Roll bis Geschwindigkeit abgeklungen |
| `scripts/units/unit.gd` (erweitert) | **THROWN**: `throw_airborne(impulse, opts)` (Parabel, kein Y-Snap, Landung → Sturzschaden + Roll-Übergang); **ROLL**: Anfangsgeschwindigkeit + Reibungs-Abklingen; **PANIC**: `start_panic(source_pos, duration)` + `_tick_panic` (Zufallsflucht, 6 s), `is_panic_immune()` (Schamanin true) |
| `scripts/buildings/building.gd` (erweitert) + Subklassen | Zerstörungsstufen (`destruction_stage`, `apply_destruction_stages`, `is_usable()`), Stufen-Visuals (herausgebrochene Stücke), Versinken bei Stufe 4 → `destroy()`; Hut/TrainingBuilding respektieren `is_usable()` (kein Spawn/Training, Freilassen wie bei destroy); Reparatur-HP-Pfad (`repair(amount)`) |
| `scripts/units/brave.gd` + `tribe_commands.gd` + `selection_manager.gd` | Task **REPAIR** (analog CONSTRUCT **inkl. Holzlogistik**: CHOP/PICKUP/DELIVER an den Eingang, Fortschritt auf geliefertes Holz gedeckelt), `TribeCommands.order_repair(building, units)`, Rechtsklick auf beschädigtes eigenes Gebäude → reparieren |
| Zauber-Tab + Schamanin-Porträt verdrahten | **Kein neues UI** — `set_spell_state(...)` existiert seit Phase 4. Eintrag 1 heißt jetzt **„Feuerball"** (Icon-Key `blast` in `ui_theme.gd`/`default_spell_entries()` → `fireball`). Klick/Hotkey 1–5 → Zielmodus (Cursor-Indikator) → Terrain-Klick → `cast_spell`; Esc bricht ab; ausgegraut ohne Ladung/bei toter Schamanin. Porträt: Klick selektiert/springt zur Schamanin; tot → Respawn-Countdown |
| Spieler-Setup in `main.gd` | Blaue **und rote** Schamanin + Reinkarnationsplatz in der Startaufstellung beider Tribes |
| `tests/test_spells.gd`, `tests/test_shaman_respawn.gd`, `tests/test_building_destruction.gd` | siehe Tests unten |

## Umsetzungsschritte

1. `spell.gd`-Framework + Ladungs-Aufladung in `Tribe.tick` + `cast_spell` in
   TribeCommands; Dummy-Spell für Framework-Tests.
2. **Gebäudezerstörung** (Stufen, Nutzbarkeits-Sperre, Versinken, Reparatur-Task) —
   eigenständig testbar, Blitz/Tornado bauen darauf auf.
3. **Schleuderphysik** (`throw_airborne`, Roll mit Anfangsgeschwindigkeit) +
   **PANIC-State** in `unit.gd` — eigenständig testbar, Feuerball/Schwarm/Tornado
   bauen darauf auf.
4. `shaman.gd` (Werte, Kill-Bonus) + Startaufstellung; Cast-Flow UI →
   TribeCommands → Shaman läuft in Reichweite → `execute`.
5. **Landbrücke zuerst unter den Zaubern** (architektonisch kritischster):
   Linien-Verformung mit Rampe; Test mit konkreter Wasserzelle + Höhendifferenz.
6. Feuerball, Blitz, Schwarm, Tornado.
7. `reincarnation_site.gd`-Respawn + `test_shaman_respawn.gd`.
8. Zauber-Tab + Schamanin-Porträt verdrahten (inkl. Feuerball-Umbenennung).
9. Verifikation + manuelle Prüfung + Commit/Push.

## Tests

`tests/test_building_destruction.gd`:
- Stufen-Schwellen: 0/30/60/90/100 % Schaden → Stufe 0–4; `is_usable()` nur bei
  Stufe 0; Hütte auf Stufe ≥ 1 spawnt nicht, TrainingBuilding lässt Trainee +
  Warteschlange frei.
- `apply_destruction_stages(2)` = 60 % Max-HP-Schaden.
- Stufe 4: nach dem Versinken Footprint-Zellen wieder begehbar, aus Registry raus.
- Reparatur: REPAIR-Task hebt HP, Stufe sinkt, ab < 30 % wieder nutzbar.
- Reparatur-Holzkosten: 90 % Schaden an der Hütte → Gesamtbedarf
  `floor(0.9 × wood_cost)`; ohne geliefertes Holz kein Fortschritt (Deckel),
  1 geliefertes Holz repariert `max_hp / wood_cost` HP.
- Stufe ≥ 1: `production_progress()` = −1 (keine Produktion/kein Balken).

`tests/test_spells.gd` (Spells mit injiziertem ctx headless):
- **Framework:** wie bisher (zu wenig Mana → keine Ladung; Aufladung über Ticks
  bis `max_charges`; Round-Robin billigster zuerst; Cast verbraucht genau 1 Ladung;
  fehlgeschlagenes `execute` → Ladung bleibt; tote Schamanin → kein Cast) +
  `max_charges` je Zauber = 4/4/4/4/3.
- **Schamanin-Kill-Bonus:** Schamanin von Einheit des Gegner-Tribes töten →
  Gegner-Tribe erhält Bonus-Mana/Ladungen in erwarteter Höhe (15 % der
  Ladungskapazität); Tod ohne Attacker (z. B. Wasser) → kein Bonus.
- **Feuerball:** Direkttreffer = 60 Schaden, Einheit im Umkreis = 30; Getroffene
  sind THROWN (kein Y-Snap), landen, rollen und stehen auf ebenem Boden schnell
  wieder (Position ≠ Start, begehbar).
- **Landbrücke:** Wasserzelle (`is_walkable == false`, kein Pfad) → nach Cast
  begehbar, `find_path` über die Brücke, `map_data`-Werte im Rect erhöht;
  **Rampen-Fall:** Start/Ziel mit Höhendifferenz → alle Linien-Zellen begehbar
  (Hangneigung unter Schwelle).
- **Blitz:** Feindeinheit = 240 Schaden (Brave/Krieger tot, volle Schamanin genau
  tot); angrenzende Einheit rollt kurz; Gebäudeziel → Stufe +2; kein Ziel →
  Ladung bleibt.
- **Schwarm:** Schwarm despawnt nach 10 s; Feind nahe am Schwarm ist PANIC,
  bewegt sich, ignoriert `order_move`, nach 6 s (ohne erneute Nähe) wieder
  steuerbar; leichter Schaden getickt; Schamanin bleibt steuerbar (immun).
- **Tornado:** despawnt nach 8 s; Gebäude unter dem Wirbel steigt alle 2 s um
  1 Stufe (nach 8 s = Stufe 4 → weg, Footprint frei); Einheit im Weg wird
  hochgewirbelt (Y steigt), weggeschleudert, erleidet Sturzschaden 30 + Rollschaden
  und steht danach an begehbarer Position; Wurf/Rolle ins Wasser → tot.

`tests/test_shaman_respawn.gd`:
- Schamanin töten → `tribe.shaman` tot/null; Site ticken → vor Ablauf keine neue,
  nach Ablauf genau **eine** neue am Platz, `tribe.shaman` gesetzt.
- Lebende Schamanin → kein Spawn (nie zwei); zerstörte/fehlende Site → kein Respawn.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Zauber-Tab: Pips füllen sich; Hotkeys 1–5; Ausgrauung ohne Ladung/bei toter
  Schamanin; Eintrag 1 heißt „Feuerball"; Porträt selektiert/springt zur Schamanin
  und zeigt den Respawn-Countdown.
- **Landbrücke** über eine Wasserstraße: Terrain hebt sich als breite Linie (nur
  lokale Chunks, kein Ruckler), bei Höhendifferenz begehbare Schräge, Einheiten
  laufen hinüber, Maus-Raycast trifft die neue Höhe.
- **Feuerball**: Einschlag wirft Einheiten sichtbar im Bogen, sie rollen kurz und
  stehen auf; Direkttreffer tötet einen Brave.
- **Blitz** auf Gebäude: sichtbar herausgebrochene Stücke (Stufe 2), Gebäude nicht
  mehr nutzbar; Rechtsklick mit Braves → Reparatur, danach wieder nutzbar.
- **Schwarm**: wandert, Gegner nahe dran wuseln panisch davon; eigene Schamanin
  bleibt gelassen.
- **Tornado**: wandert 8 s, zerlegt ein Gebäude stufenweise bis zum Versinken
  (Bauplatz wieder frei), wirbelt Einheiten zur Spitze hoch und schleudert sie
  weg; Landung → Rollen → Aufstehen; ins Wasser = Tod.
- Schamanin sterben lassen → Zauber gesperrt, Gegner bekommt sichtbaren
  Ladungsschub → nach Wartezeit Respawn am Reinkarnationsplatz.

## Offene Auslegungen (bei der Umsetzung so angenommen — bei Bedarf korrigieren)

1. **„Blitz löst Zerstörstufe 2 aus"** → als **+2 Stufen** (60 % Max-HP-Schaden)
   umgesetzt, nicht „setzt auf Stufe 2" (sonst wäre Blitz auf ein Stufe-2/3-Gebäude
   wirkungslos).
2. **Kill-Bonus „15 % Manaboost in Ladungen"** → 15 % der **Gesamt-Ladungskapazität**
   des Empfängers (Σ `charge_cost × max_charges`) als Bonus-Mana durch die normale
   Umwandlung.
3. **Nicht nutzbar (Stufe 1–3)** schließt neben der Produktion auch die
   **Hütten-Kapazität** ein (zählt nicht zur Bevölkerungsgrenze, solange beschädigt).
4. **Schadenszauber treffen nur Feinde** (wie bisher geplant); Schwarm-Panik trifft
   nur Gegner, die Schamanin ist nur gegen den **Panikeffekt** immun, nicht gegen
   den leichten Schwarmschaden.
5. `charge_cost` je Zauber sind **Startwerte** (Balancing in Phase 8).

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden (insb. Landbrücke + Tornado/Gebäudezerstörung im Live-Spiel)
- [ ] Checkbox Phase 6 in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 6: Schamanin & Zauber" && git push`
