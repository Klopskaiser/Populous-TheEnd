# Projekt: Populous-TheEnd (Godot-RTS)

> ⚠️ **Sonderfall – kein proALPHA/ABL.** Dieses Projekt ist eine **Ausnahme** vom üblichen
> proALPHA-Q0/LIT-Arbeitsablauf. Es handelt sich um ein **Godot-4-Spielprojekt** (GDScript),
> nicht um ABL-/OOABL-Code. Deshalb gilt hier **NICHT**:
> - kein Progress/ABL, keine `.cls`/`.p`/`.w`/`.i`-Quellen, keine ABL-Coderichtlinien;
> - kein PROPATH / keine `propath.txt` bzw. `.propath`, keine „Kundenanpassung-vor-Standard"-Logik;
> - **keine MCP-Server** – `ProalphaGate` und `lit-dev` sind hier nicht anwendbar und dürfen
>   nicht aufgerufen werden (kein Compile/Check/Format über MCP).
>
> Die allgemeinen/globalen Regeln aus der Benutzer-`CLAUDE.md` bleiben unverändert; dieser
> Sonderfall wird ausschließlich hier lokal dokumentiert. Alle Erkenntnisse zu diesem Projekt
> bleiben auf dieses Projekt beschränkt. Verifikation erfolgt über die Godot-CLI (headless)
> und den Godot-Editor (siehe §9).

---

## 1. Projektüberblick

**Populous-TheEnd** ist ein Echtzeit-Strategiespiel im Stil von **„Populous: The Beginning"**
(Bullfrog, 1998), umgesetzt in **Godot 4.7** mit GDScript.

- **Modus:** Nur **Skirmish** (1 menschlicher Spieler gegen KI). Keine Kampagne.
- **Kamera:** Frei drehbare RTS-Kamera aus der Vogelperspektive (isometrisch anmutend).
- **Kernschleife:** Stamm aufbauen (Hütten → Bevölkerung → Mana), Braves zu Kampfeinheiten
  ausbilden, mit Schamanin + Truppen den gegnerischen Stamm vernichten.
- **Out of Scope (bewusst ausgeschlossen):** Kampagne, Spione, Boote, Ballons.

## 2. Engine, Werkzeuge & Befehle

- **Engine:** Godot **4.7 stable** (Windows, 64-bit).
- **Executable:** `C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`
  (im Folgenden `$GODOT`; Achtung: der äußere Eintrag `…win64.exe` ist ein **Ordner**,
  die eigentliche Exe liegt gleichnamig darin). Falls die Exe verschoben wird, nur
  diesen Abschnitt anpassen.
- **Sprache:** GDScript (typisiert, siehe §8).

```powershell
$GODOT = 'C:\Users\johannes.wutzke\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'

& $GODOT --path D:\game\Populous-TheEnd --editor            # Editor öffnen
& $GODOT --path D:\game\Populous-TheEnd                     # Spiel starten (Hauptszene)
& $GODOT --path D:\game\Populous-TheEnd --headless --import # Assets importieren (headless)
& $GODOT --path D:\game\Populous-TheEnd --headless --check-only --script <pfad>.gd
                                                            # Syntax-Check eines Skripts
& $GODOT --path D:\game\Populous-TheEnd --headless --quit   # Projekt headless laden & beenden
                                                            # (Lade-/Parse-Fehler im Output)
```

- **Verifikation ohne MCP:** Nach Skript-Änderungen `--check-only` bzw. headless-Start
  nutzen; Fehler erscheinen auf stdout/stderr. Funktionaler Test über Editor/Spielstart.

## 3. Grafik & Rendering

- **Terrain:** 3D-Terrain. **Wichtig für die Architektur:** Das Terrain muss zur Laufzeit
  verformbar sein (Zauber *Landbridge* hebt Land an; optional später weitere Verformung).
  Deshalb kein statisches Mesh, sondern ein **Heightmap-basiertes Mesh**, dessen Höhenwerte
  zur Laufzeit geändert und neu vernetzt werden können (inkl. Aktualisierung von Kollision
  und Navigation).
- **Die Welt ist eine Scheibe im Weltall (Phase 10j).** Begehbar ist nur der in das
  quadratische Höhenraster **einbeschriebene Kreis**; außerhalb ist der **Void** —
  kein Boden, keine Zelle, kein Mesh. Einziger Hebel ist die Maske in
  `TerrainData.is_walkable()`/`is_grass()`: weil `NavGrid.update_region()` der
  **einzige** Solidity-Writer ist, ziehen A-Stern, PathWorker, Fahrzeuggitter,
  Insel-Labels, Baum-/Einheiten-Spawns und `can_place_at` automatisch mit. Ein
  Terrain-Zauber kann die Scheibe damit **nicht vergrößern**. `has_ground(x, z)`
  antwortet auf „ist hier Boden?" — `get_height()` clampt seine Eingaben weiterhin
  und liefert draußen die Randhöhe, ist also KEINE Gültigkeitsprüfung.
  Rand: Die Silhouette ist **rund**, weil `vertex_mesh_xz()` die Mesh-Randvertices
  radial auf den Kreis zieht (Begehbarkeit bleibt zellbasiert). Darunter kurze
  Felskante und ein **umgedrehter Kegel mit abgerundeter Spitze** (`TerrainRim`);
  Wasserfall nur dort, wo der Rand unter der Wasserlinie liegt (heute nur die Insel) —
  er stürzt **senkrecht** und folgt dem Kegel bewusst nicht. Hintergrund ist ein
  **Sternenhimmel** (`shaders/starfield.gdshader`); das Ambient-Licht bleibt
  zwingend `AMBIENT_SOURCE_COLOR`, sonst wird die Karte unlesbar dunkel.
- **Gebäude:** 3D-Modelle (platzierbar auf dem Terrain, an Geländehöhe ausgerichtet).
- **Einheiten:** **2D-Sprites mit Billboarding** – `Sprite3D`/`AnimatedSprite3D` mit
  `billboard = BILLBOARD_ENABLED`, immer zur Kamera gedreht.
  Benötigte Animationen pro Einheit: **Idle, Walk, Attack, Cast** (Cast nur Schamanin/Prediger).
  **Idle läuft NICHT in Dauerschleife:** eine herumstehende Einheit hält ihre
  **Ruhepose** (`stand`, eine Spalte je Blickrichtung) und spielt die Idle-Animation
  im Schnitt alle 8 s **einmal** daraus heraus — gestreut über die Einheiten
  (`Balance.UNIT_IDLE_ANIM_INTERVAL`/`_JITTER`, `UnitRenderer.idle_frame`), weil
  hunderte dauernd wippende Figuren das Spielbild unruhig machten. Der Zeitpunkt ist
  **gehasht statt gewürfelt** (kein `randf()`, damit der geseedete Test-RNG-Strom
  unberührt bleibt) und deshalb zustandslos. Fehlt `stand.png`, ruht die Einheit auf
  **Frame 1 ihres eigenen `idle.png`** — die einzige Animation, deren Fehlen nicht
  auf den Platzhalter zurückfällt.
  **Liegende Posen (`dead`, `airborne`) werden aufrecht in die hochkante
  Sprite-Zelle gezeichnet und vom Renderer um 90° auf dem Bildschirm gerollt**
  (`PlaceholderSprites.FLAT_ANIMS`, `UnitRenderer.LIE_ROLL`): so wird die
  **lange** Zellachse zur Körperlänge und die Leiche ist so lang wie die Figur
  hoch — liegend gezeichnet wäre sie nur 0,96 statt 1,44 m. Der Roll ist **eine
  feste Richtung** (Kopf nach rechts); welche Körperseite man sieht, trägt die
  **Zeichnung**. Beide liegenden Posen sind **blickrichtungslos**
  (`PlaceholderSprites.VIEWLESS_POSES`) — ein Körper am Boden oder in der Luft
  hat keine Vorderseite, um die die Kamera laufen könnte. Die acht Slots ihrer
  Atlas-Zeile tragen deshalb **Varianten** statt Ansichten, gespiegelt wird
  nichts, und ein geliefertes Sheet hat **eine Zeile je Variante**:
  - **`dead`** hat zwei Varianten — `dead_back.png` (liegt auf dem **Rücken**,
    also von der Vorderseite gezeichnet, Gesicht sichtbar) und `dead_front.png`
    (liegt auf dem **Bauch**, also ihr Rücken gezeichnet). Der Dateiname meint
    die **Lage**, nicht die sichtbare Seite. Welche eine Einheit bekommt, wird
    einmal je Einheit gewürfelt: **40 %** Bauchlage
    (`Balance.LIE_FACE_DOWN_CHANCE`). Beide Dateien oder keine.
  - **`airborne`** fällt immer bauchwärts und hat deshalb nur **eine** Variante
    (Platzhalter: die `back`-Ansicht, also der Rücken zum Betrachter).
  `roll` (Purzeln am Boden) und `drown` bleiben aufrecht und behalten ihre acht
  Ansichten.

- **Wirbelsturm-Optik (2026-11-15):** der Trichter ist reine Shader-Arbeit
  (`TornadoVisual`, `shaders/tornado_funnel.gdshader`, `tornado_specks.gdshader`) —
  vier Draw Calls je Tornado, kein Tick im Stand, keine Partikel, kein Bildschirm-
  oder Tiefenpuffer-Zugriff. **Hochgewirbelte Einheiten müssen erkennbar bleiben
  (Nutzervorgabe):** der dichte Kern bleibt innerhalb der Reiterbahn
  (`0,8 * radius_at_height`), und vor einem Reiter liegt höchstens die dünne
  kameranahe Schleierwand. Beide Regeln stehen als Konstanten in `TornadoVisual`;
  beim Nachstellen der Optik `tests/diag_tornado_look.gd` laufen lassen (rendert
  Standbilder mit Sprites auf der Reiterbahn, **ohne** `--headless`).

- **Lava-Optik (2026-11-15):** jede Lava (Decke `LavaSurge`, Strom `LavaFlow`) zeichnet mit
  `shaders/lava.gdshader` (`LavaCommon.make_material`): träge wälzende Schmelze, Krustenplatten,
  glühende Adern, ausgefranster Rand. Die Altersfarbe aus `LavaCommon.color_for` bleibt die
  Grundfarbe (hell = frisch und tödlich); der Shader bekommt je Vertex `UV.x` = Hitze und
  `UV.y` = Deckung. **Die Decke liegt auf dem GITTER DES GELÄNDES** (`LavaSurge._rebuild_mesh`:
  dieselben Vertices und dieselbe Dreiecksteilung wie `Terrain`, um `SURFACE_LIFT` 8 cm
  angehoben) — vorher schnitt ein polares Ringnetz Sehnen durch das gewölbte Gelände und der
  Fels stach durch (zweimal gemeldet). Der ausgefranste Rand ist keine Geometrie mehr.
- **Wasserfall (2026-11-15):** `shaders/waterfall.gdshader` ist **unshaded** (er hing als
  beleuchtete Fläche im Void und war fast schwarz) und rechnet den Fallanteil aus
  `height_tiles` — vorher las die Ausblendung `UV.y` als 0..1, obwohl es in Kacheln läuft, und
  der 34-m-Fall war schon 8 m unter der Kante unsichtbar. Der Vorhang hängt weiter senkrecht
  (Netz, Tests); nur an der Kante schießt das Wasser im Shader in einem kurzen Bogen hinaus
  (`arc_out` 1,4 m), dafür hat das Netz `TerrainRim.WATERFALL_ROWS`. **Fließrichtung:** `UV.y` wächst nach unten, ein fallendes Muster braucht also `y - t` — mit `y + t` kletterten die Streifen den Vorhang hinauf (Bugmeldung 2026-11-15, behoben). Beides ansehen mit
  `tests/diag_lava_waterfall_look.gd` (ohne `--headless`).

## 4. Einheiten & Steuerung

