# Phase 7c — Neue Zauber: Erdbeben, Vulkan, Feuerregen

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Drei neue Kampfzauber im bestehenden Ladungssystem: **Erdbeben**
(Flächen-Terrainverwerfung + Gebäudeschaden), **Vulkan** (permanenter
Terrain-Kegel + Lava-Schadenszone) und **Feuerregen** (Feuerball-Salve über
eine Fläche). Zauberleiste wächst auf 8 Slots, die KI nutzt die neuen Zauber
situativ.

## Voraussetzungen

Phase 6: komplettes Spell-Framework — `Spell`-Basisklasse (`charge_cost`,
`max_charges`, `cast_range`, `execute`), `SpellContext`
(`apply_terrain_change` = NavGrid-Update + `terrain_deformed`),
Ladungs-Round-Robin in `Tribe`, `SpellTargeting`-Zielmodus, Schamanin-Cast-Flow.
Wiederverwendbare Vorlagen: [landbridge_morph.gd](../scripts/spells/landbridge_morph.gd)
(graduelle Terrainverformung über Schritte), [fireball_bolt.gd](../scripts/spells/fireball_bolt.gd)
(Parabel-Projektil + AoE + Wegschleudern), [tornado_vortex.gd](../scripts/spells/tornado_vortex.gd)
/ [swarm_cloud.gd](../scripts/spells/swarm_cloud.gd) (Lebenszeit-Entitäten über
die Projektil-Liste).

## Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/spells/earthquake.gd` | **Erdbeben** (`id = &"earthquake"`). Startwerte: `charge_cost 80`, `max_charges 2`, `cast_range 10`. Effekt im Radius ~7 m um den Zielpunkt: **Terrainverwerfung** — deterministisch zufällige Vertex-Deltas (±1,5 m, Falloff zum Rand, Seed aus Zielzelle), **graduell über ~2 s** nach dem `LandbridgeMorph`-Muster (eigene Morph-Entität oder LandbridgeMorph verallgemeinern: Ziel-Höhenkarte statt Linienprofil). Gebäude im Radius: **+2 Zerstörungsstufen** (Baustellen sterben sofort, bestehende Fragil-Regel). Einheiten im Radius: **Mini-Rolle** (`start_roll`, Richtung vom Epizentrum weg) + leichter Schaden (¼ Brave-Leben). Wasser-Klemme wie Landbrücke (nie unter `SEA_LEVEL + 1,2` heben — Senken unter die Seelinie sind ERLAUBT und fluten Land: taktische Terrainzerstörung). Nav-Update über `ctx.apply_terrain_change(rect)` |
| `scripts/spells/volcano.gd` + `scripts/spells/volcano_zone.gd` | **Vulkan** (`id = &"volcano"`). Startwerte: `charge_cost 120`, `max_charges 1`, `cast_range 12`. Effekt: **Kegel-Anhebung** (+6 m Spitze, Radius ~5 m, `TerrainData.raise_area`, graduell über ~3 s) — **bleibt permanent** als Berg (Spitze/Steilhang unbegehbar = gewollt). Dazu `VolcanoZone` (Lebenszeit-Entität über `register_projectile`, Muster `swarm_cloud`): **20 s Lava** — Feinde UND eigene Einheiten im Radius 5 m nehmen 10 Schaden/s (Lava kennt keine Freunde; dokumentierte Auslegung), Gebäude im Radius **+1 Stufe alle 4 s**. Visual: orangefarbene Partikel-/Mesh-Placeholder nur in `_ready` (headless-sicher) |
| `scripts/spells/firestorm.gd` | **Feuerregen** (`id = &"firestorm"`). Startwerte: `charge_cost 70`, `max_charges 3`, `cast_range 10`. Effekt: **8 Feuerbälle** über 3 s zeitversetzt auf deterministisch gestreute Punkte im Radius 4 m um den Zielpunkt — `FireballBolt` unverändert wiederverwenden (gleicher Direkt-/Flächenschaden + Wegschleudern je Einschlag, Attacker = Schamanin). Eigene Scheduler-Entität über die Projektil-Liste (spawnt die Bolts über Zeit) |
| `Spell.create_default_set()` | Um die 3 neuen Zauber ergänzt (Round-Robin/Kostensortierung skaliert automatisch; Startladung-1-Regel aus `main.gd` gilt mit) |
| UI: 8 Zauber-Slots | `Sidebar.default_spell_entries()` + `set_spell_state`-Verdrahtung um 3 Einträge; neue 24×24-Icons in `ui_theme.gd` (`earthquake`/`volcano`/`firestorm`); Input-Actions `cast_spell_6..8` (Tasten 6–8) in `project.godot`; `SpellTargeting`-Hotkey-Liste erweitern. Layout: Zauber-Tab muss 8 Zellen fassen (ggf. 2 Spalten/kleinere Pips — Sidebar ist 260 px breit) |
| KI-Heuristik | `AIController._cast_spells`-Prioritäten erweitern: **Feuerregen** statt Feuerball ab großem Cluster (≥ 5 Feinde), **Vulkan** auf Gebäudegruppen (≥ 2 Feindgebäude im 5-m-Umkreis des Ziels), **Erdbeben** als Gebäude-Fallback vor dem Blitz. Ein Cast/Tick, Durchfallen ohne Ladung wie bisher |
| `tests/test_spells.gd` (erweitert) | siehe Tests |

