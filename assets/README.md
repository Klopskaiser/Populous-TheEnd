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
│   ├── effects/                 # optional: panic.png, burning.png, injured.png (Status-Icons),
│   │                            #           splash.png (Spritzer auf dem Wasser)
│   └── spells/                  # optional: fireball.png, swarm.png, tornado.png, lava.png
└── audio/
    ├── music/*.ogg              # alle Dateien = Playlist (Loop)
    ├── ambience/*.ogg           # Umgebungs-Loops
    ├── sfx/combat/<kind>_<n>.ogg  # punch_0.ogg, punch_1.ogg, kick_0.ogg, shove_0.ogg,
    │                              # fireball_0.ogg, throw_0.ogg, preach_0.ogg — beliebig
    │                              # viele nummerierte Varianten ab _0, ohne Lücken
    ├── sfx/building_complete.ogg, building_destroyed.ogg, training_done.ogg, build_place.ogg
    ├── sfx/spell_voice_<id>.ogg # Zauberformel (Cast-Beginn) — Liste siehe Abschnitt Audio
    ├── sfx/spell_<id>.ogg       # Sound des Effekts (Einschlag/Ausbruch) — ebenda
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
├── dead_back.png dead_front.png  ← Leiche: Rücken- und Bauchlage (beide oder keine)
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
- **Blickrichtungen (Zeilen), drei erlaubte Varianten — Wahl gilt pro Datei:**

  | Zeile | 8-Zeilen-Sheet | 5-Zeilen-Sheet | 1-Zeilen-Sheet |
  |---|---|---|---|
  | 1 | front | front | **alle acht Richtungen** |
  | 2 | back | back | — |
  | 3 | right | right | — |
  | 4 | left | front_right | — |
  | 5 | front_right | back_right | — |
  | 6 | front_left | — | — |
  | 7 | back_right | — | — |
  | 8 | back_left | — | — |

  - **8 Zeilen = keine Spiegelung.** Alle acht Richtungen werden exakt so
    verwendet, wie sie gezeichnet sind — links darf sich also individuell von
    rechts unterscheiden (Schild-/Schwertseite!).
  - **5 Zeilen = Komfort-Variante:** left/front_left/back_left werden
    automatisch aus den rechten Ansichten gespiegelt.
  - **1 Zeile = blickrichtungslos:** dieselbe Zeichnung gilt für alle acht
    Richtungen, es wird **nichts gespiegelt**, und der Atlas legt die Frames nur
    **einmal** ab. Für Posen, deren Blickrichtung keine Aussage trägt.
  - Erkannt wird die Variante an der Bildhöhe (`Höhe / frame_height` = 8, 5 oder
    1); `walk.png` darf 8 Zeilen haben und `attack.png` gleichzeitig 5.
  - **Die liegenden Posen (`dead`, `airborne`) haben gar keine Zeilen-Auswahl:**
    sie sind grundsätzlich blickrichtungslos, jede Datei wird immer aus **Zeile 1**
    geschnitten (weitere Zeilen werden ignoriert). Siehe unten.
- **Frames (Spalten):** Anzahl = `Bildbreite / frame_width`, frei wählbar pro Animation.
- **Animationsnamen** (Dateiname = `<anim>.png`): `idle, walk, attack, punch, kick,
  shove, jump, carry, carry_walk, sit, roll, drown` — zusätzlich `cast` (nur
  Schamanin/Prediger), `throw` (nur Feuerkrieger) und die liegenden Posen
  `airborne`, `dead_back`, `dead_front` (siehe unten). Fehlt eine Datei, wird nur
  diese Animation prozedural dargestellt.
  - `roll` = Purzeln **am Boden**, `airborne` = Flug **durch die Luft** (Wurf,
    Tornado, Sturz vom Luftschiff) — bewusst zwei verschiedene Posen.
  - `roll` und `drown` bleiben bildschirmaufrecht und werden **nicht** gerollt.
  - `drown` = Ertrinken im Wasser. Die Figur wird an der Wasseroberfläche
    gezeigt und dann darunter gezogen; die untere Hälfte des Sprites wird von
    der undurchsichtigen Wasserfläche abgeschnitten, sollte also nicht die
    Bildaussage tragen.
- **fps** pro Animation optional im Manifest; sonst gelten die eingebauten Defaults.

### Die liegenden Posen: `dead_back`, `dead_front`, `airborne`

**Aufrecht zeichnen, das Spiel legt sie hin.** Kopf oben, Füße unten, volle
Zellhöhe — obwohl es *liegende* Posen sind. Der Renderer rollt sie zur Laufzeit
um **90° auf dem Bildschirm**, damit die **lange** Zellachse (die Höhe, z. B.
96 px = 1,44 m) zur Körperlänge wird und die Leiche so lang ist, wie die Figur
groß ist. Eine liegend gezeichnete Leiche würde im Spiel **senkrecht stehen** und
wäre außerdem nur 0,96 m lang. Der Roll ist **eine feste Richtung** (Kopf nach
rechts, `UnitRenderer.LIE_ROLL`).

**Keine Blickrichtungen, sondern Varianten.** Ein Körper am Boden oder in der
Luft hat keine Vorderseite, um die die Kamera laufen könnte. Deshalb hat jede
dieser Posen **eine Zeile pro Datei** (Spalten/Frames beliebig, es bleibt eine
Animation), und statt acht Ansichten gibt es benannte Varianten:

| Datei | Lage | Was du zeichnest |
|---|---|---|
| `dead_back.png` | Leiche auf dem **Rücken** | Ansicht von oben auf ihre **Vorderseite** — Gesicht sichtbar |
| `dead_front.png` | Leiche auf dem **Bauch** | Ansicht von oben auf ihren **Rücken** — Hinterkopf, kein Gesicht |
| `airborne.png` | Flug, immer **bauchwärts** | Ansicht von oben auf ihren **Rücken** — kein Gesicht |

> **Achtung, der Name meint die LAGE, nicht die sichtbare Seite** — anders als bei
> den Ansichtszeilen `front`/`back` der übrigen Sheets. `dead_back.png` liegt auf
> dem Rücken und zeigt deshalb ihr Gesicht.

- Welche der beiden Leichen-Varianten eine Einheit bekommt, wird **einmal je
  Einheit** gewürfelt: in **40 %** der Fälle die Bauchlage
  (`Balance.LIE_FACE_DOWN_CHANCE`). Ein geschleuderter Körper fällt immer
  bauchwärts, `airborne` hat deshalb nur eine Variante.
- **Beide Leichen-Dateien oder keine.** Fehlt eine, bleibt der Platzhalter für
  **beide** Lagen aktiv (sonst mischte eine Einheit Handarbeit und Platzhalter);
  die Konsole nennt dann die fehlende Datei.
- **fps im Manifest unter dem Animationsnamen** — also `"dead"`, nicht
  `"dead_back"`. Beide Varianten teilen sich die Rate.
- Optionale Stammesfarben-Masken heißen wie die Datei: `dead_back_mask.png`.

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
- **`burning.png` ist das spielweite Feuer:** brennende Einheiten und Bäume,
  **und** der Flammenkegel der Feuerramme nutzen dieselben Frames.
- `splash.png` — Spritzring auf der Wasseroberfläche über allem, was gerade im
  Meer versinkt (Einheiten, Fahrzeugwracks, geflutete Gebäude). Wird **flach
  liegend** von oben gesehen dargestellt, also von oben zeichnen.
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

- Format: **.ogg** (empfohlen) oder .wav (auch .mp3 wird gelesen).
- **Neue Sounddateien wirken sofort** — sie werden notfalls direkt von der Platte
  gelesen, auch wenn Godot sie noch nicht importiert hat. Ein Import (Editor
  öffnen oder `--headless --import`) bleibt trotzdem sinnvoll, weil dann die
  Import-Einstellungen der Datei gelten; **ohne** Import zählt nur die Datei
  selbst (eine Loop-Markierung in den Import-Einstellungen gibt es dann z. B.
  nicht — was für unsere Loops sogar erwünscht ist, siehe unten).
  Für **Grafiken und Modelle** gilt das NICHT: die brauchen den Import.
- `music/` und `ambience/`: alle Dateien im Ordner werden (alphabetisch sortiert)
  als Playlist geloopt — Dateinamen frei wählbar.
- Kampfsounds: nummerierte Varianten ab `_0` ohne Lücken (`punch_0.ogg, punch_1.ogg, …`);
  pro Treffer wird zufällig eine Variante gespielt.
- Fehlende Kampfsounds werden weiterhin synthetisiert; alle anderen fehlenden Sounds
  bleiben einfach stumm.

### Lautstärke und Entfernung

Vier Regler in den Optionen **und** im Pausenmenü, gespeichert in
`user://settings.cfg`: **Gesamt**, **Effekte** (Bus SFX), **Bedienung** (UI) und
**Musik & Umgebung** (Music + Ambience). 0 stummt den Kanal.

Welt-Sounds sind positioniert und werden mit dem Kamera-Abstand leiser: bis
**25 m** volle Lautstärke, danach invers abfallend, hörbar bis **120 m**
(Loops 100 m). Das ist auf den Kamera-Zoom geeicht (Boom 8-90 m, Start 45), damit
alles Sichtbare hörbar bleibt. **UI-Sounds sind nicht positioniert** und spielen
immer mit voller Lautstärke — deshalb wirken sie schnell zu präsent, wenn man
die Dateien laut normalisiert.

### Sound-Prioritäten

Es spielen nur begrenzt viele Sounds gleichzeitig (8 Slots für Welt-Sounds, 12
eigene für Kampftreffer). Wird es eng, entscheidet die Priorität, wer den Slot
bekommt (`scripts/core/audio_slots.gd`):

| Prio | Sounds | Verhalten |
|---|---|---|
| **1** | `spell_voice_*`, `shaman_death` | Verdrängen bei Bedarf laufende Sounds niedrigerer Priorität |
| **2** | `airship_death`, `siege_death_burn`, `siege_death_burst` | Verdrängen Prio 3 |
| **3** | alles Übrige | Wird als Erstes verworfen, wenn kein Slot frei ist |

Solange ein Slot frei ist, wird **nie** etwas verworfen — unabhängig von der
Priorität. Gleichrangige Sounds verdrängen sich erst, wenn das Opfer schon
250 ms läuft; Kampftreffer verdrängen sich gar nicht (eigener Pool).

### Selbsttest: „warum ist es still?"

Statt zu raten, fragt man die Engine. Der Selbsttest listet für **jeden** hier
dokumentierten Namen, was sie sieht — Datei da? importiert? dekodierbar? wie
lang? — plus die Verdrahtung (Busse, Pools):

```bash
godot --headless -s res://tests/diag_audio_assets.gd
godot --headless -s res://tests/diag_audio_assets.gd -- nur=fehlt
```

`nur=fehlt` zeigt ausschließlich die Namen, zu denen wirklich eine Datei liegt —
das ist die kurze Liste, wenn man gerade Assets nachträgt. „NICHT LESBAR" heißt:
die Datei ist da, aber weder Import noch Laufzeit-Dekoder kommen damit klar
(Godot liest WAV nur als PCM 8/16/24 Bit, IMA-ADPCM oder QOA, `.ogg` nur als
Vorbis).

### Vollständige Liste der einsetzbaren Sounds

> **Varianten überall erlaubt:** Jeder Sound-Name (sfx **und** ui) kann statt
> — oder zusätzlich zu — der Basisdatei nummerierte Varianten haben
> (`<name>_0.ogg`, `<name>_1.ogg`, … lückenlos ab `_0`). Pro Abspielen wird
> zufällig eine gewählt. Beispiel: `shaman_hurt_0.ogg` + `shaman_hurt_1.ogg`
> + `shaman_hurt_2.ogg` für abwechslungsreiche Schmerzlaute.
>
> Das gilt **auch für Loops**: dort wird bei **jeder Wiederholung** neu
> gewürfelt (nie zweimal dieselbe Datei direkt hintereinander, bei genau zwei
> Dateien wechseln sie sich also ab). Dafür müssen Loop-Dateien **ohne**
> Import-Loop geliefert werden — das Wiederholen macht der AudioManager, und ein
> intern loopender Stream würde für immer auf einer Variante hängen bleiben.

**Kampf** — `audio/sfx/combat/` (nummerierte Varianten, Fallback = Synthese):

| Datei(en) | Wird gespielt bei |
|---|---|
| `punch_0.ogg`, `punch_1.ogg`, … | Faustschlag (Nahkampf) |
| `kick_0.ogg`, … | Tritt (Nahkampf) |
| `shove_0.ogg`, … | Schubser (Nahkampf) |
| `fireball_0.ogg`, … | Feuerball-Einschlag |
| `throw_0.ogg`, … | Feuerball-Abschuss (Feuerkrieger) |
| `preach_0.ogg`, … | Prediger-Gesang (Bekehrung) — **eigener** Stamm |
| `preach_enemy_0.ogg`, … | Derselbe Gesang eines **gegnerischen** Predigers (Perspektive: Spieler; ein hypnotisierter Gegner-Prediger klingt solange „eigen") |

**Einheiten** — `audio/sfx/` (Fallback = stumm):

| Datei | Wird gespielt bei |
|---|---|
| `unit_panic.ogg` | Einheit gerät in Panik (Schwarm, Brand) — gedrosselt bei Massenpanik |
| `unit_injured.ogg` | Einheit (nicht Schamanin) fällt unter 25 % Leben (einmal pro Unterschreitung) |
| `unit_death.ogg` | Tod einer Einheit außer der Schamanin — gedrosselt bei Massensterben |
| `unit_burning.ogg` | Einheit fängt Feuer (Lava/Feuerzauber) |
| `water_splash.ogg` | Etwas schlägt im Wasser auf: ertrinkende Einheit, Fahrzeugwrack, ins Meer rutschendes Gebäude (max. alle 0,15 s) |
| `water_sink.ogg` | Dasselbe geht kurz darauf unter der Oberfläche verloren (Gluckern) |
| `shaman_hurt.ogg` | Schamanin erleidet Schaden (max. alle 1,2 s; mehrere Varianten empfohlen) |
| `shaman_death.ogg` | Tod der Schamanin |
| `unit_land.ogg` | Einheit landet nach Wurf/Sturz auf dem Boden und **überlebt** die Landung (späterer Rollschaden zählt nicht; max. alle 0,15 s) |
| `unit_air_death.ogg` | Einheit erleidet **in der Luft** tödlichen Schaden (auch vom Luftschiffdeck geschossene Besatzung) — der Tod selbst folgt beim Aufprall mit `unit_death.ogg` (max. alle 0,2 s) |

**Status-Loops** — `audio/sfx/` (laufen in Dauerschleife, **solange der Zustand
anhält**; max. 4 gleichzeitige Emitter pro Sound, weitere Einheiten rücken nach,
sobald ein Platz frei wird; Fallback = stumm):

| Datei | Läuft solange … |
|---|---|
| `unit_panic_loop.ogg` | … die Einheit in Panik ist |
| `unit_burning_loop.ogg` | … die Einheit/das Katapult brennt |
| `unit_injured_loop.ogg` | … die Einheit unter 25 % Leben ist |

> Auch Loops dürfen mehrere Varianten haben (`unit_burning_loop_0.ogg`,
> `_1.ogg`, …) — jede Wiederholung würfelt neu, siehe Varianten-Hinweis oben.

**Fahrzeuge** (Katapult, Feuerramme, Luftschiff) — `audio/sfx/` (Fallback siehe Tabelle):

| Datei | Wird gespielt bei |
|---|---|
| `siege_fire.ogg` | Katapult schießt (Fallback = synthetisches Wurfgeräusch) |
| `fireram_burst.ogg` | Feuerramme feuert einen Flammenstoß (Fallback = synthetisches Wurfgeräusch) |
| `siege_impact.ogg` | Katapult-Kugel schlägt ein (Fallback = stumm) |
| `siege_burning.ogg` | Katapult **oder** Feuerramme fängt durch eine externe Quelle Feuer (Zauber/Lava) — nicht der Angriff der Feuerramme selbst, siehe `fireram_burst.ogg` (Fallback = stumm) |
| `siege_death_burn.ogg` | Katapult/Feuerramme brennt aus und versinkt (Fallback = stumm) |
| `siege_death_burst.ogg` | Katapult/Feuerramme wird zerfetzt (Tornado, Terrainriss) (Fallback = stumm) |
| `airship_death.ogg` | Luftschiff explodiert (Fallback = stumm) |

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

**Zauber** — jeder Zauber hat **zwei** Sounds zu **zwei verschiedenen
Zeitpunkten**:

- `audio/sfx/spell_voice_<id>.ogg` — die **Zauberformel** der Schamanin. Startet
  beim **Beginn** des Zaubervorgangs (Wind-up, 1,0 s), an **ihrer** Position.
  Priorität 1 (siehe oben), wird also nie von Kampflärm verdrängt.
- `audio/sfx/spell_<id>.ogg` — der Sound des **Effekts selbst** (Donner,
  Einschlag, Ausbruch, mahlender Boden). Spielt erst, wenn der Effekt
  **tatsächlich eintritt** — bei Wurf-/Terrainzaubern also deutlich später als
  die Formel — und dort, wo er passiert.

Die zwölf gültigen IDs (aus `scripts/spells/*.gd`):

| Formel | Effekt | Zauber | Effekt spielt |
|---|---|---|---|
| `spell_voice_fireball.ogg` | `spell_fireball.ogg` | Feuerball | beim Einschlag (max. alle 60 ms) |
| `spell_voice_lightning.ogg` | `spell_lightning.ogg` | Blitz | je Blitzsäule (jeder Treffer) |
| `spell_voice_swarm.ogg` | `spell_swarm.ogg` | Insektenschwarm | wenn die Wolke erscheint |
| `spell_voice_landbridge.ogg` | `spell_landbridge.ogg` | Landbrücke | wenn sich der Boden zu heben beginnt |
| `spell_voice_tornado.ogg` | `spell_tornado.ogg` | Tornado | wenn der Trichter erscheint |
| `spell_voice_earthquake.ogg` | `spell_earthquake.ogg` | Erdbeben | wenn sich der Boden zu bewegen beginnt |
| `spell_voice_volcano.ogg` | `spell_volcano.ogg` | Vulkan | wenn sich der Kegel zu heben beginnt |
| `spell_voice_firestorm.ogg` | `spell_firestorm.ogg` | Feuerregen | beim ersten Geschoss der Salve |
| `spell_voice_flatten.ogg` | `spell_flatten.ogg` | Ebene | wenn sich der Boden zu bewegen beginnt |
| `spell_voice_sink.ogg` | `spell_sink.ogg` | Absinken | wenn sich der Boden zu senken beginnt |
| `spell_voice_supertornado.ogg` | `spell_supertornado.ogg` | Supertornado | wenn der Haupttrichter erscheint |
| `spell_voice_hypnosis.ogg` | `spell_hypnosis.ogg` | Hypnose | im Moment der Übernahme (nur wenn wirklich jemand übernommen wird) |

**Zusatzsounds der Zauber** — `audio/sfx/` (Fallback = stumm):

| Datei | Wird gespielt bei |
|---|---|
| `spell_tornado_loop.ogg` | Heulen, folgt dem Tornado, solange er steht (Dauerschleife) |
| `spell_supertornado_loop.ogg` | Dasselbe für den Haupttrichter des Supertornados (die 2 Satelliten bleiben stumm) |
| `spell_swarm_loop.ogg` | Summen, folgt der Schwarmwolke (Dauerschleife) |
| `spell_volcano_erupt.ogg` | Ein Ausbruch des Vulkans (einer je Lavastoß) |
| `lava_start.ogg` | Lava tritt aus — jede Quelle (Vulkan, Erdbeben-Verwerfung, Katapult-Pfütze), max. alle 0,25 s |

> Fehlt eine `*_loop.ogg`, greift automatisch der gleichnamige Einzelsound ohne
> `_loop` und wird wiederholt.

**UI** — `audio/ui/` (Fallback = stumm; je Auswahl-/Befehlsvorgang genau EIN Sound,
auch bei vielen Einheiten):

| Datei | Wird gespielt bei |
|---|---|
| `select_unit.ogg` | Einheiten selektiert (ohne Schamanin) |
| `select_shaman.ogg` | Auswahl enthält die Schamanin |
| `select_building.ogg` | Gebäude selektiert |
| `move_unit.ogg` | Move-Befehl an Einheiten (ohne Schamanin) |
| `move_shaman.ogg` | Move-Befehl an eine Gruppe mit Schamanin |
| `move_blocked.ogg` | Move-Befehl auf ein unerreichbares Ziel (abgelehnt) |
| `click.ogg` | *(reserviert — noch an keinen Button angebunden)* |

## Export-Builds (Notiz für später)

Beim Einrichten eines Export-Presets muss `*.json` in die Include-Filter aufgenommen
werden, damit die `manifest.json`-Dateien mitkommen.
