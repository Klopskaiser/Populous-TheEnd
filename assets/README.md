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
│   ├── buildings/<kind>.glb     # hut hut1 hut2 hut3 hut4 | warrior_camp | firewarrior_camp |
│   │                            # temple | forester | workshop | fireram_workshop |
│   │                            # airship_wharf | watchtower | wood_depot | reincarnation_site
│   ├── units/<kind>.glb         # siege_engine | fire_ram | airship | golem  (Fahrzeuge + Golem;
│   │                            # alle anderen Fußeinheiten sind Sprites, s. units/)
│   └── trees/<kind>.glb         # tree | tree_leaf | tree_bamboo
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
- **Animationsnamen** (Dateiname = `<anim>.png`): `idle, stand, walk, attack, punch,
  kick, shove, jump, carry, carry_walk, sit, roll, drown` — zusätzlich `cast` (nur
  Schamanin/Prediger), `throw` (nur Feuerkrieger) und die liegenden Posen
  `airborne`, `dead_back`, `dead_front` (siehe unten). Fehlt eine Datei, wird nur
  diese Animation prozedural dargestellt.
  - `stand` = die **Ruhepose**, siehe eigener Abschnitt unten. Sie ist die einzige
    Datei, deren Fehlen **nicht** zum Platzhalter führt.
  - `roll` = Purzeln **am Boden**, `airborne` = Flug **durch die Luft** (Wurf,
    Tornado, Sturz vom Luftschiff) — bewusst zwei verschiedene Posen.
  - `roll` und `drown` bleiben bildschirmaufrecht und werden **nicht** gerollt.
  - `drown` = Ertrinken im Wasser. Die Figur wird an der Wasseroberfläche
    gezeigt und dann darunter gezogen; die untere Hälfte des Sprites wird von
    der undurchsichtigen Wasserfläche abgeschnitten, sollte also nicht die
    Bildaussage tragen.
- **fps** pro Animation optional im Manifest; sonst gelten die eingebauten Defaults.

### Die Ruhepose: `stand.png`

**Eine Spalte, sonst wie jedes andere Sheet** (8, 5 oder 1 Zeile — die Zeilen sind
Blickrichtungen wie oben). Das ist der Frame, den eine herumstehende Einheit die
**meiste Zeit** zeigt: die Idle-Animation läuft nicht mehr in Dauerschleife, sondern
im Schnitt alle 8 s **einmal** aus dieser Pose heraus und wieder in sie zurück
(`Balance.UNIT_IDLE_ANIM_INTERVAL`; hunderte dauernd wippende Figuren machten das
Spielbild unruhig). Zeichne `idle.png` deshalb so, dass es in der Ruhepose
**beginnt und endet** — sonst springt die Figur beim Übergang.

- **`stand.png` ist optional.** Fehlt es, ruht die Einheit auf **Frame 1 ihres
  eigenen `idle.png`**. Es ist damit die einzige Animation, deren Fehlen nicht auf
  den Platzhalter zurückfällt — eine handgezeichnete Idle-Animation soll nie
  zwischen ihren Durchläufen auf einer prozeduralen Strichfigur ruhen.
- **Mindestens ~0,4 s Idle-Länge.** Der Renderer wertet jede Einheit nur jeden
  dritten Bildschirmframe aus; eine kürzere Animation könnte zwischen zwei
  Auswertungen komplett durchlaufen und gelegentlich unsichtbar bleiben.
- Maske wie üblich: `stand_mask.png`.

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

**Zeile 1 zählt doppelt:** Das Schamanin-Portrait in der Seitenleiste (unter der
Minikarte) zeigt dieselben Sheets — und zwar immer die **Front-Ansicht**, also
Zeile 1. Im Todesfall zeigt es `dead_back.png` (Rückenlage, Gesicht sichtbar).
Das Portrait ist 72 Layout-Einheiten hoch; größere Frames werden hineinskaliert
(bei 64×96 also auf 75 %), das Sidebar-Layout bleibt davon unberührt. Die
Stammesfarbe wird dort mit derselben Maskenregel angewendet wie im Spiel.

