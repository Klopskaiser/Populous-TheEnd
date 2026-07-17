# Asset-Konventionen

Alle Spielinhalte funktionieren auch **ohne** Dateien in diesem Ordner — dann greifen die
prozeduralen Platzhalter. Jede hier abgelegte Datei ersetzt automatisch den entsprechenden
Platzhalter. Assets können stückweise geliefert werden (z. B. nur `walk.png` für den Brave).

> ⚠️ **Nach jedem Hinzufügen/Ändern von Dateien:** einmal
> `Godot --headless --import` ausführen (oder den Editor öffnen). Ohne Import sieht das
> Spiel die Datei nicht und fällt still auf den Platzhalter zurück (es erscheint eine
> Warnung auf der Konsole).

## Ordnerstruktur

```
assets/
├── units/<kind>/                # brave | warrior | firewarrior | preacher | shaman
│   ├── manifest.json            # PFLICHT bei Sheets: Framegröße; fps optional
│   ├── <anim>.png               # Spritesheet pro Animation (s. u.)
│   └── <anim>_mask.png          # optional: Graustufen-Maske für die Stammesfarbe
├── models/
│   ├── buildings/<kind>.glb     # hut | warrior_camp | firewarrior_camp | temple |
│   │                            # forester | workshop | watchtower | reincarnation_site
│   ├── buildings/<kind>_stage<1..3>.glb   # optional: Zerstörungsstufen (später)
│   ├── units/siege_engine.glb   # Katapult
│   └── trees/tree.glb
├── textures/
│   ├── terrain/                 # sand.png, grass.png, rock.png, water.png (water optional)
│   └── spells/                  # optional: fireball.png, swarm.png, tornado.png, lava.png
└── audio/
    ├── music/*.ogg              # alle Dateien = Playlist (Loop)
    ├── ambience/*.ogg           # Umgebungs-Loops
    ├── sfx/combat/<kind>_<n>.ogg  # punch_0.ogg, punch_1.ogg, kick_0.ogg, shove_0.ogg,
    │                              # fireball_0.ogg, throw_0.ogg, preach_0.ogg — beliebig
    │                              # viele nummerierte Varianten ab _0, ohne Lücken
    ├── sfx/building_complete.ogg, building_destroyed.ogg, training_done.ogg, build_place.ogg
    ├── sfx/spell_<id>.ogg       # vollständige Liste siehe Abschnitt Audio
    └── ui/select_unit.ogg, select_building.ogg, click.ogg
```

## Einheiten-Spritesheets

**Eine PNG pro Animation.** Layout: **Zeilen = Blickrichtungen, Spalten = Frames.**

- **Framegröße:** einheitlich pro Einheit, angegeben in `manifest.json`
  (`frame_width`/`frame_height`). Empfohlener Standard: **64×96 px**.
  **Hard Cap: 64×96** — größere Frames sprengen das Textur-Atlas-Budget.
- **Blickrichtungen (Zeilen), zwei erlaubte Varianten:**
  - **8 Zeilen** in dieser Reihenfolge: `front, back, right, left, front_right,
    front_left, back_right, back_left`
  - **5 Zeilen**: `front, back, right, front_right, back_right` — die linken
    Ansichten werden automatisch gespiegelt.
  Die Zeilenzahl wird aus `Bildhöhe / frame_height` erkannt.
- **Frames (Spalten):** Anzahl = `Bildbreite / frame_width`, frei wählbar pro Animation.
- **Animationsnamen** (Dateiname = `<anim>.png`): `idle, walk, attack, punch, kick,
  shove, jump, carry, carry_walk, dead, sit, roll` — zusätzlich `cast` (nur Schamanin/
  Prediger) und `throw` (nur Feuerkrieger). Fehlt eine Datei, wird nur diese Animation
  prozedural dargestellt.
- **fps** pro Animation optional im Manifest; sonst gelten die eingebauten Defaults.

`manifest.json`-Beispiel:

```json
{
  "frame_width": 64,
  "frame_height": 96,
  "anims": { "walk": { "fps": 8 }, "attack": { "fps": 10 } }
}
```

