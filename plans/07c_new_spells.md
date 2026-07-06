# Phase 7c — Neue Zauber: Erdbeben, Vulkan, Feuerregen, Ebene, Absinken

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Fünf neue Zauber im bestehenden Ladungssystem: **Erdbeben**
(Flächen-Terrainverwerfung + Gebäudeschaden), **Vulkan** (permanenter
Terrain-Kegel + Lava-Schadenszone), **Feuerregen** (Feuerball-Salve über eine
Fläche), **Ebene** (quadratische Fläche wird schlagartig auf Zielpunkt-Höhe
planiert) und **Absinken** (Gegenstück zur Landbrücke: Terrain absenken,
Küstenland fluten). Dazu **allgemeine Terrain-Integritätsregeln** für ALLE
terrainändernden Zauber (Gebäude zerplatzen bei zu großem
Fundament-Höhenunterschied, Gebäude rutschen ins Wasser, Einheiten ertrinken
auf gefluteten Flächen). Zauberleiste wächst auf 10 Slots, die KI nutzt die
neuen Zauber situativ.

## Voraussetzungen

Phase 6: komplettes Spell-Framework — `Spell`-Basisklasse (`charge_cost`,
`max_charges`, `cast_range`, `execute`), `SpellContext`
(`apply_terrain_change` = NavGrid-Update + `terrain_deformed`),
Ladungs-Round-Robin in `Tribe`, `SpellTargeting`-Zielmodus, Schamanin-Cast-Flow.
Wiederverwendbare Vorlagen: [landbridge_morph.gd](../scripts/spells/landbridge_morph.gd)
(graduelle Terrainverformung über Schritte), [fireball_bolt.gd](../scripts/spells/fireball_bolt.gd)
(Parabel-Projektil + AoE + Wegschleudern), [tornado_vortex.gd](../scripts/spells/tornado_vortex.gd)
/ [swarm_cloud.gd](../scripts/spells/swarm_cloud.gd) (Lebenszeit-Entitäten über
die Projektil-Liste). Gebäude: `footprint_rect()` + bestehende
Versink-Animation (`SINK_DURATION`/`SINK_DEPTH` in
[building.gd](../scripts/buildings/building.gd)) als Basis für die neuen
Zerstörungs-Visuals.

## Ladungszahlen (verbindlich)

| Zauber | `max_charges` |
|---|---|
| Erdbeben | **2** |
| Vulkan | **1** |
| Feuerregen | **2** |
| Ebene | **3** |
| Absinken | **3** |

(`charge_cost`-Werte unten sind Startwerte; Feinbalance in Phase 8.)

## Deliverables