**Import-Hinweis:** Unit-Sheets beim Godot-Standardimport (Lossless) belassen — keine
VRAM-Kompression einstellen.

## 3D-Modelle (.glb)

**Der Dateiname ist der Schlüssel.** Das Spiel sucht jedes Modell unter genau einem Pfad;
liegt dort keine importierte `.glb`, bleibt der prozedurale Platzhalter aktiv. Alles
Weitere (Bau-/Schadensoptik, Flagge, Schatten) hängt das Spiel selbst an.

**Gemeinsame Regeln für alle Modelle:**

- **Maßstab:** 1 Godot-Einheit = 1 m.
- **Ursprung:** am Boden (y = 0), mittig unter dem Objekt. Das Spiel setzt den Ursprung
  auf die Geländehöhe.
- **Ausrichtung:** die Vorderseite zeigt nach **+Z**. Bei Gebäuden ist das der **Eingang**
  (Süden bei Orientierung 0), bei Fahrzeugen die **Fahrtrichtung**; gedreht wird zur
  Laufzeit.
- **Stammesfarbe:** ein `MeshInstance3D` namens **`Flag`** (irgendwo im Baum) bekommt die
  Stammesfarbe als Material. Gebäude ohne `Flag` erhalten eine kleine prozedurale Flagge
  vom Spiel; Fahrzeuge ohne `Flag` zeigen einfach keine.
- **Schatten:** Fahrzeugmodelle werfen keinen Echtzeit-Schatten (das Spiel legt einen
  Blob-Schatten unter sie); Gebäude und Bäume werfen Schatten.

### Gebäude — `models/buildings/<kind>.glb`

Das Modell muss in den Footprint passen (Breite × Tiefe in Metern, Tiefe = Z-Achse, der
Eingang liegt an der +Z-Kante). Bau- und Zerstörungsoptik laufen über Textur-Tausch
auf demselben Modell (Abschnitt unten) — es gibt **keine** getrennten Stufenmodelle.

| Datei | Gebäude | Footprint (B × T) | Bemerkung |
|---|---|---|---|
| `hut.glb` | Hütte, Stufe 0 | 4 × 4 | |
| `hut1.glb` … `hut4.glb` | Hütte, Ausbaustufe 1–4 (`hut4` = Wohnpalast) | 4 × 4 | **Jede Stufe braucht ihr eigenes Modell.** Fehlt z. B. `hut2.glb`, zeigt eine Hütte auf Stufe 2 den Platzhalter — sie fällt **nicht** auf `hut.glb` zurück. Die Bodensilhouette darf über die Stufen nicht wachsen. |
| `warrior_camp.glb` | Kaserne (Krieger) | 5 × 5 | |
| `firewarrior_camp.glb` | Feuertempel (Feuerkrieger) | 8 × 8 | |
| `temple.glb` | Tempel (Prediger) | 6 × 6 | |
| `forester.glb` | Försterei | 2 × 4 | schmal und tief |
| `workshop.glb` | Katapultwerkstatt | 7 × 4 | breit und flach |
| `fireram_workshop.glb` | Feuerrammenwerkstatt | 6 × 4 | Schreibweise ohne Unterstrich zwischen fire und ram |
| `airship_wharf.glb` | Luftschiffwerft | 8 × 8 | |
| `watchtower.glb` | Wachturm | 2 × 2 | Besatzung wird vom Spiel auf zwei Plattformslots gesetzt |
| `wood_depot.glb` | Holzstation | 1 × 1 | |
| `reincarnation_site.glb` | Reinkarnationsplatz | 3 × 3 | unverwundbar, wird nie beschädigt dargestellt |

Die zugehörigen Stufentexturen heißen ebenfalls nach dem `<kind>` — für die Hütten also
`hut_stage1.png`, aber `hut2_stage1.png` für die zweite Ausbaustufe.

### Fahrzeuge und Golem — `models/units/<kind>.glb`