**Stammesfarbe:** Die Sprites dürfen voll koloriert sein. Bereiche, die die Stammesfarbe
annehmen sollen (Kleidung, Federn, Kriegsbemalung), werden in `<anim>_mask.png`
weiß markiert (gleiche Größe/Layout wie das Sheet; schwarz = keine Färbung, Graustufen =
teilweise). Ohne Maske wird das ganze Sprite mit der Stammesfarbe multipliziert —
dann sollte die Art hell/fast weiß angelegt sein.

**Import-Hinweis:** Unit-Sheets beim Godot-Standardimport (Lossless) belassen — keine
VRAM-Kompression einstellen.

## 3D-Modelle (.glb)

- **Ursprung:** am Boden, mittig im Footprint des Gebäudes.
- **Ausrichtung:** Eingang zeigt Richtung **+Z (Süden)** — die Drehung aufs Gelände
  übernimmt das Spiel.
- **Maßstab:** 1 Godot-Einheit = 1 m; das Modell muss in den Gebäude-Footprint passen:
  Hütte (`hut`) 4×4, Kaserne (`warrior_camp`) 5×5, Feuertempel (`firewarrior_camp`) 8×8,
  Tempel (`temple`) 6×6, Förster (`forester`) 3×3, Werkstatt (`workshop`) 8×4 (breit×tief),
  Wachturm (`watchtower`) 2×2, Reinkarnationsplatz (`reincarnation_site`) 3×3.
- **Stammesfarbe:** Ein `MeshInstance3D` mit dem Namen `Flag` im Modell wird automatisch
  in der Stammesfarbe eingefärbt (gilt auch für `siege_engine.glb`).
- **Katapult-Extras (`siege_engine.glb`):** Ein optionaler Node namens `Arm` wird beim
  Feuern als Wurfarm-Pivot animiert (Drehung um X, Ruheposition = gespannt).
- Bau-Animation (Wachsen aus dem Boden) und Beschädigungs-Optik übernimmt das Spiel.

## Terrain-Texturen

`sand.png`, `grass.png`, `rock.png` — kachelbare (seamless) Texturen. Sobald alle drei
vorhanden sind, schaltet das Terrain auf den Textur-Shader um (Blending nach Höhe und
Hangneigung); sonst bleibt die bisherige Vertex-Färbung. `water.png` ist optional und
wird auf die Wasserfläche gekachelt. VRAM-Kompression (Godot-Default für 3D) ist hier
richtig und erwünscht.

## Audio

- Format: **.ogg** (empfohlen) oder .wav.
- `music/` und `ambience/`: alle Dateien im Ordner werden (alphabetisch sortiert)
  als Playlist geloopt — Dateinamen frei wählbar.
- Kampfsounds: nummerierte Varianten ab `_0` ohne Lücken (`punch_0.ogg, punch_1.ogg, …`);
  pro Treffer wird zufällig eine Variante gespielt.
- Fehlende Kampfsounds werden weiterhin synthetisiert; alle anderen fehlenden Sounds
  bleiben einfach stumm.

### Vollständige Liste der einsetzbaren Sounds

**Kampf** — `audio/sfx/combat/` (nummerierte Varianten, Fallback = Synthese):

| Datei(en) | Wird gespielt bei |
|---|---|
| `punch_0.ogg`, `punch_1.ogg`, … | Faustschlag (Nahkampf) |
| `kick_0.ogg`, … | Tritt (Nahkampf) |
| `shove_0.ogg`, … | Schubser (Nahkampf) |
| `fireball_0.ogg`, … | Feuerball-Einschlag |
| `throw_0.ogg`, … | Feuerball-Abschuss (Feuerkrieger) |
| `preach_0.ogg`, … | Prediger-Gesang (Bekehrung) |

**Einheiten** — `audio/sfx/` (Fallback = stumm):