## Umsetzungsschritte

1. Erdbeben (Terrainverwerfung graduell + Gebäude/Einheiten-Effekt) + Tests grün.
2. Vulkan (Kegel + `VolcanoZone`) + Tests grün.
3. Feuerregen (Bolt-Scheduler) + Tests grün.
4. `create_default_set` + UI (8 Slots, Icons, Hotkeys 6–8, Zielmodus).
5. KI-Heuristik erweitern (+ Test).
6. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_spells.gd`)

- **Erdbeben:** Höhen im Radius nach Morph-Ende verändert (mind. ein Vertex ±),
  außerhalb unverändert; Gebäude im Radius +2 Stufen, außerhalb 0; Einheit im
  Radius nimmt Schaden/rollt; Cast verbraucht genau 1 Ladung; Wasser-Klemme.
- **Vulkan:** Kegelspitze ≥ Zielhöhe +5 nach Morph; Zone schädigt Feind UND
  eigene Einheit; Gebäude +1 Stufe nach 4 s Kontakt; Zone despawnt nach 20 s;
  Berg bleibt (Höhe nach Despawn unverändert).
- **Feuerregen:** Über die Laufzeit entstehen 8 Bolts (Projektil-Liste);
  Einschläge verteilen sich im 4-m-Radius; Gesamtschaden an einer Traube > ein
  Einzelfeuerball; 1 Ladung pro Cast.
- **Set/UI-Logik:** `create_default_set` liefert 8 Zauber, kostensortierter
  Round-Robin lädt auch die neuen; `default_spell_entries` hat 8 Einträge mit
  gültigen Icon-Keys.
- **KI:** Schamanin + 2 Feindgebäude im Umkreis + Vulkan-Ladung → Vulkan-Cast
  (Ladung sinkt); großer Cluster + Feuerregen-Ladung → Feuerregen vor Feuerball.

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

## Manuelle Prüfung

- Zauber-Tab zeigt 8 Slots mit Pips; Hotkeys 1–8 togglen die Zielmodi.
- Erdbeben: Boden verwirft sich sichtbar/graduell, Gebäude brechen, Einheiten
  purzeln; Minimap aktualisiert die Höhenfarben.
- Vulkan: Berg wächst und BLEIBT; Lava-Zone schädigt alles im Umkreis;
  Gebäude unter dem Vulkan gehen kaputt.
- Feuerregen: Salve regnet über die Fläche, Trauben werden auseinandergeworfen.
- KI-Match (F10-Zeitraffer): Die KI castet die neuen Zauber sichtbar
  (Konsole/Beobachtung), Match konvergiert weiterhin.

## Definition of Done

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuelle Prüfung bestanden
- [ ] PROGRESS.md ergänzt, Checkbox 7c in [00_overview.md](00_overview.md) abgehakt
- [ ] `git add -A && git commit -m "Phase 7c: Erdbeben, Vulkan, Feuerregen" && git push`