Nur die drei Fahrzeuge und der beschworene Golem sind 3D; alle anderen Fußeinheiten
sind Spritesheets (Abschnitt oben). Vorderseite +Z, Ursprung am Boden mittig. Als
Größenreferenz die Platzhalter:

| Datei | Fahrzeug | Platzhaltergröße | Sondernodes |
|---|---|---|---|
| `siege_engine.glb` | Katapult | Rumpf ~0,9 × 1,9 m, Räder ⌀ 0,56 m | **`Arm`** (`Node3D`, optional): Wurfarm, Ursprung im Drehbolzen, dreht beim Feuern um seine X-Achse; die Lage im Modell ist die gespannte Ruhelage, **positive Drehung hebt das hintere Ende (die Schale)**. Der Arm schnellt in 0,12 s um 1,15 rad hoch (`SiegeEngine.ARM_MODEL_SWING` — so weit muss er frei schwingen können), federt 0,25 s am Anschlag und wird in 0,7 s zurückgespannt. **`Stone`** (optional, `MeshInstance3D`, Kind von `Arm`, Ursprung in der Steinmitte): der Stein in der Schale, unsichtbar vom Abwurf bis der Arm wieder gespannt ist — **und er ist das Geschoss**: sein Netz fliegt statt des Feuerballs (`SiegeEngine._dress_shot`, `SiegeShot.stone_mesh`), 1,6-fach vergrößert, taumelnd, mit kleinerem Funkenschweif. Er löst sich 0,1 s nach dem Schuss dort, wo der Arm ihn dann hält, und läuft bis 60 % der Flugstrecke auf die unveränderte Geschossbahn ein. Ohne `Stone` fliegt weiter der Feuerball. **`Winch`** (optional): Winde, dreht eine Umdrehung um X mit dem Arm mit. **`Wheel*`** und `Flag` optional (s. u.). Projektmodell seit 2026-11-22: 1,45 m breit, 2,4 m lang, Räder ⌀ 0,59 m. |
| `fire_ram.glb` | Feuerramme | Rumpf ~1,0 × 1,7 m (Platzhalter auf 85 % skaliert) | **`Wheel*`** und `Flag` optional (s. u.). Die Flamme beginnt 1,2 m vor dem Ursprung (`FireRam.NOZZLE_OFFSET`) — dort sollte die Düse sitzen. Projektmodell seit 2026-11-22: 1,17 m breit, 2,0 m lang, Schnauze 1,15 m vor dem Ursprung, Räder ⌀ 0,46 m. |
| `airship.glb` | Luftschiff (Zeppelin) | Ballon ~6 m lang × 2 m breit, Unterkante ca. 2,5 m über dem Ursprung; Gondel/Deck 1,6 × 3,6 m | `Flag` optional. **Das Deck muss bei y = 0,6 m liegen** (`Airship.DECK_Y`): dort stellt das Spiel die Passagiere hin — zwei Spalten ±0,44 m neben der Mittelachse, drei Ränge im Abstand 0,85 m. Der Rumpf wippt ±0,15 m (Periode ~5 s), die Passagiere schweben mit. Der Ursprung ist der Punkt **unter** dem Schiff am Boden; die Flughöhe setzt das Spiel. |