| Datei | Wird gespielt bei |
|---|---|
| `unit_panic.ogg` | Einheit gerät in Panik (Schwarm, Brand) — gedrosselt bei Massenpanik |
| `unit_injured.ogg` | Einheit (nicht Schamanin) fällt unter 25 % Leben (einmal pro Unterschreitung) |
| `unit_death.ogg` | Tod einer Einheit außer der Schamanin — gedrosselt bei Massensterben |
| `unit_burning.ogg` | Einheit fängt Feuer (Lava/Feuerzauber) |
| `shaman_hurt.ogg` | Schamanin erleidet Schaden (max. alle 0,8 s) |
| `shaman_death.ogg` | Tod der Schamanin |

**Katapult** — `audio/sfx/` (Fallback siehe Tabelle):

| Datei | Wird gespielt bei |
|---|---|
| `siege_fire.ogg` | Katapult schießt (ohne Datei ertönt das bisherige synthetische Wurfgeräusch) |
| `siege_impact.ogg` | Katapult-Kugel schlägt ein (Fallback = stumm) |
| `siege_burning.ogg` | Katapult fängt Feuer (Fallback = stumm) |

**Gebäude & Ereignisse** — `audio/sfx/` (Fallback = stumm):

| Datei | Wird gespielt bei |
|---|---|
| `build_place.ogg` | Bauplatz gesetzt (Baustart) |
| `building_complete.ogg` | Gebäude fertiggestellt |
| `building_attack_melee.ogg` | Gebäude wird im Nahkampf abgerissen (max. **ein** Sound pro Gebäude alle 2,5 s, egal wie viele Angreifer) |
| `building_attack_ranged.ogg` | Gebäude wird von Fernkampf getroffen (pro Gebäude gedrosselt, alle 1,5 s) |
| `building_damaged.ogg` | Gebäude erreicht eine höhere Zerstörungsstufe (30/60/90 %) |
| `building_destroyed.ogg` | Gebäude zerstört |
| `training_done.ogg` | Einheit fertig ausgebildet |

> Hinweis: Einen Brand-Sound für **Gebäude** gibt es nicht — Gebäude haben
> (anders als Einheiten, Katapulte und Bäume) keinen Brand-Zustand, nur
> Zerstörungsstufen.

**Umwelt** — `audio/sfx/` (Fallback = stumm):

| Datei | Wird gespielt bei |
|---|---|
| `tree_burning.ogg` | Baum fängt Feuer |
| `wood_chop.ogg` | Brave erntet Holz von einem Baum (gedrosselt) |

**Zauber** — `audio/sfx/spell_<id>.ogg`, gespielt beim erfolgreichen Wirken.
Die zehn gültigen IDs (aus `scripts/spells/*.gd`):

| Datei | Zauber |
|---|---|
| `spell_fireball.ogg` | Feuerball |
| `spell_lightning.ogg` | Blitz |
| `spell_swarm.ogg` | Insektenschwarm |
| `spell_landbridge.ogg` | Landbrücke |
| `spell_tornado.ogg` | Tornado |
| `spell_earthquake.ogg` | Erdbeben |
| `spell_volcano.ogg` | Vulkan |
| `spell_firestorm.ogg` | Feuerregen |
| `spell_flatten.ogg` | Ebene |
| `spell_sink.ogg` | Absinken |

**UI** — `audio/ui/` (Fallback = stumm; je Auswahl-/Befehlsvorgang genau EIN Sound,
auch bei vielen Einheiten):

| Datei | Wird gespielt bei |
|---|---|
| `select_unit.ogg` | Einheiten selektiert (ohne Schamanin) |
| `select_shaman.ogg` | Auswahl enthält die Schamanin |
| `select_building.ogg` | Gebäude selektiert |
| `move_unit.ogg` | Move-Befehl an Einheiten (ohne Schamanin) |
| `move_shaman.ogg` | Move-Befehl an eine Gruppe mit Schamanin |
| `click.ogg` | *(reserviert — noch an keinen Button angebunden)* |

## Export-Builds (Notiz für später)

Beim Einrichten eines Export-Presets muss `*.json` in die Include-Filter aufgenommen
werden, damit die `manifest.json`-Dateien mitkommen.
