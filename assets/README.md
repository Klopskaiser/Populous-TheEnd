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
    ├── sfx/spell_<id>.ogg       # z. B. spell_fireball.ogg, spell_lightning.ogg
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
- **Maßstab:** 1 Godot-Einheit = 1 m; das Modell muss in den Gebäude-Footprint passen
  (Hütte 4×4, Kaserne 5×5, Tempel 6×6, Feuertempel 8×8, Wachturm 2×2 …).
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
- `music/` und `ambience/`: alle Dateien im Ordner werden als Playlist geloopt.
- Kampfsounds: nummerierte Varianten ab `_0` ohne Lücken (`punch_0.ogg, punch_1.ogg, …`);
  pro Treffer wird zufällig eine Variante gespielt.
- Fehlende Kampfsounds werden weiterhin synthetisiert; alle anderen fehlenden Sounds
  bleiben einfach stumm.

## Export-Builds (Notiz für später)

Beim Einrichten eines Export-Presets muss `*.json` in die Include-Filter aufgenommen
werden, damit die `manifest.json`-Dateien mitkommen.