| `golem.glb` | Golem (Zauber 13) | Modell **4 m hoch gebaut** (`Golem.MODEL_HEIGHT`) — das Spiel skaliert es auf `Balance.GOLEM_HEIGHT` (5,25 m, so hoch wie der Wachturm); schlanke Figur, im Spiel 2,3 m breit × 1,8 m tief, Ursprung an den Füßen mittig; Platzhalter: Beine, Rumpf, Schultern, Kopf, zwei hängende Arme | **`AnimationPlayer`** (optional) mit den Clips `idle` / `walk` / `slam` / `kick` / `swat` / `death` (s. u.). **`Flag`** (`MeshInstance3D`, optional): Teil in Stammesfarbe (leuchtet leicht) — beim Projektmodell seit 2026-11-17 eine **Raute auf der Brust** (die Figur trägt jetzt einen weißen Gymnastikanzug; vorher die Krawattenschleife der Schuluniform). `grow` und `stomp` seit 2026-11-17 in der **niedlichen Fassung** wie beim Dämonengolem (Namen und Zeiten unverändert). **`Arm`** (`Node3D`, optional, nur für Modelle ohne Clips): Schulter-Pivot beider Arme, schwingt beim Angriff um seine X-Achse. |
| `golem_demon.glb` | Dämonengolem (Zauber 14) | Modell **4 m hoch gebaut** wie `golem.glb`; das Spiel skaliert es auf seine Größe (2 m beim Erscheinen, +3 m je Wachstumsstufe, seit 2026-11-17) und zeigt es **25 % breiter und tiefer** als den Golem gleicher Höhe (`DemonGolem.model_scale`). Die Figur mit den Jeansschuhen, muskulöser; fehlt die Datei: derselbe Platzhalter wie beim Golem | Wie `golem.glb`: **`AnimationPlayer`** mit denselben 16 Clipnamen und Zeiten, **`Flag`** (Krawattenschleife). `walk` deckt 2,575 m je Durchlauf (`DemonGolem.WALK_CLIP_STRIDE`). Erzeugt von `D:\game\gymnastikschuh\golem_export.mjs` aus `jeans_variante/out/avatar_1_example_daemon.vrm`. Seit 2026-11-17 mit der **niedlichen Fassung** von `grow` und `stomp` (`--bewegung=./golem_bewegung_niedlich.mjs`: Schuhspitzen nach innen, graziles Strecken, Mädchensprung) — Namen und Zeiten unverändert. |
| `golem_genesis.glb` | Genesisgolem (Zauber 15) | Modell **4 m hoch gebaut** wie `golem.glb` und im Spiel genauso skaliert (10 % niedriger als breit, `Golem.model_scale`). Die Figur mit den rosa Schuhen in Shorts und Top; fehlt die Datei: derselbe Platzhalter wie beim Golem | Wie `golem.glb`: **`AnimationPlayer`** mit denselben 16 Clipnamen und Zeiten, **`Flag`** (Raute auf der Brust). `walk` deckt 2,614 m je Durchlauf (`GenesisGolem.WALK_CLIP_STRIDE`). `grow` und `stomp` in der niedlichen Fassung. Erzeugt von `golem_export.mjs` aus `rosa_variante/out/avatar_1_example_rosa_final.vrm`. |

Das Katapult ohne `Arm` feuert trotzdem — nur ohne die Schnapp-Animation; der Golem
ohne Clips und ohne `Arm` greift trotzdem an — nur ohne Bewegung.

**Räder (`Wheel*`, seit 2026-11-22, Katapult und Feuerramme):** jeder Node, dessen Name mit
`Wheel` beginnt, ist ein Rad (`CrewedVehicle._collect_wheels`). Sein **Ursprung liegt auf der
Achse**, die Achse zeigt entlang X. Das Spiel dreht ihn um X um gefahrene Strecke / Radius;
der Radius ist die **Höhe des Ursprungs über dem Boden** (das Rad muss also bei y = 0
aufstehen). Dreht das Fahrzeug auf der Stelle, laufen die Räder links und rechts gegeneinander
(aus dem seitlichen Abstand des Ursprungs). Ein Clip ist nicht nötig. Ohne `Wheel*` fährt das
Fahrzeug mit stehenden Rädern.