| Datei | Inhalt |
|---|---|
| Terrain-Integritätsregeln (`spell_context.gd` + `building.gd`) | **Gilt für ALLE terrainändernden Zauber** (Landbrücke, Erdbeben, Vulkan, Ebene, Absinken): Nach `ctx.apply_terrain_change(rect)` werden Gebäude und Einheiten im Rect geprüft. **(a) Fundament-Bruch:** Ist der Höhenunterschied unter dem Gebäude-Footprint größer als ein Schwellwert (Startwert ~1,2 m zwischen höchstem und tiefstem Fundament-Vertex), wird das Gebäude **sofort zerstört** und das Modell **fliegt in Einzelteilen auseinander** (Trümmer-Fragmente als Parabel-Wurf nach dem `FireballBolt`-Wegschleuder-Muster; Visual-Placeholder nur in `_ready`, headless-sicher). **(b) Überflutung Gebäude:** Stehen ≥ 30 % der Fundamentfläche unter `SEA_LEVEL`, **rutscht das Gebäudemodell ins Wasser und versinkt** (Variante der bestehenden Sink-Animation mit seitlichem Versatz Richtung Wasser) — Gebäude zerstört, Bauplatz frei. **(c) Ertrinken:** Einheiten, deren Standfläche unter `SEA_LEVEL` gerät, **sterben sofort** (bestehende Wasser-Tod-Regel wie beim Tornado). Baustellen sterben bei jeder Terrainänderung im Footprint sofort (bestehende Fragil-Regel) |
| `scripts/spells/earthquake.gd` | **Erdbeben** (`id = &"earthquake"`). Startwerte: `charge_cost 80`, `max_charges 2`, `cast_range 10`. Effekt im Radius ~7 m um den Zielpunkt: **Terrainverwerfung** — deterministisch zufällige Vertex-Deltas (±1,5 m, Falloff zum Rand, Seed aus Zielzelle), **graduell über ~2 s** nach dem `LandbridgeMorph`-Muster (eigene Morph-Entität oder LandbridgeMorph verallgemeinern: Ziel-Höhenkarte statt Linienprofil). Gebäude im Radius: **+2 Zerstörungsstufen**; zusätzlich greifen die Integritätsregeln (Fundament-Bruch/Überflutung). Einheiten im Radius: **Mini-Rolle** (`start_roll`, Richtung vom Epizentrum weg) + leichter Schaden (¼ Brave-Leben). Anheben nie über `SEA_LEVEL + 1,2`-Klemme hinaus wie Landbrücke — Senken unter die Seelinie sind ERLAUBT und fluten Land (Integritätsregeln c/b). Nav-Update über `ctx.apply_terrain_change(rect)` |
| `scripts/spells/volcano.gd` + `scripts/spells/volcano_zone.gd` | **Vulkan** (`id = &"volcano"`). Startwerte: `charge_cost 120`, `max_charges 1`, `cast_range 12`. Effekt: **Kegel-Anhebung** (+6 m Spitze, Radius ~5 m, `TerrainData.raise_area`, graduell über ~3 s) — **bleibt permanent** als Berg (Spitze/Steilhang unbegehbar = gewollt). Dazu `VolcanoZone` (Lebenszeit-Entität über `register_projectile`, Muster `swarm_cloud`): **20 s Lava** — Feinde UND eigene Einheiten im Radius 5 m nehmen 10 Schaden/s (Lava kennt keine Freunde; dokumentierte Auslegung), Gebäude im Radius **+1 Stufe alle 4 s** (Integritätsregeln greifen zusätzlich beim Kegel-Wachstum). Visual: orangefarbene Partikel-/Mesh-Placeholder nur in `_ready` (headless-sicher) |
| `scripts/spells/firestorm.gd` | **Feuerregen** (`id = &"firestorm"`). Startwerte: `charge_cost 70`, `max_charges 2`, `cast_range 10`. Effekt: **8 Feuerbälle** über 3 s zeitversetzt auf deterministisch gestreute Punkte im Radius 4 m um den Zielpunkt — `FireballBolt` unverändert wiederverwenden (gleicher Direkt-/Flächenschaden + Wegschleudern je Einschlag, Attacker = Schamanin). Eigene Scheduler-Entität über die Projektil-Liste (spawnt die Bolts über Zeit) |
| `scripts/spells/flatten_spell.gd` | **Ebene** (`id = &"flatten"`). Startwerte: `charge_cost 70`, `max_charges 3`, `cast_range 10`. Effekt: **quadratische Fläche** (~9 × 9 m, zellen-ausgerichtet um den Zielpunkt) wird auf die **Elevation des Zielpunkts** planiert. **Harte Kanten:** kein Falloff — Vertices innerhalb des Quadrats exakt auf Zielhöhe, außerhalb unverändert (am Rand entstehen Klippen/Steilkanten). **Schnell:** Morph über ~0,5 s. Einheiten auf der Fläche werden je nach lokalem Höhendelta **umhergeschleudert**: schnelles Anheben → Wurfparabel + Rollen (Wegschleuder-Muster aus `FireballBolt`), Absenken → Sturz + Rollen; auf entstandenen Schrägen/Kanten rollen sie aus bzw. fallen herunter. **Keine Klemme nach unten:** Liegt der Zielpunkt unter der Seelinie, wird die Fläche geflutet — Integritätsregeln (b)/(c) greifen. Gebäude am Flächenrand mit zu großem Fundament-Höhenunterschied **zerplatzen sofort in Einzelteile** (Integritätsregel a). Nav-Update über `ctx.apply_terrain_change(rect)` |
| `scripts/spells/sink.gd` | **Absinken** (`id = &"sink"`). Startwerte: `charge_cost 60`, `max_charges 3`, `cast_range 10`. **Gegenstück zur Landbrücke:** senkt das Terrain im Radius ~6 m um den Zielpunkt um bis zu ~3 m ab — **weicher Falloff** (Kosinus) zum Rand, deutlich **sanftere Kanten als bei Ebene**. Graduell über ~1,5 s (`LandbridgeMorph`-Muster). Auf Land werden Hügel/Berge abgetragen; **Klemme nach unten auf Meeresboden-Niveau** (nicht tiefer als der bestehende Seegrund). In Küstennähe sinkt Land unter `SEA_LEVEL` und wird geflutet: **Anhänger auf gefluteter Fläche sterben sofort** (Integritätsregel c), **Gebäude mit ≥ 30 % Fundament im Wasser rutschen ins Wasser und versinken** (Integritätsregel b), Gebäude mit zu großem Fundament-Höhenunterschied zerplatzen (Integritätsregel a). Nav-Update über `ctx.apply_terrain_change(rect)` |
| `Spell.create_default_set()` | Um die 5 neuen Zauber ergänzt (Round-Robin/Kostensortierung skaliert automatisch; Startladung-1-Regel aus `main.gd` gilt mit) |
| UI: 10 Zauber-Slots | `Sidebar.default_spell_entries()` + `set_spell_state`-Verdrahtung um 5 Einträge; neue 24×24-Icons in `ui_theme.gd` (`earthquake`/`volcano`/`firestorm`/`flatten`/`sink`); Input-Actions `cast_spell_6..10` (Tasten 6–9 und 0) in `project.godot`; `SpellTargeting`-Hotkey-Liste erweitern. `SpellTargeting`-Vorschau: Ebene zeigt ein **Quadrat**, Absinken einen Kreis. Layout: Zauber-Tab muss 10 Zellen fassen (2 Spalten/kleinere Pips — Sidebar ist 260 px breit) |
| KI-Heuristik | `AIController._cast_spells`-Prioritäten erweitern: **Feuerregen** statt Feuerball ab großem Cluster (≥ 5 Feinde), **Vulkan** auf Gebäudegruppen (≥ 2 Feindgebäude im 5-m-Umkreis des Ziels), **Absinken** auf küstennahe Feindgebäude (Fundament nahe `SEA_LEVEL` → Fluten billiger als Beschuss), **Ebene** auf Feindgebäude an Hängen (erwarteter Fundament-Bruch), **Erdbeben** als Gebäude-Fallback vor dem Blitz. Ein Cast/Tick, Durchfallen ohne Ladung wie bisher |
| `tests/test_spells.gd` (erweitert) | siehe Tests |