| Einheit | Rolle |
|---|---|
| **Schamanin** | Wichtigste Einheit, einzige Zauberwirkerin. **HP = 4 × Brave**, **Nahkampfschaden = 2 × Brave**. Stirbt sie, **respawnt** sie nach einer Wartezeit am **Reinkarnationsplatz** (Reincarnation Site); der Stamm des Tötenden bekommt einmalig **10 % der minütlichen Manaproduktion ihres Stammes** auf seine aktiven Aufladeraten verteilt. Pro Stamm genau eine. |
| **Brave (Gefolgsmann)** | Basis-Einheit. Sammelt **passiv Holz** und baut Gebäude aus. Wird von Hütten gespawnt. |
| **Techniker** | Ausbildung in der **Ausbildungshalle** (10 s). Werte wie ein Brave, Nahkampf **50 % Tritt / 50 % Schlag** (kein Schubser). Zivil **baut und repariert** er wie ein Brave, **fällt aber nie einen Baum** und **bemannt keine Hütten** — er verbaut nur Holz, das schon in Reichweite liegt (Stapel/Holzstation). Sein Wert liegt an Bord: **jedes Fahrzeug mit mindestens einem Techniker fährt 33 % schneller** (einmalig, stapelt nicht). **Katapult:** +33 % Feuerrate vom ersten Techniker, **+10 % je weiterem, additiv** (6er-Crew = +83 %). **Feuerramme:** vom ersten **kein** Feuerratenbonus — stattdessen sind **die Techniker an Bord** (nur sie) feuer-, panik- und bekehrungsresistent; jeder weitere gibt +10 % (4er-Crew = +30 %). **Luftschiff:** repariert die Hülle wie die Feuerramme ihre Feuer-Leben (1 Trefferpunkt je 30 s, bei `AIRSHIP_HULL_HITS = 2` also genau ein zurückgewinnbarer Treffer, das Hüllenfeuer geht dabei aus), und **jeder Techniker nach dem ersten** gibt **allen Insassen** einen **Stärke**-Stack. Boni zählen nur für Techniker, die wirklich am Posten sind (dieselben Bedingungen wie `active_crew_count`) — ein bekehrter, panischer oder zu Fuß kämpfender Techniker zählt nicht. **Ein BRENNENDER Techniker auf der Feuerramme schon** (2026-09-10): die Ramme fährt durch ihren eigenen Flammenkegel und zündet dabei ihre Besatzung an, und mit der Feuerresistenz ist das folgenlos (5 statt 15 HP/s, keine Panik) — sie bedient und feuert weiter, statt die Ramme neutral werden zu lassen. Die Ausnahme hängt am **Buff**, nicht an der Einheitenart: ein brennender Brave auf derselben Ramme und ein brennender Techniker auf dem Katapult (dort gibt es die Aura nicht) fallen wie bisher aus. |
| **Krieger** | Nahkampf-Einheit. Ausbildung in der **Kaserne** (Krieger-Trainingslager). Nahkampf-Multiplikator **2,5 x Brave** (2026-09-07, vorher 3,0), dafuer haeufiger der harte Tritt: **65 % Schlag / 35 % Tritt**, er **schubst nicht mehr**. |
| **Feuerkrieger** | Fernkampf-Einheit (Feuerbälle). Ausbildung im **Feuertempel** (Feuerkrieger-Trainingslager). **Zielwahl: Reichweite schlägt Priorität** (2026-09-06, `Firewarrior._retarget_by_reach`/`_scan_for_enemy`): ein Priester **innerhalb** der Feuerreichweite (9 m, seit 2026-09-06; vorher 8) geht immer vor; steht das Ziel außer Reichweite, wird geschossen, wer schon in Reichweite steht, statt zu verfolgen; erst wenn niemand schießbar ist, wird ein Priester bis zum Aggro-Radius (13 m) gejagt. Vorher zog ein Priester irgendwo im Aggro-Radius die Feuerkrieger an den Gegnern vor ihrer Nase vorbei. Der Feuerball macht **Flächenschaden** (**30 %** des Hauptschadens im Umkreis von **1,3 m**, **nur Feinde**, kein Rückstoß auf Umstehende) — ohne ihn teilten Feuerkrieger viel Schaden aus und töteten fast nichts. Der Radius ist an der Einheitengeometrie ausgerichtet: 1,3 m fasst **ein 6er-Pack** (max. 1,10 m breit) bzw. eine Nahkampfgruppe (0,9-m-Ring) und lässt die Nachbargruppe (2,2 m) draußen. Gemessen **flach in XZ**, der Bereich ist also ein senkrechter Zylinder. **Die Wirkung skaliert mit der Dichte:** im 200er-Klumpen nimmt fast jeder Ball ~3 Umstehende mit, bei 20 gegen 20 meist keinen — Feuerkrieger sind damit bewusst eine **Masseneinheit**. **Der Ball gleitet ueber den Boden** (2026-09-07, `Fireball._follow_ground_or_block`): der Boden ist eine **Untergrenze**, keine Wand — der Ball wird auf 0,8 m ueber Grund angehoben und nimmt Kuppen, Rampenkanten und Heightmap-Wellen mit, wie die Flamme der Feuerramme. Vorher flog er auf einer geraden 3D-Linie mit knapp einem Meter Bodenfreiheit und **verpuffte still** an jeder Erhebung dazwischen. Nach **unten** wird er nie gedrueckt: Schuesse vom Wachturm/Luftschiffdeck und die Jagd auf Luftziele behalten ihre Hoehe. Eine echte **Steilwand blockt weiter** — Grenze ist `TerrainData.MAX_SLOPE` (1,5 m je Meter), also genau die Begehbarkeitsgrenze: *der Ball kommt ueber alles, was eine Einheit hochlaufen koennte.* Im **Nahkampf** schubst (40 %) und tritt (60 %) er nur noch — den Faustschlag hat er nicht mehr. |
| **Prediger** | **Konvertiert** feindliche Einheiten zum eigenen Stamm. Ausbildung im **Tempel**. Im Nahkampf **schubst** er (60 %) statt zu verletzen und **tritt gar nicht** (2026-09-07); 40 % bleiben der Faustschlag. Mehrere Prediger verteilen sich auf verschiedene Ziele; **Einheiten in Bekehrung sind kein gültiges Ziel** für Nah-/Fernkampf (Katapult ausgenommen). Eine **kämpfende feindliche Schamanin** im Umkreis von 6 m **unterbricht die Predigt** — laufende Bekehrungen brechen ab, neue beginnen nicht, und das gilt für alle Prediger in ihrem Radius. Bloßes Herumstehen stört nicht. **Gegnerische Prediger singen hörbar anders** als die eigenen (`preach_enemy` statt `preach`, Perspektive Spieler) — eine fremde Predigt soll man erkennen. **Luftschiffinsassen sind kein Bekehrungsziel** (am Deck unerreichbar) und werden gar nicht erst gewählt — weder vom Prediger am Boden noch von einem im Wachturm oder auf einem Deck, und ein Rechtsklick darauf wird abgewiesen. **Im Angriffsmove bekehrt der Prediger, was er trifft, und marschiert danach weiter** zum Zielpunkt wie jede andere Einheit (`Preacher._resume_route_or_idle`, 2026-09-06 — vorher endete jede Predigt in IDLE und die Route war vergessen); die KI schont Prediger mitten in der Bekehrung bei ihrem Wellen-Refresh (`_marching_only` überspringt `State.CAST`). |
| **Belagerungswaffe (Katapult)** | Fernkampf-Fahrzeug mit Crew, gebaut in der **Werkstatt** (Phase 7f). **Zielsuche wie bei den Fußtruppen** (2026-09-08): Katapult, Feuerramme und Luftschiff scannen über `UnitManager.get_enemy_candidates` — dort verbrauchen eigene Einheiten und Leichen keine Kandidatenplätze. Vorher fraß die eigene Welle das Budget der gekappten Abfrage auf, und ein Fahrzeug im Angriffsmove fuhr mitten durch erreichbare Feinde hindurch. Feindliche **Fahrzeuge** kommen aus einem zweiten Durchgang (`get_enemy_vehicles_in_radius`), weil sie nicht anvisierbar sind und der Zellenvorfilter sie sonst wegmaskiert. |
| **Golem** | **Beschworene Riesin** (Zauber 13, 2026-09-06), neben den Fahrzeugen die einzige Einheit mit **3D-Modell**: seit 2026-11-15 eine **schlanke Figur, mit der Statur einer wachturmhohen Figur (`GOLEM_BUILD_HEIGHT` 5,25 m: Körperbox 1,55 m breit × 1,22 m tief), aber 10 % niedriger (`GOLEM_HEIGHT` 4,73 m — sie wirkte zu schlank)** (vorher ein 4 m hoher, 4 × 3 m breiter Klotz), `models/units/golem.glb` optional mit Skelettanimation (`idle`/`walk`/`slam`/`kick`/`kick_l`/`swat`/`swipe`/`drum`/`death`, dazu für die gebückte Haltung `crouch_idle`/`crouch_down`/`crouch_up`/`slam_low`/`drum_low` und fürs Wachsen `grow`; `idle` ist seit 2026-11-15 das auf 20,5 s gekürzte **Idle 1** der Figur: Gewicht wandert von Bein zu Bein, das entlastete hebt die Ferse, der Kopf legt sich zur Seite, die Hände spreizen sich ab), sonst prozeduraler Platzhalter gleicher Größe. Das Modell ist auf 4 m gebaut; das Spiel skaliert Breite/Tiefe mit `GOLEM_BUILD_HEIGHT` und die Höhe mit `GOLEM_HEIGHT`. **Stammesfarbe trägt die Krawattenschleife** (Netz `Flag`); die Schuhe bleiben weiß, mit grau abgesetzten Kreuzbändern. Beim Beschwören **steigt sie in 0,9 s aus dem Boden** (nur Optik). **800 LP**, 3,5 m/s, lebt **180 s + 6 s je Kill**, dann zerfällt er (400/+3 nach dem ersten Spieltest verdoppelt). Jeder Kill **heilt ihn zusätzlich um 10 LP** (`Balance.GOLEM_HP_PER_KILL`) und **hebt seine Lebensobergrenze um 5** (`GOLEM_MAX_HP_PER_KILL`, 2026-11-15) — **höchstens bis 1000** (`GOLEM_MAX_HP_CAP`, nach 40 Kills). **Auch ein vom Golem zerstörtes Gebäude zählt als ein Kill.** Die Obergrenze **gilt**: Kill-Heilung und Dauerheilung enden an ihr — sie wächst nur über Kills (sonst heilte er sich passiv unendlich hoch). **Stufen (Nutzervorgabe 2026-11-15):** er beginnt auf **Stufe 0** und steigt nach **5, 6, 7, 7, 8 und 9 Kills** je eine Stufe auf (`Balance.GOLEM_LEVEL_KILLS`, 2026-11-15 — vorher 6 je Stufe; aufsummiert 5, 11, 18, 25, 33, 42), bis **Stufe 6** (`Golem.level`, `level_for_kills`); **Stufe 7** braucht 45 weitere (87, s. u.); Kills durch Angriffe und durch Trampeln zählen. **Je Stufe:** +20 s Lebenszeit (einmalig), **+3 LP/s Dauerheilung** (Stufe 1: 3/s, Stufe 6: 18/s — auch im Kampf, bis zur Lebensobergrenze), **+5 Schaden** auf Handschlag und Tritt, und der **Körper wird 20 % größer als auf der Stufe davor** (aufgezinst, Nutzervorgabe: 1,2 hoch Stufe — Stufe 6 ist das 2,99-Fache, 14,1 m; das Modell wächst sichtbar). **Beim Wachsen streckt er sich** (`_tick_stretch`, 2026-11-16): bei jedem Stufenaufstieg und jedem Wachstumsschritt nach Stufe 7 reckt er sich einmal (Clip `grow`, Sound `golem_grow`) — **0,5 s** (`GOLEM_GROW_TIME`), in denen er weder angreift noch läuft. Eine laufende Angriffsanimation wird vorher zu Ende gespielt, und solange das Strecken aussteht, beginnt er keinen neuen Angriff; danach **steht** er (aus der gebückten Haltung richtet er sich dabei auf) und darf sofort weitermachen, auch sich sofort wieder bücken. **Die Wirkflächen wachsen langsamer als der Körper: 10 % je Stufe** (`reach_factor()`, 1,1 hoch Stufe, skaliert den Radius des Handschlags und die Breite der Schneise — Stufe 6: 1,77-fach, also Kreis 4,6 m, Schneise 3,2 m breit). **Die Reichweite wächst dagegen mit den Gliedern** (`limb_factor()` = Größenfaktor hoch 0,83, 2026-11-16 — vorher wuchs auch sie nur 10 % je Stufe und der große Golem musste fast auf sein Ziel treten): der Exponent ist so gewählt, dass bei 100 m **60 %** des rein körperproportionalen Werts herauskommen (`GOLEM_LIMB_SHARE_AT_MAX`). Der **Zuwachs** daraus fällt über alle Stufen noch einmal **10 % stärker** aus (`GOLEM_LIMB_GROWTH_BONUS`, 2026-11-16: Gliederfaktor = 1 + (Größe^0,83 − 1) × 1,1). Am Gliederfaktor hängen die **Reichweite** (Stufe 6: 7,9 m, Stufe 7: 11,2 m, 100 m: 41,6 m), die **Länge der Tritt-Schneise** (Stufe 6: 11,2 m vor und 7,8 m zurück) und der **Abstand des Handschlag-Aufschlagpunkts** (Stufe 6: 3,2 m vor ihr), das **Tempo mit der Wurzel der Größe** (3,5 → 6,05 m/s auf Stufe 6 — die Schritte werden länger, die Schrittfolge etwas ruhiger). **Auch die Angriffsanimationen werden mit der Größe langsamer** (`attack_speed()`, 2026-11-15: Abspieltempo 1/Wurzel der Größe, die Ausholzeit wächst entsprechend) — **aber nie langsamer, als die Abklingzeit erlaubt**: spätestens wenn der Clip die 1,8 s füllt, ist Schluss (Handschlag ab Stufe 2 mit 0,96 s Ausholzeit, Tritt und Luftschlag ab Stufe 5 mit 0,75 s). **Der Angriffstakt wächst mit** (`strike_cooldown()`, 2026-11-15 — ersetzt „der Takt bleibt 1,8 s“): linear in der Körperhöhe von 1,8 s bei Startgröße bis **4 s bei 100 m** (`GOLEM_STRIKE_COOLDOWN_MAX`; Stufe 7: 2,18 s); die Animationen strecken sich mit und füllen ab den mittleren Stufen die ganze Abklingzeit, ohne Idle dazwischen. **Drehrate** (`turn_rate()`, `_slew_heading`): der Körper folgt der Blickrichtung nicht mehr augenblicklich, sondern mit 8 rad/s bei Startgröße, linear fallend bis **70 % der Feuerrammen-Drehrate bei 100 m** (1,4 rad/s, halbe Drehung in 2,2 s); angegriffen wird erst, wenn er bis auf 25° zum Ziel gedreht ist (`is_turned_to_facing`), Angriffe landen in der echten Körperrichtung (`heading()`), und solange er sich dreht, läuft er langsamer (mindestens 20 % seines Tempos). **Ab Stufe 1** ignoriert er die **Kollision mit Einheiten** (`UnitManager.FLAG_NO_COLLISION`: er nimmt an der Abstandsregelung nicht mehr teil und schiebt niemanden weg; **Golems untereinander halten dagegen immer Abstand** — `_tick_golem_separation`, 2026-11-16: zwei Golems, egal welcher Stufe und welchen Stamms, können nicht ineinander stehen, sie halten die Summe ihrer Körperradien Abstand und schieben sich sonst auseinander, der kleinere weicht stärker aus) und **trampelt**: jeder Feind unter seinem Körper (Radius 0,78 m × Größe) nimmt **Trampelschaden nach Größe** (`trample_damage()`, 2026-11-15: Körperhöhe in Metern / 5, gerundet, mindestens 1 — Stufe 1: 1, Stufe 6: 3, Stufe 7: 4, bei 100 m: 20; kein Stufenbonus mehr), solange er **läuft** (schneller als 0,5 m/s) — im Stehen nie, eigene Einheiten nie, dasselbe Opfer höchstens einmal je Sekunde. **Die Endboni gibt es ab Stufe 6 (`GOLEM_FINAL_BONUS_LEVEL`): die Lebenszeit läuft nicht mehr ab, und er jagt Luftschiffe:** steht ein bemanntes feindliches Luftschiff in seiner Reichweite (flach gemessen, dieselbe wie am Boden — auf Stufe 6 also 5,3 m), holt er mit einem eigenen Schlag nach oben aus (`Golem.ATTACK_SWAT`, Clip `swat`, Aufschlag nach 0,5 s; im selben 1,8-s-Takt, auch im Gehen und Stehen, und vor den Feinden am Boden). Jeder Treffer ist **ein Hüllentreffer wie beim Katapult** (`Airship.register_hull_hit`) — **zwei zerstören das Schiff**. Eigene und neutrale (unbemannte) Schiffe schlägt er nie. **Die Animation richtet sich nach der Höhe des Schiffs am Körper** (`_clip_for`, 2026-11-15 — Luftschiffe fliegen auf 10 m, ein Schlag nach oben passt beim 14-m-Golem nicht mehr): über 80 % der Körperhöhe der Schlag nach oben (`swat`), zwischen 40 und 80 % ein waagerechter Schwinger (`swipe`), darunter ein Tritt; Wirkung, Reichweite und Ausholzeit sind dieselben. **Er verfolgt Luftschiffe** (`_tick_air_chase`): steht er untätig, läuft er einem bemannten feindlichen Schiff im Umkreis von 25 m (`GOLEM_AIR_CHASE_RADIUS`) im Angriffsmove nach und zielt alle 0,7 s neu — aber nur, wenn er eine Stelle in Schlagweite des Schiffs **zu Fuß erreichen** kann (`_chase_point`: begehbar und dieselbe Insel; ein Schiff über offenem Wasser lässt er ziehen). Jeder Befehl von außen beendet die Verfolgung. **Stufe 7, der Gigant** (87 Kills): der Körper wächst noch einmal um **50 %** (4,48-fach, 21,2 m), Reichweite und Wirkflächen um **25 %** (2,21-fach: Kreis 5,8 m, Schneise 4,0 m breit; Reichweite 11,2 m, Schneise 15,9 m vor und 11,1 m zurück, Aufschlagpunkt 4,5 m vor ihr), die Dauerheilung auf 21/s, das Tempo folgt der Größe (7,4 m/s); der **Schaden steigt nicht mehr** (bleibt +30), die Lebensobergrenze ist flat 1000. **Wo der Gigant steht, wird der Boden eben** (`_tick_flatten`, `Golem.flatten_plan`): alle 0,6 s senkt sich alles unter seinem Körper (Radius 3,5 m — die Körperbox, 2026-11-15 in zwei Schritten auf 67,5 % verkleinert) **allmählich** (höchstens 0,1 m je Sekunde, `GOLEM_FLATTEN_RATE` — schlagartig war es zu stark; **nie unter die Wasserlinie**: kein Punkt sinkt tiefer als 0,15 m über `SEA_LEVEL`, und Meeresboden wird gar nicht angefasst, weder gesenkt noch gehoben) auf die **tiefste NATÜRLICHE Stelle** dort (`_flatten_natural` merkt sich die Höhen vor seinem Eingriff — sonst zählte seine eigene Mulde als tiefste Stelle, wanderte mit und er schnitt den ganzen Weg auf das Uferniveau herunter, Bugmeldung 2026-11-15); ringsum bleibt eine begehbare Böschung (höchstens 1 m Anstieg je Meter), es wird nur gesenkt, nie gehoben. Das ist ein normaler `TerrainMorph` — Gebäude auf einer neuen Kante bersten, Überflutete ertrinken. **Der Gigant trampelt auch Gebäude nieder** (2026-11-15): jedes feindliche Gebäude unter seinem Körper verliert alle 2 s (`GOLEM_TRAMPLE_BUILDING_INTERVAL`) **eine Zerstörungsstufe**, solange er läuft — wie unter dem Tornado; ein so zerstörtes Gebäude zählt als Kill. **Und er läuft gerade** (`walks_straight()`, `Golem.giant_line_clear`): Gebäude, Bäume und normales Gelände — auch Hänge, die für alle anderen zu steil sind — sind für ihn kein Hindernis mehr; ist die Luftlinie frei, nimmt er sie sofort (ein einziges Wegstück, ohne Wegsuche). Aufgehalten wird er nur noch vom **Meer**, vom **Kartenrand** und von **großen Klippen** (mehr als 20 % seiner Körperhöhe auf einem Meter Weg, `GOLEM_GIANT_STEP_SHARE` — Stufe 7: 4,2 m). Ist die Luftlinie versperrt, wird normal gesucht und der Weg danach **begradigt** (`_straighten`: nur die Knicke bleiben, die Wasser oder Klippe erzwingen — kein Zickzack am Gitter, kein Umweg ums Haus). Ein Ziel IN einem Gebäude wird auf die nächste freie Zelle gelegt; er läuft hindurch, bleibt aber nicht darin stehen. **Fahrzeuge (2026-11-15):** Tritt, Handschlag und Trampeln des Giganten treffen auch **Bodenfahrzeuge, die nicht unter der eigenen Flagge stehen** (bemannt oder verlassen; eigene nie) — mit den Schadensstufen des Fahrzeugs (`CrewedVehicle.take_crush_hit`): das **Katapult ist sofort zerstört**, die **Feuerramme verliert eines ihrer 3 Leben**; getrampelt wird je Fahrzeug höchstens alle 2 s. Ein zerstörtes Fahrzeug zählt als Kill, die Besatzung kommt lebend frei. Luftschiffe bleiben Sache des Luftschlags. **Wachstum nach Stufe 7:** alle 15 Kills ein Schritt ohne neue Stufe (`growth_steps`): Körper **+3 %** (aufgezinst) — und mit ihm der **Körperradius** (Trampeln, Einebnen; `trample_radius()` = Körperbox × Größe, seit 2026-11-15 auch nach Stufe 7, am Ende 16,4 m) —, Reichweite und Wirkflächen **+0,75 %**, Tempo **+0,25 %**, **Lebensobergrenze +7** (`GOLEM_GROWTH_MAX_HP`, 2026-11-16 von 5 auf 7; am Ende 1371), und der **Radius von Handschlag und Trommeln wächst dort 1,4 % je Schritt bis 12 m bei 100 m** (`slam_radius()`, `GOLEM_SLAM_RADIUS_AT_MAX`, 2026-11-16 — vorher endete er mit den 0,75 % der übrigen Flächen bei 8,6 m; die Breite der Schneise bleibt bei 0,75 %); Dauerheilung und Schaden bleiben — nur der **ausgewachsene** Golem heilt noch einmal 3 LP/s mehr (24/s, `GOLEM_FULL_SIZE_REGEN`). Schluss bei **100 m** Körperhöhe (`GOLEM_MAX_HEIGHT`, nach 53 Schritten = 795 Kills über Stufe 7; dann Reichweite 41,6 m, Tempo 8,5 m/s). **Zwei Flächenangriffe** (Nutzervorgabe 2026-11-15), ab 3 m Abstand alle **1,8 s** einer von beiden: der **Handschlag** (`slam`) — sie bückt sich und schlägt beide Hände auf den Boden — trifft **rundherum**, einen **Kreis mit 2,6 m Radius** um den Aufschlagpunkt 1,2 m vor ihr (`Golem.in_slam_area`, 21 m² wie der alte Schlag): **25 Schaden**, je **30 %** wird das Opfer **hochgewirbelt** bzw. **ins Rollen** gebracht (vom Golem weg). Der **Tritt** (`kick`, wie beim Fußball) trifft eine **Schneise 1,8 m breit, 4,25 m nach vorn und — das Bein holt aus — 70 % davon (2,98 m) nach hinten** (`Golem.in_kick_lane`, `GOLEM_KICK_BACK_SHARE`, 13 m²; bis 2026-11-15 nur 5 m nach vorn): **45 Schaden**, und **jeder Überlebende fliegt davon** — vorn in Trittrichtung, hinten nach hinten weg (9 m/s waagerecht — dreimal der Wurf des Handschlags). **Wahl nach Schaden** (`_choose_attack`, `attack_value`, 2026-11-16 — ersetzt die festen Zielzahlen 3 / 5): für Tritt, Handschlag und Trommeln wird gerechnet, was der Angriff **jetzt** treffen würde (dieselbe Fläche und Zielobergrenze wie beim Aufschlag): Summe über die Einheiten von **min(Schaden, deren Leben)** — kein Überschaden — plus `GOLEM_STRUCTURE_VALUE` (30) je Gebäude/Fahrzeug, geteilt durch die Abklingzeit des Angriffs plus ein Drittel des Haltungswechsels, falls er dafür wechseln müsste (`GOLEM_STANCE_PLAN_ATTACKS`). Der höchste Wert je Sekunde gewinnt; Gleichstand: der Angriff der aktuellen Haltung. Schaden je Sekunde und gesundem Ziel (Tritt stehend, Bodenangriffe gebückt; Tritt / Handschlag / Trommeln): Stufe 0: 25,0 / 20,0 / 23,3 — Stufe 1: 27,5 / 23,7 / 27,5 — Stufe 3: 31,9 / 30,6 / 35,1 — Stufe 6: 37,1 / 39,2 / 44,6. Folgen: auf Stufe 0 tritt sie, wenn in der Schneise so viel steht wie im Kreis, und der Bodenangriff lohnt ab **2 gegen 1**; **ab Stufe 2 ist das Trommeln auch je Einzelziel der stärkste Angriff** (Nutzerwerte vom 2026-11-16), sie bückt sich dann auch für ein einzelnes gesundes Ziel. Gegen angeschlagene Ziele gewinnt der schnelle Handschlag (Grenze: Restleben unter Handschlag-Schaden × 1,44 — Stufe 0: 36, Stufe 6: 79). Der Tritt bleibt für Ziele, die nur die Schneise erreicht, und solange der Haltungswechsel nicht lohnt. Ein einzelnes Gebäude nimmt von jedem Angriff eine Stufe, dort gewinnt also der schnellste: der gebückte Handschlag (alle 1,25 s statt Tritt alle 1,8 s). **Trommeln** (`Golem.ATTACK_DRUM`, Clip `drum_low`, 2026-11-15): drei Schläge auf den Boden — linke Hand, rechte Hand, linke Hand, aus der gebückten Haltung 0,35 / 0,8 / 1,25 s nach Beginn —, **jeder Schlag 14 Schaden** (`GOLEM_DRUM_HIT_DAMAGE`, zusammen 42; Werte vom 2026-11-16, vorher 40 gesamt) in der Fläche des Handschlags; je Stufe bekommt **jeder Schlag +1** (`GOLEM_DRUM_LEVEL_DAMAGE_PER_HIT`) **zusätzlich** zum normalen Stufenbonus von +5 für den ganzen Angriff (auf die drei Schläge verteilt) — also +8 je Stufe: Stufe 1: 16 / 16 / 18 = 50, Stufe 6: 3 × 30 = 90. Hochwirbeln/Rollen, Gebäudestufe und Fahrzeugtreffer gibt es nur beim letzten Schlag. **Abklingzeit: der normale Angriffstakt** (1,8 s bei Startgröße), nicht der verkürzte der gebückten Haltung. Jeder der drei Schläge ist ein eigener Schadenstick mit eigener Zielobergrenze. **Der Tritt wechselt das Bein** (Clips `kick` und `kick_l`, nur Optik). Gezählt werden Feinde **und feindliche Gebäude** (2026-11-15 — vorher trat sie Gebäude immer einzeln, auch wenn drei in der Fläche standen), für den Giganten auch Fahrzeuge. **Trefferzonen und Körper** (`_in_hit_zone`, Nutzervorgabe 2026-11-15): der **Handschlag** trifft den Kreis um die Hände **plus den vorderen Halbkreis des eigenen Körpers** (die Wirkflächen wachsen langsamer als der Körper, vorn blieben sonst Lücken); **hinter ihr, an den Fersen, trifft nur, was der Kreis der Hände von sich aus erreicht**. Der **Tritt** trifft **nur seine Schneise** — sie läuft durch den ganzen Körperkreis (und ist nie kürzer als er, `_kick_extent`), wird dort aber nicht auf den Körper verbreitert. Gilt für Einheiten, Gebäude und Fahrzeuge. **Zielobergrenze** (`max_targets()`, `Balance.GOLEM_MAX_TARGETS`, 2026-11-15 — gegen dichte Nahkampfhaufen eskalierte der Flächenschaden): jeder Schadenstick trifft höchstens **5 / 6 / 6 / 6 / 7 / 8 / 8 / 8** Ziele (Stufe 0–7), nach Stufe 7 **alle 3 Wachstumsschritte eines mehr** (100 m: 25). **Der Tritt trifft eines weniger** (`max_targets_of`, `GOLEM_KICK_TARGETS_LESS`, 2026-11-16: Stufe 0 also 4 statt 5). Das gilt für Handschlag und Tritt je Aufschlag und fürs **Trampeln je Sekunde** (was getrampelt wurde, belegt seinen Platz 1 s, Gebäude und Fahrzeuge 2 s). **Einheiten gehen vor** Fahrzeugen und Gebäuden, die nächsten zuerst; **das Ziel, das er gerade angreift — Einheit oder Gebäude — wird immer getroffen** und zählt mit. **Haltung (2026-11-16, `Golem.stance`):** sie **steht** oder ist **gebückt**. Stehend tritt sie, schlägt nach Luftschiffen und läuft; **Handschlag und Trommeln schlägt sie nur gebückt** — von dort schneller: 0,35 s Ausholzeit statt 0,8 s (`GOLEM_SLAM_WINDUP`), und der Handschlag kommt alle **1,25 s** wieder (`GOLEM_SLAM_COOLDOWN`, 2026-11-16; wächst mit der Größe wie der normale Takt). Dafür kann sie gebückt weder laufen noch treten. **Der Wechsel kostet Zeit** (`stance_switch_time()`: 0,4 s × Wurzel der Größe — 2026-11-16 von 0,45 auf 0,4 —, höchstens 2 s; Stufe 6: 0,69 s, Stufe 7: 0,85 s, 100 m: 1,84 s) — in der Zeit greift sie nicht an und bewegt sich nicht; aus dem Stand dauert der erste Handschlag also 0,75 s. **Sie wechselt von selbst** (`_attack_or_switch`, `_tick_stance`): sie nimmt den Angriff mit dem meisten Schaden je Sekunde (s. „Wahl nach Schaden“) und wechselt dafür die Haltung; weil der Wechsel in der Rechnung Zeit kostet, hat die aktuelle Haltung einen kleinen Vorteil. Außerdem steht sie auf, wenn ein Luftschiff in Schlagweite kommt oder wenn sie laufen muss. Freiwillige Wechsel frühestens **3 s** nach dem letzten (`GOLEM_STANCE_MIN_TIME` — sonst pendelte sie; in der Zwischenzeit nimmt sie den besten Angriff ihrer Haltung — außer sie kann aus ihrer Haltung gar nichts treffen, dann wechselt sie sofort); wer laufen **muss** (Bewegungsbefehl, Ziel außer Reichweite), steht sofort auf. Die Haltung steht mit im Besatzungsfeld. Beide haben eine **Ausholzeit** (Handschlag 0,35 s aus der gebückten Haltung, Tritt 0,5 s): der Angriff wird angesetzt, der Schaden fällt erst beim Aufschlag der Animation, in der dann aktuellen Blickrichtung; solange steht sie und wechselt kein Ziel. Jedes feindliche Gebäude in der Wirkfläche verliert **eine Zerstörungsstufe** (von außen, nie als Raider). Eigene Einheiten trifft er nie, Sitzende (Bekehrung) schon. **Hält sich nicht an die Kampfgruppenregeln** (`_is_ranged()` als Schalter: kein 3er-Ring, Nächster-nach-Distanz-Scan). **Aggro wächst mit dem Körper** (`Golem.aggro_radius()`, 2026-11-15): 8 m × Größenfaktor, also immer rund 1,7 Körperhöhen (Stufe 6: 23,9 m, Stufe 7: 35,8 m), gedeckelt bei 60 m (`GOLEM_AGGRO_MAX`) — vorher lagen die festen 8 m beim großen Golem innerhalb seiner eigenen Reichweite, er griff kaum noch etwas von sich aus an. Die Werte aller Stufen druckt `tests/diag_golem_values.gd`. **Marsch ohne Angriffsbefehl (2026-11-15):** auf einem einfachen Bewegungsbefehl läuft er zum Ziel und wehrt sich unterwegs NICHT (`Golem._maybe_retaliate` — die Grundregel „nach jedem dritten Treffer zurückschlagen“ hielte ihn an jedem Gefecht auf); im Angriffsmove und im Stand kämpft er wie bisher. **Zieldisziplin:** steht ein Feind in Reichweite, wird der geschlagen — einem weggeschleuderten Ziel läuft er erst nach, wenn niemand mehr nah ist; ein fliegendes Ziel wartet er ab. Wie jede Einheit steuerbar, KI schickt ihn mit der Welle. **Ausgewählt zeigt das Besatzungsfeld der Seitenleiste seine Werte** (`Golem.status_text()`, `Sidebar._crew_view`): Stufe und Kills bis zur nächsten, Größe in Metern, Leben, Lebenszeit (ab Stufe 6 „unbegrenzt“), Kills. **Immun** gegen Bekehrung, Hypnose, Panik, Wurf und Rollen (`Unit.is_hypnosis_immune()`); **Konter (Nutzervorgabe 2026-11-15):** **Feuer** macht wieder den vollen Brandschaden (15/s, weiter ohne Panik); der **Blitz** trifft ihn **doppelt** (480, `Unit.lightning_damage`); ein **Katapult-Volltreffer** (Einschlag im Körperkreis — getroffen wird sein Körper, nicht nur der Mittelpunkt, `SiegeShot._shockwave`) macht umso mehr Schaden, je größer er ist: von 15 bei Startgröße linear bis **80** kurz vor 100 m (Stufe 7: 26; `Golem.siege_shock_damage`). **Der ausgewachsene Golem (100 m, `is_full_size()`) ist dagegen gehärtet:** feuerresistent (5/s), nur einfacher Blitzschaden, höchstens **40** je Katapulttreffer. **Kein Anhänger** (`counts_population = false`): kein Mana, kein Wohnraum, hält keinen Stamm am Leben; zählt gegen den Hardcap. Kann weder Fahrzeuge bemannen noch Türme besetzen **und steigt auf kein Luftschiff** (`Airship.accepts_crew_unit`, Bugfix 2026-11-15 — das Luftschiff nimmt sonst jeden). |