**Woher die beiden Projektmodelle kommen:** `tools\fahrzeuge\fahrzeuge_bauen.py` baut sie aus
den gelieferten Rohmodellen in `tools\fahrzeuge\quelle\` (Teile trennen, Drehpunkte setzen,
Räder der Feuerramme abschneiden, Wimpel ergänzen). Anleitung und Stolpersteine:
`tools\fahrzeuge\LIESMICH.md`. Ansehen im Spiel-Renderer: `tests/diag_vehicle_models.gd`.

**Golem-Animationen (optional, `AnimationPlayer` im Modell; `idle` ist seit 2026-11-15 das gekürzte Idle 1 der Figur, 20,5 s):** Seit 2026-11-15 zusätzlich `kick_l` (Tritt mit dem linken Bein, 1,2 s), `swipe` (waagerechter Schwinger gegen Luftschiffe auf Brusthöhe, 1,2 s, Treffer bei 0,5 s) und `drum` (drei Schläge auf den Boden links/rechts/links bei 0,8/1,25/1,7 s, 2,4 s); fehlt einer, spielt das Spiel `kick` bzw. `swat` bzw. keinen Clip. Für die gebückte Haltung (2026-11-16): `crouch_down` und `crouch_up` (je 0,45 s, Stand ↔ gebückte Ruhepose), `crouch_idle` (Schleife, 3 s), `slam_low` (0,9 s, Aufschlag bei 0,35 s) und `drum_low` (1,7 s, Aufschläge bei 0,35/0,8/1,25 s) — alle beginnen bzw. enden in derselben gebückten Pose; fehlen sie, spielt das Spiel `slam`/`drum` bzw. `idle`. Fürs Wachsen: `grow` (**1,0 s** seit 2026-11-16, Strecken aus dem Stand und zurück; fehlt er, pausiert der Golem die Sekunde ohne Animation). **Seit 2026-11-16 gezielter:** beim Handschlag (`slam`, `slam_low`) liegen beide Hand-Schuhe dicht nebeneinander auf dem Aufschlagpunkt (`Balance.GOLEM_SLAM_FORWARD`, im Modell 0,91 m vor dem Ursprung bei 4 m Höhe), beim Trommeln (`drum`, `drum_low`) 0,34 m neben der Körpermitte statt 0,59 m; die Arme sind am Boden leicht angewinkelt. **Sprungangriff (2026-11-16):** `stomp` (**1,0 s**, Sprung auf der Stelle aus dem Stand: Absprung bei 0,3 s, **Landung beider Füße bei 0,6 s** = `Balance.GOLEM_STOMP_WINDUP`, danach sinkt sie in die gebückte Haltung; der Clip beginnt in der stehenden Ausgangspose und **endet in der gebückten Ruhepose**, daran schließen `crouch_idle`, `slam_low`, `drum_low` oder `crouch_up` ohne Sprung an; fehlt er, fällt der Schaden ohne Bewegung). `idle` und `walk` (das Spiel
schaltet beide auf Schleife; `walk` auf der Stelle, das Abspieltempo folgt der echten
Geschwindigkeit über `Golem.WALK_CLIP_SPEED`), `slam` (Handschlag, **Aufschlag bei 0,8 s**),
`kick` (Tritt, **Aufschlag bei 0,5 s**), `swat` (Schlag nach oben gegen Luftschiffe, **Aufschlag bei 0,5 s**)
und `death` (einmalig; danach versinkt die Figur).

**Sitzen (2026-11-17):** alle drei Golem-Modelle bringen dazu `sit_down` (1,5 s, gebückte Ruhe → Sitz), `sit_up` (1,5 s, zurück) und
`sit_idle` (18 s, Schleife: umschauen, mit den Schuhspitzen wippen, die Hände umsetzen) – zusammen 19 Clips, dazu seit dem Abend des 2026-11-17 die zwölf Clips der Sitzangriffe (`sit_stomp_l/_r`, `sit_kick_l/_r`,
`sit_wipe_l/_r`, `sit_hop`, `sit_clap`, `sit_double_stomp`, `sit_turn_l/_r`, `sit_grow`; Ebenen und Aufschlagzeiten in
`scripts/units/golem_sit_anim.gd`): **31 Clips** je Modell. Die Clips
schließen zahlengleich an die gebückte Pose an; fehlen sie, wechselt das Spiel die Haltung ohne Bewegung. **Im Spiel gibt es dafür
die Haltung `Golem.STANCE_SIT`, aber noch keinen Auslöser** (`Golem.sit_down()` ruft bisher niemand). Mit denselben Dateien kam die
**gebückte Haltung ohne Clipping**: in `crouch_*`, `slam_low`, `drum_low` und `stomp` stehen die Knie außen neben dem
Oberkörper (vorher steckten die Oberschenkel im Brustkorb), die Schuhspitzen drehen mit, das Becken ist weniger gekippt. Zeiten,
Aufschlagorte und Arme sind unverändert. Erzeugt mit `--bewegung=./golem_bewegung_niedlich_sitzen.mjs`
(`D:\game\gymnastikschuh\LIESMICH_POPULOUS.md`, Abschnitt „Sitzen“).
Die Aufschlagzeiten müssen zu `Balance.GOLEM_SLAM_WINDUP` / `GOLEM_KICK_WINDUP` / `GOLEM_SWAT_WINDUP` passen — dort
fällt der Schaden. Das Modell des Projekts erzeugt `D:\game\gymnastikschuh\golem_export.mjs`.

**Stand 2026-11-20:** alle drei Golem-Modelle haben **41 Clips** (dazu seit 2026-11-18 Krebsgang, Sterben im Sitzen und der seitliche
Handschlag) und sind mit `--bewegung=./golem_bewegung_niedlich_spiel.mjs` erzeugt (Arbeitskopien: `D:\game\gymnastikschuh\out\golem_spiel\`).
Neu darin: `walk`, `kick` und `kick_l` sind die **niedlichen Fassungen** (x-beiniger Gang mit Schuhspitzen nach innen; Schnapptritt statt
Fußballtritt) – Namen, Dauer, Treffzeit (0,50 s) und Schrittweg (2,658 m je Durchlauf bei 4 m) sind unverändert, am Spielcode ändert sich
nichts. Beim Tritt kommt der Fuß jetzt von oben (Sohle vor dem Treffer mindestens 0,25 m über dem Boden statt 0,09 m). `swipe` ist
korrigiert: der Oberarm taucht beim Durchschwingen nicht mehr in den Oberkörper (der alte `swipe` ist entfernt). Die alten `walk`/`kick` liegen nur noch in der Werkstatt
(`LIESMICH_POPULOUS.md`, Abschnitt „Niedliches Gehen und Treten“).

**Stand 2026-11-21:** die drei Modelle haben **22 Knochen** (dazu `leftToes`, `rightToes`) und sind mit
`--bewegung=./golem_bewegung_niedlich_ballen.mjs --zehen` erzeugt. Die Schuhe knicken am Ballen: in `grow` steht sie auf den Ballen (Ferse
hoch, Vorfuß am Boden), in `walk` rollt der Schuh beim Abdrücken über den Ballen ab, statt als Ganzes auf die Spitze zu kippen; der
niedliche Gang ist dabei leicht zurückgenommen (Becken und Knie auf 80 %). Je steifer der Schuh, desto niedriger die Ferse (Golem >
Genesisgolem > Dämonengolem). Namen, Dauern und Schrittweg sind unverändert, 39 der 41 Clips zahlengleich; `golem_sit_anim.gd` zählt die
Zehenknochen zu den Beinen (8 statt 6 Spuren in der Bein-Ebene). Einzelheiten: `LIESMICH_POPULOUS.md`, Abschnitt „Ballenstand beim Strecken“.

### Bäume — `models/trees/<kind>.glb`

Ein Modell je Baumtyp, gezeichnet in **ausgewachsener** Größe (Platzhalter: rund 3 m
hoch). Die Wachstumsstufen skaliert das Spiel als Ganzes:

| Datei | Typ | Stufen-Skalierung (Stufe 0 → max) | Bemerkung |
|---|---|---|---|
| `tree.glb` | Standardbaum (Nadel) | 0,28 · 0,35 · 0,55 · 0,8 · 1,0 | überall |
| `tree_leaf.glb` | Laubbaum | 0,28 · 0,35 · 0,55 · 0,8 · 1,0 | wächst auf Gras schneller |
| `tree_bamboo.glb` | Bambus | 0,3 · 0,65 · 1,0 (nur 3 Stufen) | nur auf Gras, steht dicht |

- Stufe 0 ist der Sämling: **0,28-fach** — das Modell sollte auch so klein noch lesbar
  sein (dünner Stamm, kleine Krone).
- Ein brennender Baum **schrumpft** bis zum Verschwinden; das gilt für die `.glb` genauso.
  Das Flackern/Ausblenden der Krone gibt es nur beim Platzhalter.
- Ursprung am Fuß des Stamms, Stamm entlang +Y.
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
| **1** | `spell_voice_*`, `shaman_death`, `shaman_air_death` | Verdrängen bei Bedarf laufende Sounds niedrigerer Priorität |
| **2** | `airship_death`, `siege_death_burn`, `siege_death_burst`, `golem_death` | Verdrängen Prio 3 |
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
| `unit_air_death.ogg` | Einheit (nicht Schamanin) erleidet **in der Luft** tödlichen Schaden (auch vom Luftschiffdeck geschossene Besatzung) — der Tod selbst folgt beim Aufprall mit `unit_death.ogg` (max. alle 0,2 s) |
| `shaman_air_death.ogg` | Dasselbe für die **Schamanin**: ihr eigener Schrei beim tödlichen Treffer in der Luft (Prio 1 wie `shaman_death`) |
| `golem_strike.ogg` | Aufschlag eines Golem-Angriffs — der gemeinsame Sound, solange die vier folgenden fehlen (max. alle 0,2 s) |
| `golem_kick.ogg` | Aufschlag des Tritts |
| `golem_slam.ogg` | Aufschlag des Handschlags (beide Hände auf den Boden) |
| `golem_drum.ogg` | EIN Trommelschlag (wird dreimal je Trommeln gespielt, im Abstand von 0,45 s) |
| `golem_stomp.ogg` | Landung des Sprungs (beide Füße schlagen auf) |
| `golem_swat.ogg` | Treffer auf ein Luftschiff (Schlag nach oben, Schwinger oder Tritt) |
| `golem_grow.ogg` | Der Golem wächst und streckt sich (Stufenaufstieg, Wachstumsschritt nach Stufe 7; 0,5 s) |
| `golem_death.ogg` | Golem zerfällt (Lebenszeit abgelaufen oder erschlagen; Prio 2) |

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

Die dreizehn gültigen IDs (aus `scripts/spells/*.gd`):

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
| `spell_voice_golem.ogg` | `spell_golem.ogg` | Golem beschwören | wenn der Golem erscheint (nur bei erfolgreicher Beschwörung) |
| `spell_voice_demon_golem.ogg` | `spell_demon_golem.ogg` | Dämonengolem beschwören | wenn der Dämonengolem erscheint (nur bei erfolgreicher Beschwörung). Alle übrigen Sounds teilt er mit dem Golem (`golem_*`, `select_golem` …) |

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
| `select_golem.ogg` | Auswahl enthält einen Golem (und keine Schamanin); fehlt die Datei: `select_unit` |
| `move_golem.ogg` | Move-Befehl an eine Gruppe mit Golem (ohne Schamanin); fehlt die Datei: `move_unit` |
| `attack_golem.ogg` | Angriffsbefehl (Rechtsklick auf feindliche Einheit, Luftschiff oder Gebäude) mit einem Golem in der Auswahl; fehlt die Datei: `move_golem`, sonst stumm — andere Einheiten haben keinen Angriffsbefehl-Sound |
| `move_blocked.ogg` | Move-Befehl auf ein unerreichbares Ziel (abgelehnt) |
| `click.ogg` | *(reserviert — noch an keinen Button angebunden)* |

## Export-Builds (Notiz für später)

Beim Einrichten eines Export-Presets muss `*.json` in die Include-Filter aufgenommen
werden, damit die `manifest.json`-Dateien mitkommen.
