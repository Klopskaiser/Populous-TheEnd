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
│   ├── effects/                 # optional: panic.png, burning.png, injured.png (Status-Icons)
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

## Beispiele: konkrete Dateibäume

Drei kopierfertige Beispiele — je eine Asset-Art: **Gebäudemodell** (Hütte),
**Einheiten-Sprites** (Brave), **Zaubereffekt** (Wirbelsturm). Details zu den einzelnen
Regeln stehen weiter unten in den jeweiligen Abschnitten.

**1. Hütte — 3D-Gebäudemodell**

```
assets/models/buildings/
└── hut.glb                     ← Basismodell, Footprint 4×4, Eingang → +Z

assets/textures/buildings/      ← alles optional (Textur-Tausch auf hut.glb)
├── hut_build1.png … hut_build4.png   ← 4 Baustadien
└── hut_stage1.png … hut_stage3.png   ← Zerstörung ab 30 / 60 / 90 %
```

Ohne die Texturen: Bauen = Wachsen aus dem Boden, Schaden = prozedurale Bruchstücke.

**2. Brave — Einheiten-Sprites**

```
assets/units/brave/
├── manifest.json               ← Pflicht bei Sheets (frame_width/-height)
├── idle.png  walk.png  attack.png
├── carry.png carry_walk.png    ← Brave trägt Holz
├── dead.png
└── walk_mask.png               ← optional: Stammesfarben-Maske je Sheet
```

Einzelne Sheets reichen; fehlende Animationen bleiben Platzhalter.

**3. Wirbelsturm — Zaubereffekt**

```
assets/audio/sfx/
└── spell_tornado.ogg           ← Wirk-Sound (einziges austauschbares Asset)
```

Der Wirbel selbst wird **prozedural** gezeichnet — kein Modell/Sprite nötig.

## Einheiten-Spritesheets

**Die Einheit bestimmt der Ordner, die Animation der Dateiname:**
`assets/units/<einheit>/<animation>.png` — eine PNG pro Animation.
`<einheit>` ist `brave`, `warrior`, `firewarrior`, `preacher` oder `shaman`.
Layout innerhalb der PNG: **Zeilen = Blickrichtungen, Spalten = Frames.**

### Beispiel: Krieger mit Lauf-Animation (6 Frames à 64×96 px)

```
assets/units/warrior/
├── manifest.json     ← Pflicht, sobald Sheets vorhanden sind
└── walk.png          ← 384×768 px = 6 Spalten (Frames) × 8 Zeilen (Richtungen)
```

`manifest.json`:

```json
{
  "frame_width": 64,
  "frame_height": 96,
  "anims": { "walk": { "fps": 8 }, "attack": { "fps": 10 } }
}
```

Nur `walk.png` vorhanden? Dann läuft der Krieger mit dem eigenen Sprite und
nutzt für alle übrigen Animationen weiter den Platzhalter — Animationen können
einzeln nachgeliefert werden.

### Regeln

- **Framegröße:** einheitlich pro Einheit, angegeben in `manifest.json`
  (`frame_width`/`frame_height`). Empfohlener Standard: **64×96 px**.
  **Hard Cap: 64×96** — größere Frames sprengen das Textur-Atlas-Budget.
- **Blickrichtungen (Zeilen), zwei erlaubte Varianten — Wahl gilt pro Datei:**

  | Zeile | 8-Zeilen-Sheet | 5-Zeilen-Sheet |
  |---|---|---|
  | 1 | front | front |
  | 2 | back | back |
  | 3 | right | right |
  | 4 | left | front_right |
  | 5 | front_right | back_right |
  | 6 | front_left | — |
  | 7 | back_right | — |
  | 8 | back_left | — |

  - **8 Zeilen = keine Spiegelung.** Alle acht Richtungen werden exakt so
    verwendet, wie sie gezeichnet sind — links darf sich also individuell von
    rechts unterscheiden (Schild-/Schwertseite!).
  - **5 Zeilen = Komfort-Variante:** left/front_left/back_left werden
    automatisch aus den rechten Ansichten gespiegelt.
  - Erkannt wird die Variante an der Bildhöhe (`Höhe / frame_height` = 8 oder 5);
    `walk.png` darf 8 Zeilen haben und `dead.png` gleichzeitig 5.