> **Fahrzeuge sind Geräte, keine Anhänger (2026-09-06):** Katapult, Feuerramme und
> Luftschiff zählen **nie** zur Bevölkerung, erzeugen kein Mana, belegen keinen
> Wohnraum und halten einen Stamm in der Siegprüfung nicht am Leben (Stamm mit nur
> noch einem Fahrzeug ist besiegt, der Reinkarnationsplatz versinkt). Die
> **Besatzung** zählt weiter wie jede Einheit. Einziger Schalter ist
> `Unit.counts_population` (auf Fahrzeugen `false`), ausgewertet in `Tribe.add_unit`/
> `remove_unit` (Zähler), `GameState.is_tribe_defeated` und
> `ReincarnationSite._tribe_has_no_followers`. Der Einheiten-Hardcap (unten) zählt
> Fahrzeuge dagegen bewusst mit.
>
> **Neutral-Status:** Ein Fahrzeug ohne **handlungsfähige** Besatzung ist **neutral**
> (`CrewedVehicle.is_neutral()`) — niemand an Bord in `State.CREW`: unbemannt, oder die
> ganze Crew sitzt in Bekehrung, paniert, brennt (**außer mit Feuerresistenz**, s.
> `_crew_serves`), rollt oder **kämpft einzeln zu Fuß** daneben. Neutral heißt: **kein Angriffsziel** für irgendwen (Auto-Zielwahl **und**
> Rechtsklick, alle Fahrzeugtypen — die alte Ausnahme „leerer Zeppelin bleibt
> beschießbar" ist weg; ein laufender Beschuss lässt das Ziel fallen), **inert** (fährt
> und feuert nicht, alle Befehle werden gelöscht) und **graue Flagge**. Zauber treffen
> es weiterhin. Ein neutrales Fahrzeug ist beim Anwaehlen ausserdem **stumm**
> (2026-09-07, `SelectionManager._selection_has_audible_unit`) — niemand an Bord kann
> antworten; eine daneben mitselektierte Einheit bringt den Ruf zurueck. Wieder bemannt
> wird es durch die Rückkehr der alten Crew an ihren Platz, eigenes Nachbesetzen oder
> Kapern. **Kapern** (`capturable_by`): Sobald
> **niemand an Bord** ist, darf jeder einsteigen — einlaufende Rekruten des Besitzers
> zählen nicht (Luftschiff-Regel „alle Plätze frei", gilt auch am Boden). Ist die Crew
> nur **außer Gefecht** (sitzt/paniert/kämpft), fällt das Bodenfahrzeug erst nach
> **10 s** Neutralität an den ersten fremden Einsteiger (`Balance.
> VEHICLE_NEUTRAL_TAKEOVER_TIME`); die alte Crew verliert dann ihre Plätze. Das
> **automatische** Nachbesetzen durch fremdes Militär ist strenger und wartet auch bei
> lediglich einlaufenden Besitzer-Rekruten auf den Timer.
>
> **Herrenlose Fahrzeuge sprengen sich nach 3 Minuten** (`CrewedVehicle.
> UNCREWED_LIFETIME` = 180 s, Schalter `destroys_when_uncrewed`): sobald die
> Crewliste **leer** ist — anlaufende Rekruten zählen mit und setzen den Zähler
> zurück — läuft die Uhr, danach zerplatzt das Fahrzeug. Das gilt seit
> 2026-09-10 **auch für das Luftschiff**, das sich vorher als einziger Typ davon
> ausgenommen hatte: ein leerer Zeppelin treibt weiter heim (`_tick_drift`),
> aber das ist eine Gnadenfrist und kein Freibrief. Der Zeppelin stirbt dabei
> über seine **eigene** `explode()` (Hüllentrümmer in der Luft) statt als
> Bodenwrack zu versinken.
>
> **Fahrzeugbesatzung wehrt sich nur gegen Nahkampf** (2026-09-09,
> `CrewedVehicle.crew_defends_melee_only`, ausgewertet in
> `Unit._maybe_retaliate`): Beschuss aus der Ferne zieht **niemanden** vom
> Fahrzeug. Vorher galt das nur für die Feuerramme — ein Nutzerreport aus der
> Debugschlacht zeigte, warum es für alle gelten muss: ein weit hinten
> stehendes Katapult verlor durch **einen** Feuerball auf ein Crewmitglied
> plötzlich 2–4 Mann, die quer über das Feld zum Schützen rannten. Jenseits der
> Leine (`SIEGE_CREW_LEASH`, 8 m) wird ein Mitglied nämlich **aus der Crew
> gelöscht** (`_prune_crew`) — mit ihm gehen Feuerrate, Technikerboni und unter
> `min_fire_crew` die Schussfähigkeit. **Nahkampf am Fahrzeug wird weiter
> beantwortet**; dieser Kampf bleibt mit `FLEE_MELEE_RANGE` (1,8 m) innerhalb
> der Leine. Luftschiff-Deckbesatzung wehrt sich ohnehin nie (`rides_airborne`).
>
> **Werkstatt-Bemannung:** Die Werkstatt rekrutiert **wiederholt** (jede Sekunde) bis zu
> zwei untätige eigene Braves im 12-m-Radius für das fertige Fahrzeug, solange es
> unbemannt am Ausgang steht — nicht mehr nur einmalig im Moment der Fertigstellung.

> **Einheiten-Hardcap:** max. **1000 Einheiten pro Stamm** (`Balance.TRIBE_MAX_UNITS`,
> zusätzlich zum Bevölkerungslimit der Hütten). *(In Phase 10e von 1500 auf 1000
> korrigiert — der Code stand immer auf 1000; Nutzerentscheidung 2026-08-04.)*
> Der Cap zählt **alle** Einheiten, also auch Armee, Schamanin, Fahrzeuge und
> Hütten-Besatzung — als reine Zivilbevölkerung sind damit realistisch ~700
> erreichbar, nicht 1000.

**Steuerung:**
- **Rechtsklick** bewegt selektierte Einheiten (Standard-RTS-Selektion: Klick + Box-Select).
- **Wegpunkt-Routen:** Für Einheiten können Routen aus mehreren Wegpunkten festgelegt werden
  (Patrouillen oder einmalige Bewegungsabläufe).
- **Rally Points (Pflicht-Feature):** Für **alle Gebäude** – insbesondere Trainingshütten –
  müssen Sammelpunkte per UI oder Rechtsklick setzbar sein. Neu erzeugte/ausgebildete
  Einheiten laufen automatisch zum Rally Point.
- **`Entf` reißt alle selektierten eigenen Gebäude ab** (Details in §5).
- **Ein expliziter Befehl holt eine Einheit aus einem Gebäude zurück:** Wer gerade
  ein feindliches Gebäude von innen demoliert (`State.RAID`, aus der Welt entfernt,
  nicht anklickbar), kommt bei Bewegungs-, Angriffs- oder Zauberbefehl am
  Gebäuderand wieder heraus und führt den Befehl aus (`Building.release_raider`,
  `Unit._leave_building_for_order`). Praktisch betrifft das die **Schamanin**, die
  über ihr Portrait auch im Gebäude anwählbar bleibt — alle anderen fallen beim
  Betreten aus der Selektion (`UnitManager.unit_left_world`). Die KI schickt ihren
  Demolierern bewusst keine Marschbefehle nach (`_marching_only`).
- **Beim Platzieren selektierte Braves bauen automatisch mit** — kein zusätzlicher
  Rechtsklick nötig. Braves auf einer **anderen Insel** werden nicht mitgeschickt
  (sie könnten den Bauplatz nie erreichen).
- **`B` zieht ein Holzfäll-Rechteck** (`Shift+B` beauftragt alle Hütten): die Braves
  fällen jeden Baum darin und sammeln **auch die Holzstapel** im Rechteck ein — für
  diese Stapel gilt weiter die **automatische** Ablieferung (anders als beim
  Einzel-Rechtsklick, der Holz aufnimmt und *hält*). Wohin geliefert wird, hängt
  davon ab, wo der Stapel liegt:
  - **an einem eigenen Gebäude** (also bereits „abgeliefertes" Holz): in die
    **nächste Holzstation**. Gibt es keine, bleibt der Stapel liegen — ihn zum
    Gebäude zu tragen, an dem er schon liegt, wäre ein Weg im Kreis.
  - **frei im Gelände:** zum nächsten eigenen Gebäude, mit Vorrang für den größten
    offenen Bedarf (siehe §5) bzw. eine Holzstation in Reichweite.
  - Der **eigene Bestand einer Holzstation** ist nie Sammelziel, sonst würden zwei
    Stationen ihren Bestand endlos hin- und herschaffen.

> **Bewegungsbefehle und Wasser (2026-11-15):** eine Fußeinheit bekommt nie ein Ziel im
> Wasser. `TribeCommands.order_move` prüft den Klickpunkt mit `land_point()`: ein Klick auf
> **offenes Wasser** schickt keine Fußeinheit los (Rückgabe 0, die UI spielt den
> Abgelehnt-Ton; Luftschiffe fliegen trotzdem), ein Klick **am Ufer** — an Land oder bis
> 1,5 m ins Wasser (`SHORE_SNAP`) — geht an Land, und jeder Formationsplatz, der im Wasser
> läge, wird auf das nächste Land gezogen (`_land_slot`): die Gruppe stellt sich **am Ufer
> entlang** auf. Wasser = Geländehöhe am Punkt ≤ `SEA_LEVEL` (der Mausstrahl trifft den
> Meeresgrund).
>
> **Portrait der Schamanin:** zeigt für eine stehende Schamanin dasselbe Bild wie die Welt —
> Ruhepose, und die Idle-Animation nur dann, wenn sie in der Welt gerade läuft
> (`Sidebar._sync_portrait_rest` fragt `UnitRenderer.idle_frame` mit denselben Werten).

## 5. Gebäude & Wirtschaft

- **Holz** ist die **einzige physische Ressource**. Braves sammeln es von **wilden Bäumen**;
  es wird für Bau und Ausbau von Gebäuden benötigt.
- **Hütten (Huts):** **7 Holz**, Platz für **10** Bevölkerung — und **ausbaubar in vier
  Stufen bis zum Wohnpalast** (Phase 10f):

  | | Stufe 0 „Hütte" | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 „Wohnpalast" |
  |---|---|---|---|---|---|
  | Holz (kumuliert) | **7** | 11 | 15 | 19 | **23** |
  | Bevölkerungsplätze | **10** | 18 | 26 | 34 | **45** |
  | Arbeiterplätze | **2** | 3 | 4 | 5 | **6** |

  - **Ausbau:** Ein Timer (90 s nach Fertigstellung bzw. nach dem letzten Ausbau) macht
    die nächste Stufe **fällig**; ist sie erlaubt und liegt Holz in Reichweite, verlässt
    die **gesamte Besatzung** die Hütte, holt **4 Holz** und baut aus. Eine ausbauende
    Hütte produziert deshalb **nichts**, **behält aber ihren Wohnraum**. Der Fortschritt
    läuft über den vorhandenen Balken, beim Ausbau **blau** (Produktion gold, Abriss rot).
    Gesperrt wird der Ausbau stammweit über die Schaltfläche **„Ausbau erlauben"** beim
    Wachstumsregler oder pro Hütte über deren **Pause-Knopf**; ein fälliger Ausbau wartet
    dann sichtbar. Reparatur hat Vorrang — Schaden bricht einen laufenden Ausbau ab und
    gibt sein Holz zurück, ebenso ein Ausbau, der **2 min** keinen Fortschritt macht
    (etwa weil die Bauarbeiter getötet wurden). Das Ausbauholz zählt zur
    **Abriss-Erstattung**.
  - **Bemannung (Phase 7i):** Eine Hütte produziert nur **mit Besatzung** (Braves, im
    Gebäude versteckt, zählen weiter zur Bevölkerung, **kein Mana**). Leere Hütte = keine
    Produktion; die Rate ist **linear in der Besatzung** (30 s je Brave und Arbeiter, also
    15 s auf Stufe 0 und 5 s im Wohnpalast). Bemannung manuell (Braves + Rechtsklick auf
    die Hütte) oder automatisch per **Wachstumsregler** (pro Stamm, UI bei Bevölkerung/
    Mana): **Kein** (leert alle Hütten), **Minimal** (1 Besatzung je Hütte), **Maximum**
    (füllt Hütten bis zur Stufen-Kapazität). Automatisch werden nur **nahe idle** Braves
    eingezogen.
- **Trainingsgebäude:** **Kaserne** (Krieger, 5 Holz/3 s), **Feuertempel** (Feuerkrieger,
  **18 Holz**/4 s, großer vieleckiger Bau, 8×8), **Tempel** (Prediger, **15 Holz**/5 s,
  doppelt so groß, 6×6), **Ausbildungshalle** (Techniker, **10 Holz**/**10 s**, 4×4 —
  die langsamste Ausbildung im Spiel; der Techniker ist über seine Fahrzeugboni bezahlt,
  nicht über seine Werte). Ablauf: Brave betritt das Gebäude → kommt nach Ausbildungszeit als
  entsprechende Kampfeinheit heraus → läuft zum Rally Point.
- **Weitere Gebäude:** **Förster** (Setzlinge/Holzwirtschaft, Phase 7d),
  **Katapultwerkstatt** (**12 Holz**, 7×4) und **Feuerrammenwerkstatt** (**10 Holz**,
  **3×6** — schmale Front, tiefe Halle, beide Phase 7f), **Luftschiffwerft** (20 Holz),
  **Wachturm** (4 Holz, 2 Besatzungsplätze mit Reichweitenbonus, Phase 7h),
  **Holzstation** (1 Holz, 1×1, Lager für 20 Holz).
- **Turmbesatzung ist ein geschützter Vorrat, aber kein unantastbarer** (Phase 7h):
  sie bleibt in der Welt registriert (sichtbar auf der Plattform) und ist für Nah- und
  Fernkampf, Bekehrung und Hypnose **kein Ziel** (`Unit.is_targetable()`), nimmt aber
  weiter **Flächenschaden** (Schwarm, Feuerregen, Lava). Sie **paniert nie** (2026-09-08,
  `start_panic` weist stationierte Einheiten ab) — sie hat keinen eigenen Welt-Tick, ein
  Panikzustand liefe also nie ab und blieb ewig stehen. **Brand zählt dagegen normal:**
  `Unit.tick` ruft für stationierte Einheiten `_tick_burning` auf, der Brand macht
  Schaden, endet nach seiner Zeit und kann im Turm töten — der Tod löst die
  Stationierung, sonst verrottete die Leiche nie.
- **Reinkarnationsplatz:** Respawn-Ort der Schamanin (siehe §4).
- **Gebäude-Lebenspunkte (2026-09-08):** alle Werte in `Balance` sind gegenüber der
  Vorversion **um 50 % erhöht** (Hütte 450 bis 720 je Ausbaustufe, Kaserne 600,
  Tempel 660, Feuertempel 900, Förster 375, beide Werkstätten 525, Luftschiffwerft 750,
  Holzstation 180, Wachturm 300). **Belagerungswaffen sind davon unberührt:** eine
  Zerstörungsstufe ist `ceil(30 % × max_health)`, also bleibt es bei genau **einer Stufe
  pro Katapult-/Rammentreffer** (vier Treffer = zerstört). Ebenso relativ: Blitz (+2),
  Erdbeben (+2), Tornado, Golem, Lava und die Reparaturkosten in Holz. **Nicht**
  nachgezogen wurden bewusst die Quellen mit festem HP-Betrag — Feuerkrieger-Beschuss
  (5), Feuerregen (20 je Ball) und der Nahkampf-Abriss (6 HP/s je Abreißer) brauchen
  jetzt 50 % länger.
- **Gebäudezerstörung (4 Zerstörungsstufen):** Stufe 0 = intakt. Stufen 1–3 (ab 30 % /
  60 % / 90 % Schaden): Gebäude **nicht nutzbar (keinerlei Produktion)**, per Rechtsklick
  durch Arbeiter **reparierbar** — die Reparatur kostet **Holz proportional zum
  reparierten Schaden** (`floor(Schadensanteil × Holzkosten)`, z. B. 90 % Schaden an der
  Hütte → 90 % der Hütten-Holzkosten, abgerundet); visuell brechen mit steigendem Schaden
  mehr Stücke aus dem Modell. Stufe 4 (100 %): Gebäude **versinkt im Boden** und ist
  zerstört, der Bauplatz ist wieder normal betretbar/bebaubar.
  Details: `plans\06_shaman_spells.md`.
- **Abriss (`Entf`, Phase 10d):** Eigene Gebäude sind abreißbar, der Auftrag ist
  **endgültig** (kein Abbrechen). Eine Baustelle **ohne Baufortschritt** ist sofort weg
  und gibt **100 %** des eingesetzten Holzes zurück; alles andere wird eine
  **Arbeiter-Aufgabe** mit **75 %** Erstattung — der Baufortschritt läuft rückwärts, das
  Gebäude schrumpft sichtbar und das Holz kommt **portionsweise** als Bodenstapel am
  Bauplatz an. Ein abzureißendes Gebäude ist **nicht nutzbar** (Besatzung/Trainees werden
  lebend ausgeworfen) und zeigt seinen Abriss über den **roten** Fortschrittsbalken.
  Der **Reinkarnationsplatz ist nicht abreißbar**.
- **Bauverfall (Phase 10d):** Eine Baustelle, die **2 Minuten** keinerlei Fortschritt macht
  (kein Holz, keine Planierung, kein Aufbau), **verfällt** und gibt ihr geliefertes Holz
  am Platz zurück. Das räumt unerreichbare und vergessene Bauplätze wieder ab.
- **Erreichbarkeit (Phase 10d):** Bauarbeiter werden **nur** für Baustellen angeworben, die
  sie zu Fuß erreichen können (gleiche Navigationsinsel). Ein Arbeiter, dem das Gelände
  seine Baustelle wegnimmt (Landbrücke, Erdbeben, Absinken), legt sein Holz ab und
  beendet den Auftrag statt hängen zu bleiben.

## 6. Magiesystem

- **Mana** wird **passiv** generiert; die Rate skaliert mit der **eigenen
  Bevölkerungszahl**, aber **gedämpft** (Phase 10k): bis 100 Anhänger zählt jeder voll,
  darüber nur noch etwa **ein Viertel** je weiterem Kopf. 500 Anhänger liefern damit
  genau das **Doppelte** von 100, 1000 das **3,2-Fache** (vorher das Zehnfache). Die
  Kurve ist `1 + ln(1 + (n−100)/10000) / ln(1,04)`; die Konstanten sind nicht gefittet,
  sondern fallen aus den Zielwerten heraus (`400/10000 = 0,04`).
- **Mana kostet auch Unterhalt:** eine voll besetzte **Försterei** 2,4 Mana/s (0,6 je
  Arbeiter) und jedes **aktiv ausbildende** Trainingsgebäude 0,6 Mana/s. Beides wird vom
  Einkommen abgezogen, **bevor** geladen wird. **Fahrzeugbau und die Brave-Produktion
  der Hütte kosten kein Mana** — die Buchung hängt bewusst an `TrainingBuilding.trainee`,
  nicht an `Building`. Wer in der Warteschlange steht, kostet nichts. Zusatzmana durch
  Beten gibt es nicht (mit 10c entfallen).
- **Ladungssystem:** Mana wird automatisch in **Zauber-Ladungen** umgewandelt (je Zauber
  `charge_cost` und `max_charges`); Casts verbrauchen gespeicherte Ladungen, es gibt
  keinen separaten Cooldown. Anzeige als Ladungs-Pips **plus zwei Ladebalken** je Zauber:
  **blau** der echte Fortschritt, **gold** dahinter ein Ratenbalken, der immer wieder
  durchläuft und nur im offenen Teil sichtbar ist (Original-Populous-Muster). Seine
  Umlaufzeit ist logarithmisch aus der Restzeit abgeleitet, weil die Restzeiten drei
  Größenordnungen überspannen. Ab 30 s steht die Restzeit zusätzlich als Zahl da — sie
  ist eine **Momentaufnahme** und springt, sobald ein anderer Zauber voll wird.
- **Alle aktiven Zauber laden gleichzeitig** und teilen sich das Einkommen zu gleichen
  Teilen. Da die Zauber unterschiedlich viel pro Ladung kosten, ergeben sich daraus
  von selbst individuelle Aufladezeiten — **billige Zauber sind schneller wieder da**.
- **Zauber sind per Rechtsklick abschaltbar.** Ein abgeschalteter Zauber wird nicht mehr
  geladen (sein Anteil geht an die übrigen), seine **gespeicherten Ladungen bleiben
  nutzbar** und sein angefangener Ladebalken bleibt erhalten. Zu Spielbeginn sind alle
  Zauber aktiv. Ein **voller** Zauber wird ebenfalls nicht mehr geladen und kostet nichts.
- **Kein Mana-Banking:** Einkommen, das keinen Abnehmer findet (alles voll oder
  abgeschaltet), **verfällt**. Der Förster-Unterhalt wird vom Einkommen abgezogen,
  bevor geladen wird.
- **Zauberzeit 0,5 s für alle Zauber** (`Balance.SHAMAN_CAST_TIME`): In diesem Wind-up
  spricht die Schamanin die **Zauberformel** (`spell_voice_<id>`). Der Sound des Zaubers
  selbst (`spell_<id>`) kommt getrennt davon, erst **wenn der Effekt eintritt**
  (Einschlag/Ausbruch/Bodenbewegung). Aus Wachturm und Luftschiff zaubert sie ohne Wind-up.
- **Der Effekt kann später eintreten als das Wind-up** (`Spell.effect_delay`): Feuerball,
  Blitz, Schwarm, Hypnose, Tornado, Landbrücke und Ebene wirken **sofort**; Feuerregen und
  Absinken **0,5 s später** (also insgesamt wie vor der Verkürzung); Vulkan, Erdbeben und
  Supertornado **1,0 s später**. Die Schamanin ist nach ihren 0,5 s in jedem Fall wieder
  frei — die **Ladung ist mit dem Wind-up verbraucht**, und den verzögerten Effekt zündet
  ein kleiner Träger auf der Projektilliste (`Spell.DelayedEffect`), der auch ihren Tod
  überlebt.
- **Zaubersprüche:** Grundset (1–5) aus Phase 6, erweitertes Set (6–10) aus Phase 7c,
  Supertornado (11) und **Hypnose (12)** aus Phase 10k. „Ladungen" = `max_charges`; der
  **Mana-Bedarf pro Ladung** (`charge_cost`) steigt stark mit der Mächtigkeit.
- **Kein Zauber unter 9 m Reichweite** (Nutzervorgabe 2026-09-07): der Feuerball war
der einzige mit 8 m und zwang die Schamanin unnoetig nah heran; alle uebrigen lagen
schon bei 9-12 m. Neue Zauber halten diese Untergrenze ein.

**Die Kosten wurden in Phase 10k neu gesetzt** und der Gesamtspeicher wuchs von 2460
  auf 10 310 Mana. Damit ist der **An/Aus-Schalter der Zauberleiste die zentrale
  strategische Entscheidung**: bei voller Leiste braucht ein Vulkan über 14 Minuten,
  allein geladen 45–80 s. Auch die **KI schaltet ab** — sie hält aktiv, was in ~120 s
  ladbar ist, und schaltet teure Zauber zu, sobald alles Aktive voll ist (Einkommen ohne
  Abnehmer verfällt, es gibt kein Mana-Banking).

| # | Zauber | Mana/Ladung | Ladungen | Reichweite | Effekt |
|---|---|---|---|---|---|
| 1 | **Feuerball** | 30 | 4 | 9 m | **Störwaffe, kein Killer** (10k): 20 HP Direkttreffer, 10 HP Splash — dazu wird der Direkttreffer **4 m hochgewirbelt**, Splash-Opfer 2 m. Sturzschaden nach der spielweiten Regel je Meter, Landung rollt aus wie jeder Sturz. Der Ball **verfolgt** das beim Auslösen erfasste Ziel, solange es nicht weiter als 6 m vom Zielpunkt wegläuft. Nahe dem Scheibenrand wird er dadurch zum Gruppentöter. |
| 2 | **Lightning (Blitz)** | 200 | 4 | 12 m | Trifft Einheiten (**4 × Brave-Leben** Schaden; angrenzende Einheiten kommen kurz ins Rollen) oder Gebäude (**+2 Zerstörungsstufen**). |
| 3 | **Swarm (Insektenschwarm)** | 100 | 4 | 10 m | Spawnt einen **zufällig wandernden Schwarm (10 s)**; Gegner in der Nähe geraten in **Panik (6 s)** und erleiden leichten Schaden. Schamanin ist gegen den Panikeffekt immun. |
| 4 | **Landbridge (Landbrücke)** | 150 | 4 | 9 m | Kein Schaden. Hebt Terrain in **breiter Linie** an: über Wasser auf Küstenniveau, sonst auf das Niveau des Zielpunkts; bei Höhendifferenz entsteht eine **begehbare Schräge** (→ Laufzeit-Terrainverformung, §3). |
| 5 | **Tornado** | 220 | 3 | 11 m | Windhose (8 s), wandert zufällig; der Wirkbereich ist ein **Trichter**: am Boden 2,2 m, zur Spitze hin auf das **1,7-Fache** aufgeweitet (`TornadoVortex.TOP_WIDEN`, also 3,7 m Mündung) — fliegende Ziele und Luftschiffe fängt er also deutlich weiter außen als Fußtruppen, und die Hochgewirbelten kreisen oben auf dem breiteren Radius; über Gebäuden **+1 Zerstörungsstufe alle 2 s**. Einheiten im Weg werden zur Spitze **hochgewirbelt**, kurz mitgetragen und mit hoher Geschwindigkeit **weggeschleudert** (Sturzschaden ½ Brave-Leben + Rollschaden; ins Wasser = Sofort-Tod). |
| 6 | **Erdbeben** | 400 | 2 | 11 m | Hebt/senkt das Terrain entlang einer zufälligen Verwerfung (Laufzeit-Verformung), beschädigt Gebäude. |
| 7 | **Vulkan** | 1600 | 1 | 12 m | Hebt einen **Vulkan mit echtem Krater** (10k): Radius 7 m, höchster Ring ist der Kraterrand bei 0,55 × Radius, innen eine 1,5 m tiefe Mulde. Die Lava quillt in der Mulde hoch, tritt über den Rand und läuft außen hinunter — **ein** großer Schwall mit längerer Lebensdauer. Danach füllt sich die Mulde zum kleinen runden Gipfelplateau. Teuerster Zauber. |
| 8 | **Feuerregen** | 775 | 2 | 12 m | **Dauerregen statt Salve** (10k): 20 s lang fallen Bälle in zufälligen Abständen (Ø 0,3 s) auf zufällige Punkte im Umkreis von 7,2 m. Je Ball 20/10 HP, **kein** Hochwirbeln, dafür **Brand** und **20 HP Gebäudeschaden** (= ein Kriegerschlag). **Kennt keine Freunde** (2026-09-06, `FireballBolt.friendly_fire`): Schaden, Brand, Rückstoß und Gebäudeschaden treffen **auch eigene Einheiten und Gebäude** — nur der **Panik-Ring** für Zuschauer außerhalb der Einschläge bleibt gegnerisch (Brennende panieren ohnehin). Die KI lässt die Salve aus, wenn eine eigene Einheit im Zielgebiet steht. Über ~100 Bälle fallen Gebäude — gewollt (waren ~67, bis die Gebäude-HP am 2026-09-08 um 50 % stiegen; der Ballschaden blieb bewusst fest). |
| 9 | **Ebene** | 300 | 3 | 10 m | Ebnet das Zielquadrat exakt ein (harte Kanten). |
| 10 | **Absinken** | 350 | 3 | 10 m | Senkt das Zielgebiet ab (nie unter den Meeresboden). |
| 11 | **Supertornado** | 1200 | 1 | 12 m | Doppelt so breiter Trichter (4,4 m am Boden, **7,5 m an der Mündung**), 12 m hoch, 16 s, dazu zwei normale Tornados als Satelliten. Die Trichter-Aufweitung ist dieselbe Regel wie beim Tornado und wächst damit automatisch mit. |
| 12 | **Hypnose** | 210 | 3 | 10 m | Bekehrt gegnerische Anhänger im **4 × 4 m**-Quadrat **vorübergehend (30 s)** zum eigenen Stamm: sie sind normal steuerbar und kämpfen für den Kontrolleur, Bevölkerung und Manaerzeugung wandern mit. Ein Zeichen über dem Kopf (Spirale, 2,25 m) zeigt die Fremdkontrolle — bei **allen** hypnotisierten Einheiten, egal wessen, und es ist das **einzige** Statussymbol, das der Brand nicht verdrängt (es sagt, wessen Einheit das ist). **Nur die Schamanin ist immun** — Prediger nicht; ein **Ragdoll** (in der Luft tödlich getroffen) ist ebenfalls kein Ziel, sonst holte der Stammeswechsel ihn aus seinem Sturz und er stürbe nie. Eine Bekehrung durch einen Prediger gewinnt und ist endgültig. Wer damit die **letzten** Einheiten eines Stammes nimmt, beendet ihn. |
| 13 | **Golem beschwören** | 900 | 2 | 10 m | Beschwört am Zielpunkt (auf die nächste begehbare Zelle geschnappt) einen **Golem** (siehe §4). Kein Platz oder Einheiten-Hardcap erreicht → der Zauber schlägt fehl und die **Ladung bleibt**. Hotkey **X** (`cast_spell_13`). Die KI beschwört ihn 3 m vor ihrer Schamanin in Richtung des nächsten angreifbaren Feindgebäudes. Sounds `spell_voice_golem`/`spell_golem`, dazu je Aufschlag ein eigener Sound je Angriff — `golem_kick`, `golem_slam`, `golem_drum` (je Trommelschlag), `golem_swat` (2026-11-16, `Golem.strike_sfx_key`); fehlt die Datei, spielt wie bisher `golem_strike` —, und `golem_death` beim Zerfall. **Eigene Stimme in der Bedienung** (`SelectionManager.voice_key`, UI-Sounds): `select_golem` bei der Anwahl, `move_golem` beim Bewegungsbefehl, `attack_golem` beim Angriffsbefehl auf Einheit, Luftschiff oder Gebäude (andere Einheiten haben dafür keinen Sound); die Schamanin in der Gruppe geht vor, und solange eine Datei fehlt, spielt der allgemeine Sound (`select_unit`/`move_unit`, für den Angriffsbefehl `move_golem`). |

**Neue Mechaniken durch die Zauber:** Panik, Umherschleudern von Einheiten
(Wurf-Parabel → Rollen bis zum Ausrollen), Gebäudezerstörung in Stufen (§5),
Laufzeit-Terrainverformung (Erdbeben/Vulkan/Ebene/Absinken).

**Wurfregeln (gelten für JEDEN Wurf, nicht nur Zauber):**
- **Flughöhen-Deckel** `Balance.LIFT_MAX_HEIGHT` (8 m über dem Boden darunter).
  Nur der Aufstieg wird gekappt — wer höher startet (vom Zeppelindeck
  geschleudert), fällt von dort. Was vom Hochschub nicht mehr unter den Deckel
  passt, wirkt stattdessen **seitlich**.
- **Über den Rand = Sturz ins All** (Phase 10j; ersetzt die unsichtbare Mauer aus
  10c). Wer geschleudert, gestoßen oder gerollt die Scheibe verlässt, **stirbt im
  Moment des Randübertritts** und fällt danach als Leiche mit erhaltener
  Geschwindigkeit weiter, bis er unter `Balance.VOID_FALL_DEPTH` entsorgt wird. Der
  Tod am Rand (und nicht in der Tiefe) ist Absicht: Mana-Bonus, Todesschrei und
  Respawn-Zähler laufen dort, wo man sie sieht. Der Tod ist **lautlos**
  (`death_sfx_key()` leer) — **außer bei der Schamanin**, die hörbar stirbt, deren
  Töter den Mana-Bonus bekommt und die am Reinkarnationsplatz respawnt.
  Laufende Einheiten erreichen den Void nie (unbegehbar), Fahrzeuge lassen sich
  nicht schleudern, und **Luftschiffe behalten ihren Clamp** — sie werden
  befehligt, nicht geworfen. Zwei Granularitäten: **verlassen** wird per ZELLE
  entschieden (`_leaves_the_disc`), **fallen** per PUNKT (`has_ground`).
- **Fliegende Ziele:** Nahkampf und Bekehrung kommen nicht an sie heran, Lava
  ignoriert sie, und Feuerkrieger-Feuerbälle machen **+10 % Schaden**
  (`FIREWARRIOR_AIRBORNE_MULT`, auch je Flächenschaden-Opfer) und
  **beschleunigen** bei der Verfolgung. Ein tödlicher Treffer in der Luft tötet
  nicht sofort: die Einheit fällt als Ragdoll zu Boden und stirbt bei der Landung.
  Sie schreit dabei **oben**, im Moment des Treffers (`unit_air_death`, gilt auch
  für die vom Luftschiffdeck geschossene Besatzung; die **Schamanin** hat ihren
  eigenen Schrei `shaman_air_death`, Hook `Unit.air_death_sfx_key()`) — **genau einmal je Einheit**
  und **nur bei einem echten Lufttreffer**: wer am **Sturzschaden** stirbt, bekommt
  den normalen Todes-Sound am Ende des Rollens,
  weitere Treffer auf denselben fallenden Körper bleiben stumm; der eigentliche
  Todes-Sound kommt Sekunden später beim Aufprall. Die Landung eines Ragdolls ist stumm.
- **Wer die Landung überlebt, ist zu hören** (`unit_land`, `Unit.land_sfx_key()`):
  jede Landung, nicht nur die aus Zaubern — Klippensturz, Rückstoß über eine
  Kante, Tornado-Auswurf, Feuerkrieger-Uppercut. Gemeint ist die **Landung
  selbst**: dass der Rollschaden danach noch tötet, ändert den Sound nicht.
- **Verletzte fliegen leichter:** Die Anhebe-Chance des Feuerkrieger-Feuerballs
  skaliert **invers zu den Lebenspunkten** des Ziels — bei voller Gesundheit die
  Basis, kurz vor dem Tod das **Doppelte** (`FW_FIREBALL_LIFT_HP_MAX_MULT`, also
  4 % → 8 %; rollendes Ziel 8 % → 16 %). Die Summe aus Anheben und Umwerfen ist
  damit zur **Laufzeit nicht mehr konstant** — und gegen **rollende** Ziele
  gewinnt bewusst das Umwerfen (**50 %**, Rolldauer **+0,5 s** je Treffer,
  Nachbarn im Umkreis von **1,0 m** stürzen mit 50 % mit).
- **Ein rollendes Ziel wird nicht gestoßen, sondern gelenkt und beschleunigt**
  (der 0,35-m-Schubser war neben ~2,75 m Rollstrecke bedeutungslos): jeder Treffer
  richtet die Rolle vom Schützen weg und legt **+2 m/s** drauf, **gedeckelt bei
  12 m/s** (Tornado-Auswurftempo; der Deckel ist zwingend, weil die Rollgeschwindigkeit
  am Scheibenrand direkt zum Wurf wird). Damit wird die Rolle zur **Impulsrolle** und
  endet erst beim Ausrollen unter 1 m/s — deutlich später als die 0,5 s Mindestdauer,
  bei durchlaufendem Rollschaden. Stehende Ziele werden weiterhin gestoßen.

**Nachladen ist zielunabhängig:** Der Angriffs-/Nachladezähler einer Einheit (und der eines
Turm- oder Deckschützen) wird bei einem **Zielwechsel im Kampf nicht** zurückgesetzt — ein
sterbendes Ziel ist keine nachgeladene Waffe. Nur die **frische** Aufnahme eines Kampfes
(aus Leerlauf/Marsch oder per Befehl) schlägt sofort zu. Bis 2026-09-02 gab jeder Kill einen
Gratisschuss, was massierte Feuerkrieger auf das 1,44-Fache ihrer Feuerrate brachte.

**Buff-System (2026-09-09, `Unit.BUFF_*`):** ein generisches Effektsystem für
Einheiten, gedacht als Grundlage für spätere Zauber; erster Nutzer sind die
Fahrzeugauren des Technikers. Fünf Effekte:
- **Feuerresistenz** — der Brand macht höchstens **5 HP/s** statt 15 und löst
  **keine Panik** aus (ein Insektenschwarm dagegen schon: Feuerresistenz gilt nur
  für Feuer).
- **Bekehrungsresistenz** — ein Prediger muss **3 s** auf das Ziel einreden, bevor
  es sich überhaupt hinsetzt; danach läuft die Bekehrung normal. Der **erste**
  Prediger belegt den Platz, ein zweiter wird abgewiesen, solange der erste
  weitermacht (sonst setzten zwei Prediger einander im Scan-Takt zurück und das
  Ziel wäre unbekehrbar). Bricht die Predigt **0,6 s** ab, verfällt der Vorlauf.
- **Panikresistenz** — der Panikeffekt greift nicht, der **Schaden zählt trotzdem**.
- **Regeneration** — heilt **auch im Kampf** (überspringt nur die 8-s-Wartezeit,
  die Rate bleibt).
- **Stärke** — Angriffsmultiplikator **×1,5 je Stapel, multiplikativ** und **ohne
  Deckel**. Wirkt auf **Nahkampf UND Fernkampf**: der Feuerball des Feuerkriegers
  friert den Multiplikator **beim Abwurf** ein (der Schütze kann im Flug sterben).
  Katapult und Feuerramme sind bewusst außen vor — deren Schaden ist Stufen-/
  Flächenlogik, keine HP eines Angreifers.

Zwei Entwurfsentscheidungen, die man kennen muss, bevor man daran arbeitet:
**Auren haben keinen Timer** (`set_aura_buffs`, Replace-Semantik — das Fahrzeug
sagt jeden Tick neu, was es gibt; verschwindet der Techniker, ist der Buff im
selben Tick weg, es gibt keinen Aufräumpfad zum Vergessen), und **befristete
Buffs zählen im eigenen Tick herunter** statt gegen eine gemeinsame Uhr — fast
alle Tests ticken Einheiten direkt, eine Manager-Uhr stünde dort still. Preis
davon: eine Einheit mit Buff-Arbeit **verweigert den SoA-Hold**
(`_has_pending_buff_work`, wie schon `_burn_time`), sonst liefe „heilt im Kampf"
ausgerechnet im Kampf nie. Angezeigt wird **ein** Sammelsymbol über dem Kopf
(`StatusFxRenderer.FX_BUFF`) mit der **niedrigsten** Priorität — Brand, Panik und
die Hypnose-Spirale verdrängen es.

**Zustandsanzeigen werfen keinerlei Schatten** (Sterne bei kritischer
Verletzung, Panik, Brand, Hypnose): es sind UI-Glyphen über dem Kopf, und in der
Massenschlacht würden hunderte davon die Shadow-Map fluten. Weltgeometrie
(Gebäude, Bäume, Fahrzeuge) wirft weiterhin Schatten.

**Skirmish-Karten (Phase 7i, Kantenlängen in 10j gewachsen):** Auswahl im
Skirmish-Setup — **Insel** (Standard, 144), **Seenland** (288, See mittig, Start in
den Ecken), **Bergpass** (288, Gebirge mit 3 Pässen), **Plateau** (144, erhöhte
Start-Plateaus mit Rampe). Terrain-Kantenlänge ist pro Karte variabel
(`MapGenerator.STANDARD_SIZE` / `LARGE_SIZE`; `TerrainData.SIZE` = 128 ist nur noch
die Default-/Testgröße). Die Kanten wuchsen um **×1,128**, damit die **Fläche der
Scheibe der alten Quadratfläche entspricht** (99,4 %) — die Scheibenwelt kostet
also keine Spielfläche. Alle Karten sind rund.

## 7. Skirmish-KI

- Die KI nutzt **exakt dieselben Mechaniken** wie der Spieler (keine Cheats, gleiche
  Ressourcen-/Mana-/Trainingsregeln).
- **State-Machine** mit mindestens drei Zuständen:
  - **Build-State:** Hütten bauen, Holz sammeln lassen, Trainingslager errichten.
  - **Train-State:** Braves in Trainingsgebäude schicken, Armee aufbauen.
  - **Attack-State:** Truppen sammeln und mit Schamanin + Trupps die Spielerbasis angreifen.
- Übergänge z. B. nach Schwellwerten (Bevölkerung, Gebäudezahl, Armeegröße, Mana).

**Siegbedingungen (Phase 10d):**

- Der **Reinkarnationsplatz ist unverwundbar** — kein Schaden von Einheiten, Zaubern,
  Katapulten, Lava oder Terrainverformung, und er ist nicht abreißbar.
- Er ist außerdem **kein gültiges Angriffsziel** (Phase 10g, `Building.is_attackable()`):
  weder Einheiten noch Katapulte/Feuerrammen (auch nicht über deren automatische
  Zielsuche), noch die Feuerkrieger auf dem Luftschiffdeck nehmen ihn an (deren
  **automatische** Gebäudesuche hat den Filter erst seit 2026-09-02), und die KI
  wählt ihn weder für Zauber noch als Ziel ihrer Angriffswelle. Das gilt **auch für den
  Spieler** — ein Rechtsklick darauf bleibt ein Bewegungsbefehl. Ihn zu beschießen war
  nie ein Weg zum Sieg; der Stamm fällt über seine **Anhänger** (siehe unten).
- Er **zerstört sich selbst**, sobald der Stamm außer der Schamanin **keinen Anhänger**
  mehr hat. Danach ist kein Respawn mehr möglich.
- Ein Stamm ist **besiegt, wenn er keine lebende Einheit mehr hat** — Gebäude retten ihn
  nicht (eine Hütte produziert nur mit Besatzung, und Besatzung sind selbst Einheiten).
- Beim Ausscheiden werden **alle** restlichen Gebäude und Fahrzeuge zerstört und Mana wie
  Zauberladungen geleert. Ein ausgeschiedener Stamm nimmt **keine Befehle** mehr an (UI
  **und** KI), produziert nichts und zaubert nicht. Das ist **irreversibel**; der Stamm
  bleibt nur als Datenobjekt für Siegauswertung und Statistik erhalten.

**Spielmodus „Überleben“ (2026-11-15):** Hauptmenü-Eintrag „Überleben“ (`MatchConfig.survival()`,
Direktstart `-- survival`) — Testgelände für Zauber und Golem auf der Standardinsel. Der Spieler
hat eine kleine Basis auf der Kartenmitte (Reinkarnationsplatz, Schamanin, 3 voll bemannte
Hütten, 12 Braves, **alle Zauber voll geladen — und mit jeder neuen Welle wieder**,
`Balance.SURVIVAL_REFILL_SPELLS_EACH_WAVE`; das normale Einkommen der kleinen Basis brächte
sonst kaum einen Zauber nach). Stamm 1 hat **weder Gebäude noch Schamanin noch KI**.
`SurvivalMode` (`scripts/core/survival_mode.gd`) schickt **20 Wellen** aus Kriegern,
Feuerkriegern (30 %) und Predigern (10 %): die erste nach 30 s, jede weitere **45 s nach dem
Erscheinen der vorigen** (nicht nach ihrem Tod), jede größer als die davor
(`8 + 2k + 14k²/100`: Welle 1 = 8, Welle 10 = 37, Welle 20 = 96; zusammen 877, also unter dem
Einheiten-Hardcap). Größe, Mischung und Richtungen folgen **ohne RNG** aus der Wellennummer
(`wave_size`, `wave_composition`, `wave_spawn_slots`). Gespawnt wird an 8 Punkten am Ufer
(`find_spawn_cells`), je Welle aus 2, ab Welle 8 aus 3 Richtungen, die sich jede Welle
weiterdrehen; die Welle läuft im Angriffsmove auf die Basis, untätige Wellengegner bekommen
alle 6 s ein neues Ziel. **Sieg/Niederlage:** der Wellenstamm hat zwischen den Wellen keine
Einheit und würde nach der normalen Regel sofort ausscheiden — deshalb nimmt ihn
`GameState.set_defeat_exempt()` von der Siegprüfung aus, **bis die letzte Welle erschienen
ist**; danach gilt die normale Regel (letzter Wellengegner tot → Sieg). Die Niederlage ist
unverändert. Anzeige: `SurvivalHud` oben in der Mitte („Welle 3/20“, Countdown). Alle Werte:
`Balance.SURVIVAL_*`.

## 8. Geplante Projektstruktur & Konventionen

Zielbild für die kommenden Aufgaben:

```
D:\game\Populous-TheEnd\
├── project.godot
├── CLAUDE.md                  # diese Datei
├── plans\                     # Phasenpläne (00_overview.md) + PROGRESS.md (Ist-Stand, s. §10)
├── scenes\                    # Szenen (.tscn): main, terrain, ui, units, buildings
├── scripts\
│   ├── core\                  # GameState, Spieler/Stamm-Verwaltung, Ressourcen, Mana
│   ├── units\                 # Basisklasse Unit + Schamanin, Brave, Krieger, Feuerkrieger, Prediger
│   ├── buildings\             # Basisklasse Building + Hütte, Trainingslager, Tempel, Reinkarnationsplatz
│   ├── spells\                # Zauber-Implementierungen (Blast, Lightning, Swarm, Landbridge, Tornado)
│   ├── ai\                    # KI-State-Machine (Build/Train/Attack)
│   └── ui\                    # HUD, Selektion, Zauberleiste, Rally-Point-UI
└── assets\                    # Sprites (Einheiten), 3D-Modelle (Gebäude), Texturen, Sounds
```

**Konventionen:**
- **UI-Sprache: Deutsch.** Code, Identifier, Dateinamen, Klassennamen: **Englisch**.
- **GDScript-Styleguide:** `snake_case` für Variablen/Funktionen/Dateien, `PascalCase` für
  Klassen/Nodes, **typisierte Deklarationen** (`var health: int = 100`,
  `func take_damage(amount: int) -> void`).
- Godot-Idiome bevorzugen: Signals für Entkopplung, Szenen-Komposition statt tiefer
  Vererbung, `class_name` für gemeinsame Basisklassen (Unit, Building, Spell).
- Kleine, gezielte Änderungen; bestehende Muster/Hilfsfunktionen wiederverwenden;
  keine unnötigen Refactorings.

## 9. Verifikation

- **Nach jeder Skript-Änderung:** Syntax-Check per
  `& $GODOT --path D:\game\Populous-TheEnd --headless --check-only --script <datei>.gd`
  oder headless-Projektstart (`--headless --quit`) und Output auf Fehler prüfen.
- **Funktional:** Spiel per `& $GODOT --path D:\game\Populous-TheEnd` starten und die
  betroffene Mechanik im Spiel prüfen.
- **Kein MCP-Compile/-Check** vorhanden (siehe Sonderfall-Hinweis oben). Wenn ein Check
  nicht ausführbar ist, den Grund nennen – **keine erfolgreiche Prüfung behaupten, die
  nicht lief.**
- **Bekannte Einschränkung:** `--check-only` kennt keine Autoloads – Skripte, die
  `GameState`/`Events` referenzieren, melden dort fälschlich „Identifier not found".
  Maßgeblich ist der Projekt-Ladecheck (`--headless --quit`).
- **Nach jedem `git pull` auf einem anderen Rechner einmal
  `--headless --import` ausführen** (oder den Editor öffnen). Der globale
  Klassen-Cache liegt in `.godot\` (nicht im Repo) und wird beim reinen
  Spielstart NICHT aktualisiert — neue `class_name`-Skripte aus dem Pull sind
  sonst unbekannt („Could not find type …"), betroffene Skripte kompilieren
  nicht und es hagelt Folgefehler (z. B. Minimap-`nil`-Fehler, weil
  `Main._ready` nie durchläuft).

## 10. Fortschritts-Doku (`plans\PROGRESS.md`)

- **`plans\PROGRESS.md` ist die Ist-Stand-Doku des Projekts:** was pro Phase tatsächlich
  gebaut wurde (Dateien + Kern-APIs), Extras/Abweichungen von den Phasenplänen,
  Erkenntnisse/Stolpersteine und Verifikationsstand.
- **Bei Arbeitsbeginn an einer neuen Aufgabe/Phase zuerst lesen:**
  `plans\00_overview.md` (Phasenstatus + Arbeitsanweisung) und `plans\PROGRESS.md` –
  damit ist der bisherige Stand bekannt, ohne den Code durchsuchen zu müssen.
- **Nach Abschluss einer Phase oder größeren Erweiterung:** PROGRESS.md ergänzen
  (Schritt 7 der Arbeitsanweisung in `plans\00_overview.md`).
