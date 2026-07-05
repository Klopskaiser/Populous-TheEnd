# Phase 5 — Training, Rally Points, Kampf, Prediger

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Vollständige Einheitenpalette (außer Schamanin): Braves werden in Trainingsgebäuden zu
Kriegern, Feuerkriegern und Predigern ausgebildet und laufen danach zum Rally Point.
Ein tiefes **Nahkampf-/Fernkampfsystem** (Prügelkampf in Gruppen, Feuerball-Fernkampf mit
Rückstoß), **Prediger-Konvertierung**, **Hügel-/Rollmechanik** und **Regeneration** stehen
gegen einen statisch vorplatzierten roten Sparring-Stamm zur Verfügung.

> **Aufteilung in Sub-Phasen.** Phase 5 ist zu groß für einen Implementierungslauf und wird in
> **vier Sub-Phasen 5a–5d** umgesetzt. Jede endet mit **grüner Testsuite**, fehlerfreiem
> `--headless --quit` und einem **lauffähig/manuell spielbaren Zwischenstand** und hat eine
> eigene Definition of Done. Reihenfolge ist strikt: 5a → 5b → 5c → 5d. Der Kopf dieses
> Dokuments (Einheiten-Werte + die drei Referenzabschnitte „Kampfsystem im Detail“,
> „Prediger-Verhalten“, „Bewegung“) gilt phasenübergreifend; die Sub-Phasen verweisen darauf.

## Voraussetzungen

Phasen 1–4: Unit/Brave, UnitManager (Spatial-Hash + zentrale Ticks + MultiMesh-`UnitRenderer`),
Building/Hut, Tribe, TribeCommands, Sidebar (Phase 4) mit Gebäude-Tab (Platzhalter-Buttons
für Trainingsgebäude) und Gefolgsleute-Tab (vorbereitete Zähler-Zeilen). Neue Einheiten-Typen
müssen in `UnitRenderer.KINDS` **und** `PlaceholderSprites.build_atlas`/`make_frames`
ergänzt werden (siehe Phase 3f).

## Einheiten-Werte (verbindlich, phasenübergreifend)

Basiswert ist der **Brave** (60 HP, Speed 4, Nahkampf). Alles relativ dazu:

| Einheit | HP | Nahkampf-Stärke | Fernkampf | Bewegung |
|---|---|---|---|---|
| **Brave** | 60 (Basis) | Basis | — (nur Nahkampf) | Basis |
| **Krieger** | **120** (2×) | **3× Brave** | — (nur Nahkampf) | Basis |
| **Feuerkrieger** | 60 (= Brave) | = Brave (prügelt sich) | mittlere Reichweite, **leicht > Brave** | Basis |
| **Prediger** | **75** (etwas > Brave) | = Brave | — | Basis |

Konkrete Schadenszahlen (Tuning-Defaults, in Phase 8 justierbar) als Konstanten in `unit.gd`:
- **Schlagen (punch):** mittlerer Schaden (≈ `MELEE_PUNCH = 6`).
- **Treten (kick):** etwas mehr als Schlagen, seltener (≈ `MELEE_KICK = 8`, Chance ~20 %).
- **Schubsen (shove):** geringer Schaden, kann Rollen auslösen (≈ `MELEE_SHOVE = 3`).
- **Feuerball:** leicht stärker als ein Brave-Schlag (≈ `FIREBALL_DAMAGE = 7`) + Rückstoß.
- **Krieger** multipliziert seinen Nahkampfschaden mit `MELEE_STRENGTH = 3.0`; alle anderen
  mit 1.0. Der Krieger **schubst seltener** (kleinere Shove-Chance) — er schlägt/tritt lieber.

## Trainingsgebäude (verbindlich, phasenübergreifend)

Drei Trainingsgebäude, je eine Zieleinheit. Kosten und Trainingszeiten:

| Gebäude (Rolle) | Skript / Szene | Zieleinheit | Referenzbild | Holz | Trainingszeit |
|---|---|---|---|---|---|
| **Kaserne** (Krieger-Trainingslager) | `warrior_camp.gd` | Krieger | `kaserne1.png` | **5** | **3 s** (kürzeste) |
| **Feuertempel** (Feuerkrieger-Trainingslager) | `firewarrior_camp.gd` | Feuerkrieger | `feuertempel.png` | **10** | **4 s** |
| **Tempel** (Prediger) | `temple.gd` | Prediger | `tempel.png` | **5** | **5 s** (längste) |

**Aussehen** — die drei Referenzbilder liegen im Projekt-Root
(`D:\game\Populous-TheEnd\kaserne1.png` / `feuertempel.png` / `tempel.png`). Die Optik ist
**prozedural nachzuempfinden** (keine externen Assets, `assets\` bleibt leer — Overview §7);
Ziel ist eine erkennbare Silhouette in derselben Reet-/Fell-/Blau-Rune-Optik wie die Hütte,
nicht ein 1:1-Nachbau. Kern-Merkmale je Gebäude:

- **Kaserne (Krieger):** große, **ring-/hufeisenförmige** Anlage mit Reetdach um einen offenen
  Innenhof; ein hoher **Rundturm** mit Spitze und blau-violettem Federbüschel; blaue Knoten-/
  Runenmuster ums **Torbogen-Tor**; an den Außenwänden **Schilde, Waffen und Schädel**,
  Palisadenspitzen auf der Mauerkrone; im Hof Kisten/Fässer. Kriegs-/Waffenthema.
- **Feuertempel (Feuerkrieger):** runde **Zentralhütte mit breitem konischem Reetdach** auf
  Holzgestell, blau bemalte Fellwände mit blauen Schnörkel-Runen, dunkler Rundeingang;
  umlaufender **Palisadenzaun**; davor zwei markante **lodernde Feuerschalen** auf
  Astbündel-Sockeln (Feuer-Merkmal, ggf. Partikel/Glow); kleine Eck-Hütten. Feuerthema.
- **Tempel (Prediger):** einzelne **kuppelförmige** Lehm-/Steinhütte, heller Putz mit blauen
  **Figuren-Glyphen** (stilisierte Menschen mit ausgestreckten Armen); breites rundes Reetdach;
  obenauf eine **blau-goldene Kegel-Spitze** (Finial); Torbogen-Vorbau, zwei kleine Wandfackeln.
  Heiliges/friedliches Thema.

Die **Sidebar-Labels** (Gebäude-Tab) auf diese Namen setzen: „Kaserne (5 Holz)“,
„Feuertempel (10 Holz)“, „Tempel (5 Holz)“.

## Kampfsystem im Detail (Referenz)

### Nahkampf (Prügelkampf in Gruppen) — *umgesetzt in 5b*

- **Nur ab Nahkampfreichweite aktiv** (`MELEE_RANGE`, klein). Außer Reichweite: Ziel verfolgen.
- **Angriffsarten** (gleiche Animationen für **alle** Einheiten — Schlagen/Treten/Schubsen):
  - **Schlagen:** mittlerer Schaden (häufigster Angriff).
  - **Treten:** etwas mehr Schaden als Schlagen, **seltener**.
  - **Schubsen:** geringer Schaden, **Rollrisiko** falls das Ziel auf einem Hügel steht
    (selten löst ein Schubs einen Rollvorgang bergab aus, siehe Bewegung/5d). **Krieger
    schubsen seltener.**
  - Pro Treffer wird die Angriffsart gewürfelt; die gewählte Art bestimmt Schaden, Sound und
    (bei Schubs) Roll-/Rückstoß-Chance.
- **Mengenbegrenzung — max. 3 Angreifer je Ziel gleichzeitig.** Das Ziel führt eine
  `melee_attackers: Array` (max. 3). Angreifer stellen sich in **festen Slots rund um das
  Ziel** auf (drei Positionen im Kreis, z. B. 120°-Ringplätze via
  `TribeCommands.formation_offset`-artigem Muster) und schlagen **abwechselnd** zu → das Ziel
  bekommt ~**3× so viele Treffer** wie im 1-gegen-1.
- **Warteschlange:** Überzählige Angreifer, die keinen Slot bekommen, **warten dicht um den
  Kampf herum** (Ring-Position) und rücken **sofort nach**, sobald einer der drei besiegt wird
  (Slot-Freigabe beim Tod des Angreifers **oder** des Ziels).
- **1-gegen-1 wird bevorzugt:** Ist in naher Reichweite ein noch freies Feindziel vorhanden,
  greift eine Einheit lieber dieses an, statt sich als 2./3. Angreifer an ein bereits
  bekämpftes Ziel zu hängen. Nahkämpfe finden also in kleinen Gruppen (1–3) statt.
- Slot-Bookkeeping robust gegen freigegebene Instanzen halten (untypisierte Referenzen +
  `is_instance_valid`, vgl. Erkenntnisse Phase 3b/3c).

### Fernkampf (Feuerball) — *umgesetzt in 5c*

- Feuerkrieger feuern aus **mittlerer Reichweite** (größer als Nahkampf, kleiner als Aggro).
  Nach dem Abfeuern verschwinden die Feuerbälle in den Händen des Sprites kurz und erscheinen
  beim „Nachladen“ wieder.
- **Rückstoß skaliert mit Treffer-Dichte:** Jeder Feuerball schleudert das Ziel etwas zurück;
  treffen **mehrere Feuerbälle schnell nacheinander**, summiert sich der Rückstoß (kurzer
  „Rückstoß-Akkumulator“ pro Ziel, klingt über Zeit ab) → größerer Effekt, kann bergab einen
  **Rollvorgang** auslösen (siehe Bewegung/5d).
- **Beliebig viele** Fernkämpfer dürfen ein einzelnes Ziel beschießen (keine 3er-Grenze wie im
  Nahkampf — die gilt nur fürs Prügeln).
- Im **Nahkampf** setzt der Feuerkrieger **keine** Feuerbälle ein, sondern prügelt sich wie ein
  Brave (Nahkampfstärke = Brave).

### Aggro & Verteidigung — *umgesetzt in 5b*

- **Kampfeinheiten** (Krieger/Feuerkrieger) im IDLE greifen Feinde im **Aggro-Radius**
  selbstständig an.
- **Braves fliehen NICHT** (bewusste Abweichung vom ursprünglichen Plan): Werden sie
  angegriffen, **wehren sie sich** und schlagen zurück (Nahkampf gegen den Angreifer). Sie
  suchen aber nicht proaktiv über Distanz nach Feinden (kein Aggro-Radius wie Kampfeinheiten) —
  sie verteidigen sich nur.
- **Rechtsklick auf eine feindliche Einheit = Angriff.** Selektierte Kampfeinheiten greifen an
  und **verteilen sich intelligent** im entstehenden Kampfgeschehen: Ist das befohlene Ziel
  bereits von 3 eigenen Einheiten bedrängt, sucht sich die Einheit selbstständig ein anderes
  Feindziel in Reichweite oder verteidigt sich, wenn sie selbst angegriffen wird.

### Leben, Regeneration, Sounds — *umgesetzt in 5d*

- **HP werden NIE angezeigt.** Großer erlittener Schaden wird durch kurz **kreisende Sterne
  über dem Kopf** signalisiert (Overlay-Sprite, ab Schaden-Schwelle pro Treffer/Zeitfenster).
- **Regeneration außerhalb des Kampfes:** War die Einheit `REGEN_DELAY` Sekunden nicht in einen
  Kampf verwickelt (weder ausgeteilt noch eingesteckt, kein Roll), heilt sie langsam bis
  `max_health` zurück.
- **Sounds:** Jede Angriffsart (Schlag/Tritt/Schubs) hat **eigene Sounds**, die **zufällig aus
  einer kleinen Auswahl** kommen. Prozedural erzeugte `AudioStreamWAV` (kurze Rausch-/Impuls-
  Bursts, mehrere Varianten je Art) — **keine externen Asset-Dateien** (`assets\` bleibt leer,
  vgl. Overview §7). Abspielen gedrosselt/gepoolt, damit Massengefechte die Audio-Bus nicht
  überlasten.

## Prediger-Verhalten (Referenz) — *umgesetzt in 5c*

- **Konvertiert auf geringe Distanz:** Der Prediger bleibt **stehen** (Cast-Animation); die
  gegnerischen Einheiten in seiner Konvertierungs-Reichweite **bleiben ebenfalls stehen, hören
  auf zu kämpfen und setzen sich hin** (Sitz-Animation/-Zustand). Nach einer **zufälligen Zeit**
  je Ziel werden sie konvertiert (Tribe-Wechsel: Tribe-Listen umhängen, Farbe/`modulate`
  wechseln, laufende Befehle abbrechen).
- Konvertiert **keine Schamanin** und **keinen anderen Prediger** (Original-Regel, hält Balance
  einfach).
- **Priester-Duell:** Kommt ein **feindlicher Prediger** in Reichweite, **prügeln sich die
  beiden Prediger** (Nahkampf). Der Bekehrungseffekt ist dann **weg** (die sitzenden Einheiten
  stehen wieder auf), und **auch die Gegner greifen den Prediger mit an**.
- **Trägheit laufender Kämpfe:** Gelegentlich **hören angrenzende Kämpfe nicht sofort auf**,
  wenn sie bereits im Gange waren (nicht jede Einheit im Radius setzt sich sofort hin — mit
  einer gewissen Wahrscheinlichkeit kämpft ein bereits kämpfendes Paar noch weiter).
- **Feuerkrieger-Störung:** Feuerkrieger haben eine **höhere Reichweite** und können mit einem
  **Feuerangriff den Bekehrungszyklus zurücksetzen** (der `conversion_progress` des getroffenen
  Ziels fällt zurück / die Einheit steht auf und kämpft weiter).

## Bewegung (Hügel & Rollen) (Referenz) — *umgesetzt in 5d*

- **Bergauf langsamer:** Einheiten bewegen sich langsamer, wenn sie einen Hügel erklimmen (Speed
  skaliert mit der Steigung in Laufrichtung, aus `TerrainData`-Höhen berechnet).
- **Rollen bergab:** Einheiten können steile Hügel hinunterrollen. Chance steigt mit der
  **Steilheit**; ohne Kampf passiert das **nur bei sehr steilen Hängen**, kann aber
  **ausgelöst/befördert** werden durch **Fernkampf-Rückstoß** (Feuerball, 5c) oder — **selten** —
  durch **Schubsen im Nahkampf** (5b).
- **Roll-Zustand** (`State.ROLL`, analog zum späteren `THROWN`): Y-Snapping/Separation
  ausgesetzt, Einheit rollt der Falllinie bergab folgend.
  - **Endet erst, wenn es flach genug ist** (Steigung unter Schwellwert).
  - **Rollt eine Einheit ins Wasser (unter `sea_level`), stirbt sie sofort.**
  - **Rollen verursacht leichten Schaden**, je länger es dauert.
  - Einheiten sterben durch Rollschaden **erst am Ende** des Rollvorgangs — auch wenn die HP
    zwischendurch schon ≤ 0 sind, wird der Tod bis zum Rollende aufgeschoben (Landeposition auf
    begehbare Zelle clampen, vgl. Overview-Risiko 6/7).

## Verifikations-Befehle (für jede Sub-Phase)

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
& $GODOT --path D:\game\Populous-TheEnd --headless --import
& $GODOT --path D:\game\Populous-TheEnd --headless -s res://tests/run_tests.gd   # Exit-Code 0
& $GODOT --path D:\game\Populous-TheEnd --headless --quit
```

---

## Sub-Phase 5a — Training, Rally Points, Einheiten-Modelle

**Fokus:** Einheiten werden ausgebildet und laufen zum Rally Point. **Noch kein Kampf** — die
neuen Einheiten haben nur ihre Werte und ihr sichtbares Modell.

### Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/buildings/training_building.gd` | `class_name TrainingBuilding extends Building`. `produces: PackedScene` (Zieleinheit), `training_time: float`, `queue: Array` (wartende/trainierende Braves). Ablauf in `tick`: Brave erreicht Gebäude (State TRAIN, aus Spatial-Hash/Renderer raus) → Timer → Brave entfernt, neue Kampfeinheit am Gebäuderand gespawnt (gleicher Tribe) → `order_move(rally_point)`. Befüllung via `TribeCommands.order_train(tribe, building, braves)` (selektierte Braves + Rechtsklick aufs Gebäude); Belegungs-/Slot-Icon mit Einheitentyp-Symbol (Nachzug aus Phase 4) |
| `scripts/buildings/warrior_camp.gd`, `firewarrior_camp.gd`, `temple.gd` + Szenen | Ableitungen mit jeweiliger Zieleinheit, **Kosten und Trainingszeit gemäß Tabelle „Trainingsgebäude“** (Kaserne 5 Holz/3 s, Feuertempel 10 Holz/4 s, Tempel 5 Holz/5 s). Prozedurale Placeholder-Meshes, die die **Referenzbilder** silhouettenmäßig nachempfinden (Kaserne = Ring/Hufeisen + Rundturm + Schilde/Waffen; Feuertempel = Rundhütte + Kegeldach + Feuerschalen; Tempel = Kuppel + breites Reetdach + blau-goldene Spitze). Im **Gebäude-Tab der Sidebar** die Platzhalter-Buttons aus Phase 4 aktivieren (deutsch: „Kaserne“, „Feuertempel“, „Tempel“); im Gefolgsleute-Tab die Zähler-Zeilen der neuen Typen aktivieren |
| `scripts/units/warrior.gd`, `firewarrior.gd`, `preacher.gd` + Szenen | **Dünne** `Unit`-Ableitungen: nur Werte (HP/Basiswerte aus der Tabelle) + **Sprite-Silhouetten**, in `UnitRenderer.KINDS` + `PlaceholderSprites.build_atlas`/`make_frames` registriert: Krieger = **Schild + Schwert**, Feuerkrieger = **Helm + Feuerbälle in den Händen**, Prediger = **Haube + Gewand**. Kampf-/Sonderverhalten kommt in 5b/5c |
| Rally-Point-Verdrahtung | Rally-Point-UI existiert aus Phase 4 (Auswahl-Gebäude + Rechtsklick → `rally_point`, Fahne/Marker). Für Trainingsgebäude verdrahten: fertige Einheiten laufen zur Fahne |
| Sparring-Setup in `main.gd` | Roter Tribe (id 1) statisch vorplatziert: Hütte, Krieger-Lager, ein paar Krieger/Braves/Feuerkrieger auf der anderen Inselseite — kämpfen noch nicht, existieren aber (Vorbereitung für 5b) |
| `tests/test_training.gd` | siehe Tests |

### Umsetzungsschritte

1. `warrior.gd`/`firewarrior.gd`/`preacher.gd` (nur Werte) + Sprite-Silhouetten in Atlas/Renderer.
2. `training_building.gd` + `order_train` in TribeCommands + die drei Camp-Ableitungen + Szenen.
3. Sidebar-Buttons/Zähler aktivieren; Rally-Point für Trainingsgebäude verdrahten.
4. Sparring-Basis in `main.gd`. Verifikation + manuelle Prüfung.

### Tests (`tests/test_training.gd`)

- `order_train` schickt Brave zum Gebäude; nach `training_time` Ticks existiert eine neue
  Kampfeinheit desselben Tribes, der Brave ist weg (Population konstant ±0, Typ gewechselt).
- Neue Einheit hat Bewegungsziel = `rally_point` des Gebäudes; Rally-Änderung wirkt für danach
  fertige Einheiten.
- Training ohne wartende Braves produziert nichts; Queue arbeitet FIFO mehrere Braves ab.

### Definition of Done 5a

- [x] Testsuite grün, `--headless --quit` fehlerfrei
- [x] Manuell: Camps baubar, Braves reinschicken → korrekte Einheit läuft zur Rally-Fahne;
  Modelle sichtbar (Schild+Schwert / Helm+Feuerbälle / Haube+Gewand); Rally per Rechtsklick
  versetzbar (auch bei Hütten)
- [x] `git add -A && git commit -m "Phase 5a: Training, Rally Points, Einheiten-Modelle" && git push`

---

## Sub-Phase 5b — Nahkampf-Kern

**Fokus:** Vollständiger Prügel-Nahkampf inkl. Gruppen-/Slot-System, Krieger, Brave-Verteidigung,
Aggro und Rechtsklick-Angriff. (Feuerkrieger/Prediger kämpfen hier vorerst **nur** im Nahkampf;
ihr Sonderverhalten folgt in 5c.) Referenz: „Nahkampf“ + „Aggro & Verteidigung“ oben.

### Deliverables

| Datei | Inhalt |
|---|---|
| Kampf-Grundlagen in `unit.gd` | `take_damage()` → bei ≤0 HP State DEAD, `Events.unit_died`, Despawn + Deregistrierung (Tribe, UnitManager, UnitRenderer, Selektion). Zielsuche via Spatial-Hash (`get_units_in_radius`), **per Timer alle 0,2–0,3 s mit Zufalls-Offset**, nie pro Frame. `MELEE_*`-Konstanten (siehe Werte-Tabelle) |
| Prügelkampf | Angriffsarten Schlag/Tritt/Schubs (Schadensstaffelung, gleiche Anims für alle, Krieger schubst selten). ATTACK-State: Ziel verfolgen, in Reichweite abwechselnd zuschlagen |
| Nahkampf-Slot-System | max. 3 Angreifer/Ziel (`melee_attackers`), Ring-Aufstellung, Warteschlange mit Nachrücken beim Tod, 1v1-Bevorzugung (Details in der Referenz oben) |
| `warrior.gd` (Kampf) | Nahkampf voll: `MELEE_STRENGTH = 3.0`, 120 HP, schubst selten, nur Nahkampf |
| Brave/Aggro | **Braves wehren sich** (retaliieren gegen Angreifer, kein Fliehen, kein Distanz-Aggro). Kampfeinheiten im IDLE greifen Feinde im Aggro-Radius an (IDLE→ATTACK) |
| Rechtsklick-Angriff | Rechtsklick auf Feindeinheit → Angriff; intelligente Verteilung (Ziel voll → anderes Feindziel in Reichweite / Selbstverteidigung) |
| `tests/test_combat.gd` | siehe Tests (Nahkampf-Teil) |

### Umsetzungsschritte

1. `take_damage`/Tod/Despawn + Zielsuche-Timer + `MELEE_*` in `unit.gd`.
2. Prügel-Angriffsarten + Slot-System (max. 3, Aufstellung, Warteschlange, 1v1) → `warrior.gd`.
3. Brave-Verteidigung + Aggro + Rechtsklick-Angriff mit Verteilung.
4. Verifikation + manuelle Prüfung.

### Tests (`tests/test_combat.gd`, Nahkampf-Teil)

- **Schadensrechnung:** `take_damage` reduziert HP; bei ≤0 → DEAD, `unit_died` gefeuert,
  Einheit aus Tribe-Liste und Spatial-Hash entfernt.
- **Nahkampf-Tick:** Angreifer + Feind in Range → nach `attack_cooldown`-Ticks hat Feind
  Schaden; außer Range → Angreifer bewegt sich zum Ziel.
- **Krieger-Stärke:** Krieger fügt pro Treffer 3× so viel Schaden zu wie ein Brave.
- **Nahkampf-Slots:** Max. 3 Angreifer registrieren sich am Ziel; ein 4. wartet (kein Slot);
  stirbt einer der drei, rückt der Wartende nach. Ziel bekommt bei 3 Angreifern ~3× Treffer/Zeit.
- **1v1-Bevorzugung:** Bei zwei freien Feinden und zwei Angreifern greift jeder ein eigenes Ziel
  an, statt sich beide auf dasselbe zu stürzen.
- **Aggro/Verteidigung:** Feind im Aggro-Radius → IDLE-Krieger wechselt in ATTACK; **Brave
  wechselt bei Angriff in Verteidigung (schlägt zurück), flieht nicht** und aggrot nicht über
  Distanz.

### Definition of Done 5b

- [x] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuell: Rechtsklick auf Feind → Prügelkampf; max. 3 hauen auf einen Gegner ein,
  Überzählige warten/rücken nach; bei mehreren freien Gegnern verteilen sich die eigenen
  Einheiten; Krieger deutlich zäher/härter; Braves wehren sich statt zu fliehen
- [x] `git add -A && git commit -m "Phase 5b: Nahkampf-Kern (Slots, Krieger, Aggro)" && git push`

---

## Sub-Phase 5c — Fernkampf & Prediger

**Fokus:** Feuerkrieger-Fernkampf (Feuerball + Rückstoß) und Prediger-Konvertierung inkl.
Priester-Duell und Feuerkrieger-Reset. Referenz: „Fernkampf“ + „Prediger-Verhalten“ oben.

### Deliverables

| Datei | Inhalt |
|---|---|
| `scripts/units/firewarrior.gd` (Fernkampf) + `scripts/units/fireball.gd` + Szene | Fernkampf auf mittlere Range (spawnt `Fireball`); **Rückstoß-Akkumulator** pro Ziel (Salven stärker); Feuerball-Hand-Sprite verschwindet kurz nach dem Feuern; im Nahkampf **keine** Feuerbälle → Fallback auf Prügelkampf aus 5b. `Fireball` = `Node3D`, oranges SphereMesh unshaded, fliegt getickt (leichter Bogen) zum Ziel, Treffer = Distanzcheck im `tick` → Schaden genau einmal + Rückstoß + Despawn |
| `scripts/units/preacher.gd` (Konvertierung) | Ziel in Range → Ziele setzen sich / hören auf zu kämpfen, `conversion_progress` mit Zufallszeit → Tribe-Wechsel. Priester-Duell (Bekehrung bricht ab, Gegner greifen mit an). Kampf-Trägheit. Konvertiert keine Schamanin/Prediger |
| Feuerkrieger-Reset | Feuerangriff auf ein konvertierendes Ziel setzt dessen `conversion_progress` zurück (Feuerkrieger hat höhere Reichweite) |
| `tests/test_combat.gd` (Ergänzung) | siehe Tests (Fernkampf-/Prediger-Teil) |

### Umsetzungsschritte

1. `fireball.gd` (Projektil-Tick, Einmaltreffer, Schaden) + `firewarrior.gd`-Fernkampf +
   Rückstoß-Akkumulator + Hand-Sprite-Toggle; Nahkampf-Fallback verifizieren.
2. `preacher.gd`: Konvertierung (Sitzen, Zufallszeit, Tribe-Wechsel), Priester-Duell,
   Kampf-Trägheit, Feuerkrieger-Reset.
3. Verifikation + manuelle Prüfung.

### Tests (`tests/test_combat.gd`, Fernkampf-/Prediger-Teil)

- **Fireball:** fliegt getickt zum Ziel, wendet Schaden **genau einmal** an, despawnt; erzeugt
  Rückstoß; mehrere schnelle Treffer → größerer akkumulierter Rückstoß.
- **Feuerkrieger-Nahkampf:** in Nahkampf-Range setzt er keine Feuerbälle ein, Schaden = Brave.
- **Konvertierung:** Preacher + Feind-Brave in Range → Ziel setzt sich, `conversion_progress`
  steigt; bei Abschluss ist die Einheit in `tribes[0].units` statt `tribes[1].units`, `tribe_id`
  gewechselt. Prediger/Schamanin als Ziel → kein Fortschritt.
- **Priester-Duell:** feindlicher Prediger in Reichweite → Bekehrung bricht ab (Ziele stehen
  auf), beide Prediger im Nahkampf.
- **Feuerkrieger-Reset:** Feuerangriff auf ein konvertierendes Ziel setzt dessen
  `conversion_progress` zurück.

### Definition of Done 5c

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuell: Feuerkrieger beschießen aus Distanz mit sichtbaren Feuerbällen (Rückstoß, bei
  Salven stärker), prügeln sich im Nahkampf; rote Einheiten setzen sich vor dem Prediger hin und
  werden blau; feindlicher Prediger löst Duell aus; Feuerangriff setzt Bekehrung zurück
- [ ] `git add -A && git commit -m "Phase 5c: Fernkampf & Prediger" && git push`

---

## Sub-Phase 5d — Bewegung, Rollen & Politur

**Fokus:** Hügel-Bewegung, Rollmechanik, Regeneration, Sterne-Overlay und Kampf-Sounds. Bindet
die Hooks aus 5b (Schubs) und 5c (Rückstoß) an das Rollen an; Sounds hängen sich in die
Treffer-Ereignisse aus 5b/5c ein. Referenz: „Bewegung“ + „Leben, Regeneration, Sounds“ oben.

### Deliverables

| Datei | Inhalt |
|---|---|
| Bergauf-Verlangsamung in `unit.gd` | Effektive Geschwindigkeit skaliert mit der Steigung in Laufrichtung (aus `TerrainData`-Höhen) |
| `State.ROLL` in `unit.gd` | Auslöser: Steilheit (sehr steil, ohne Kampf), **Feuerball-Rückstoß aus 5c**, **seltener Schubs aus 5b**. Y-Snapping/Separation ausgesetzt; endet erst unter Steigungs-Schwelle; Wasser (< `sea_level`) → sofort tot; Rollschaden über Zeit; **aufgeschobener Tod** (erst am Rollende); Landeposition auf begehbare Zelle clampen |
| Regeneration | `REGEN_DELAY` ohne Kampf → langsame Heilung bis `max_health` |
| „Sterne“-Overlay | Bei großem Schaden kurz kreisende Sterne über dem Kopf (Billboard-Sprite, prozedural). **HP wird nie angezeigt** |
| `scripts/core/combat_audio.gd` (oder in UnitManager) | Prozedurale `AudioStreamWAV`-Sätze je Angriffsart; pro Treffer zufällig eines abspielen, gepoolt/gedrosselt; in die Treffer aus 5b/5c eingehängt |
| `tests/test_combat.gd` (Ergänzung) | siehe Tests (Bewegungs-/Roll-/Regen-Teil) |

### Umsetzungsschritte

1. Bergauf-Verlangsamung + `State.ROLL` (Auslöser, Wasser-Tod, Rollschaden, aufgeschobener Tod).
2. Regeneration + „Sterne“-Overlay.
3. `combat_audio.gd` + Einhängen in die Treffer aus 5b/5c.
4. Verifikation + manuelle Prüfung.

### Tests (`tests/test_combat.gd`, Bewegungs-/Roll-/Regen-Teil)

- **Bewegung/Rollen:** Bergauf reduziert die effektive Geschwindigkeit; Roll-Auslöser →
  `State.ROLL`; Ende erst unter Steigungs-Schwelle; Ziel unter `sea_level` → sofort tot;
  HP≤0 während des Rollens → Tod erst am Rollende.
- **Regeneration:** nach `REGEN_DELAY` ohne Kampf steigt HP wieder; im Kampf nicht.

### Definition of Done 5d

- [ ] Testsuite grün, `--headless --quit` fehlerfrei
- [ ] Manuell: Einheiten laufen bergauf langsamer; an sehr steilen Hängen / durch Feuerball-
  Rückstoß / (selten) Schubs rollen sie hinab; Rollen ins Wasser tötet sofort; Sterne bei viel
  Schaden; verletzte Einheiten heilen außerhalb des Kampfes; verschiedene Sounds je Angriffsart
- [ ] Checkbox Phase 5 in [00_overview.md](00_overview.md) abgehakt (Phase 5 komplett)
- [ ] `git add -A && git commit -m "Phase 5d: Bewegung, Rollen & Politur" && git push`