## Umsetzungsschritte

1. Terrain-Integritätsregeln (Fundament-Bruch + Trümmer, Ins-Wasser-Rutschen,
   Ertrinken) in `apply_terrain_change`-Pfad + Tests grün — zuerst, da alle
   Terrain-Zauber darauf aufbauen.
2. Erdbeben (Terrainverwerfung graduell + Gebäude/Einheiten-Effekt) + Tests grün.
3. Vulkan (Kegel + `VolcanoZone`) + Tests grün.
4. Feuerregen (Bolt-Scheduler) + Tests grün.
5. Ebene (Quadrat-Planierung, harte Kanten, Schleudern) + Tests grün.
6. Absinken (weiches Absenken, Fluten) + Tests grün.
7. `create_default_set` + UI (10 Slots, Icons, Hotkeys 6–0, Zielmodi inkl.
   Quadrat-Vorschau).
8. KI-Heuristik erweitern (+ Test).
9. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_spells.gd`)

- **Integritätsregeln:** Gebäude über künstlich verworfenem Fundament
  (Differenz > Schwelle) → nach `apply_terrain_change` sofort zerstört +
  Trümmer-Entities gespawnt; Gebäude mit ≥ 30 % Fundament unter `SEA_LEVEL` →
  zerstört (Rutsch-Versinken), Bauplatz wieder frei; Einheit auf gefluteter
  Zelle → tot, Einheit auf trockener Nachbarzelle → lebt.
- **Erdbeben:** Höhen im Radius nach Morph-Ende verändert (mind. ein Vertex ±),
  außerhalb unverändert; Gebäude im Radius +2 Stufen, außerhalb 0; Einheit im
  Radius nimmt Schaden/rollt; Cast verbraucht genau 1 Ladung; Hebe-Klemme.
- **Vulkan:** Kegelspitze ≥ Zielhöhe +5 nach Morph; Zone schädigt Feind UND
  eigene Einheit; Gebäude +1 Stufe nach 4 s Kontakt; Zone despawnt nach 20 s;
  Berg bleibt (Höhe nach Despawn unverändert).
- **Feuerregen:** Über die Laufzeit entstehen 8 Bolts (Projektil-Liste);
  Einschläge verteilen sich im 4-m-Radius; Gesamtschaden an einer Traube > ein
  Einzelfeuerball; 1 Ladung pro Cast.
- **Ebene:** Nach dem Morph liegen ALLE Vertices der Quadratfläche exakt auf
  Zielpunkt-Höhe, direkt außerhalb unverändert (harte Kante messbar); Einheit
  auf stark angehobener Zelle wird geschleudert/rollt; Gebäude halb auf der
  Fläche (Fundament-Differenz > Schwelle) → zerplatzt sofort; Zielpunkt unter
  Seelinie → Fläche geflutet, Einheit darauf tot; 1 Ladung pro Cast.
- **Absinken:** Zentrum um ~3 m gesenkt, Randvertex weniger als Zentrum
  (Falloff messbar), außerhalb unverändert; Klemme: Seegrund wird nicht weiter
  vertieft; Küsten-Cast: Landzelle gerät unter `SEA_LEVEL` → Einheit darauf
  ertrinkt, Gebäude mit ≥ 30 % Fundament im Wasser versinkt; 1 Ladung pro Cast.
- **Set/UI-Logik:** `create_default_set` liefert 10 Zauber mit den
  verbindlichen Ladungszahlen (`earthquake 2`, `volcano 1`, `firestorm 2`,
  `flatten 3`, `sink 3`); kostensortierter Round-Robin lädt auch die neuen;
  `default_spell_entries` hat 10 Einträge mit gültigen Icon-Keys.
- **KI:** Schamanin + 2 Feindgebäude im Umkreis + Vulkan-Ladung → Vulkan-Cast
  (Ladung sinkt); großer Cluster + Feuerregen-Ladung → Feuerregen vor
  Feuerball; küstennahes Feindgebäude + Absinken-Ladung → Absinken-Cast.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Zauber-Tab zeigt 10 Slots mit Pips; Hotkeys 1–0 togglen die Zielmodi;
  Ebene-Zielmodus zeigt Quadrat-Vorschau.
- Erdbeben: Boden verwirft sich sichtbar/graduell, Gebäude brechen, Einheiten
  purzeln; Minimap aktualisiert die Höhenfarben.
- Vulkan: Berg wächst und BLEIBT; Lava-Zone schädigt alles im Umkreis;
  Gebäude unter dem Vulkan gehen kaputt.
- Feuerregen: Salve regnet über die Fläche, Trauben werden auseinandergeworfen.
- Ebene: Fläche schnappt schnell auf Zielhöhe, am Rand entstehen sichtbare
  Klippen (Quadrat); Einheiten werden hochgeworfen bzw. stürzen und rollen;
  Gebäude an der Kante zerplatzen sichtbar in umherfliegende Einzelteile.
- Absinken: Terrain senkt sich weich (sanfte Ränder), Berge lassen sich
  abtragen; an der Küste flutet Wasser das Land — Anhänger ertrinken sofort,
  angeflutete Gebäude rutschen ins Wasser und versinken.
- KI-Match (F10-Zeitraffer): Die KI castet die neuen Zauber sichtbar
  (Konsole/Beobachtung), Match konvergiert weiterhin.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] PROGRESS.md ergänzt, Checkbox 7c in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7c: Erdbeben, Vulkan, Feuerregen, Ebene, Absinken" && git push`