- **Frames (Spalten):** Anzahl = `Bildbreite / frame_width`, frei wählbar pro Animation.
- **Animationsnamen** (Dateiname = `<anim>.png`): `idle, walk, attack, punch, kick,
  shove, jump, carry, carry_walk, dead, sit, roll` — zusätzlich `cast` (nur Schamanin/
  Prediger) und `throw` (nur Feuerkrieger). Fehlt eine Datei, wird nur diese Animation
  prozedural dargestellt.
- **fps** pro Animation optional im Manifest; sonst gelten die eingebauten Defaults.

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
- **Bau-/Zerstörungs-Optik:** Ohne die unten genannten Stufen-Texturen übernimmt das Spiel
  die prozedurale Optik (Bau = Wachsen aus dem Boden, Schaden = dunkle Bruchstücke).

## Bau-/Zerstörungs-Stufentexturen (`textures/buildings/`)

Optionaler Textur-Tausch auf dem **gemeinsamen Basismodell** `<kind>.glb`. Die Texturen
müssen auf dessen UV-Layout gemappt sein; sie werden auf **allen** Modellflächen (außer
`Flag`) als Albedo ausgetauscht. **Alpha wird als Alpha-Scissor gerendert** (harte Kante,
Schwellwert 0,5): vollständig transparente Bereiche werden zu Löchern (fehlende Wand/Dach).
Alles optional — fehlt eine Textur, greift automatisch der prozedurale Fallback.

- **Zerstörung:** `<kind>_stage1.png`, `<kind>_stage2.png`, `<kind>_stage3.png`
  (ab 30 % / 60 % / 90 % Schaden; Stufe 0 = die im Modell eingebackene Standard-Textur).
- **Bau:** `<kind>_build1.png` … `<kind>_build4.png` (vier Baustadien über den Fortschritt;
  fertig = Standard-Textur). Ist mindestens `_build1.png` vorhanden, entfällt das Wachsen
  aus dem Boden zugunsten des Textur-Tauschs.

## Abfall-Effekt (`textures/fx/`)

- `building_flake.png` — optionales alpha-fähiges Quad für die Bruchstücke, die bei jedem
  Erreichen einer neuen Zerstörungsstufe ums Gebäude abfallen. Als Billboard mit
  Alpha-Scissor (Schwellwert 0,5) und in einer neutralen Bauteilfarbe getönt gerendert.
  Fehlt die Datei, werden einfache getönte Box-Fragmente verwendet.

## Status-Effekt-Icons (`textures/effects/`)

Über Einheiten mit anhaltendem Zustand schwebt ein animiertes Icon: **Panik**
(rotes Ausrufezeichen) und **Brennen** (Flamme auf dem Körper). **Brennen hat
Anzeige-Priorität** und überdeckt alle anderen Zustands-Icons. **Kritischer
Schaden** (unter 25 % Leben) wird mit den klassischen kreisenden Sternen
dargestellt (nicht ersetzbar). Die Pixel-Icons lassen sich pro Effekt ersetzen:

- `panic.png`, `burning.png`
- Format: ein einzelnes Bild **oder** ein horizontaler Streifen **quadratischer**
  Frames (Framezahl = Breite ÷ Höhe), abgespielt als Loop (~6,7 fps).
- Transparenter Hintergrund (Alpha), Lossless-Import belassen.

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

> **Varianten überall erlaubt:** Jeder Sound-Name (sfx **und** ui) kann statt
> — oder zusätzlich zu — der Basisdatei nummerierte Varianten haben
> (`<name>_0.ogg`, `<name>_1.ogg`, … lückenlos ab `_0`). Pro Abspielen wird
> zufällig eine gewählt. Beispiel: `shaman_hurt_0.ogg` + `shaman_hurt_1.ogg`
> + `shaman_hurt_2.ogg` für abwechslungsreiche Schmerzlaute.

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
| `shaman_hurt.ogg` | Schamanin erleidet Schaden (max. alle 1,2 s; mehrere Varianten empfohlen) |
| `shaman_death.ogg` | Tod der Schamanin |

**Status-Loops** — `audio/sfx/` (laufen in Dauerschleife, **solange der Zustand
anhält**; max. 4 gleichzeitige Emitter pro Sound, weitere Einheiten rücken nach,
sobald ein Platz frei wird; Fallback = stumm):

| Datei | Läuft solange … |
|---|---|
| `unit_panic_loop.ogg` | … die Einheit in Panik ist |
| `unit_burning_loop.ogg` | … die Einheit/das Katapult brennt |
| `unit_injured_loop.ogg` | … die Einheit unter 25 % Leben ist |

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
