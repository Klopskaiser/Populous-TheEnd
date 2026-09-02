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

## 4. Einheiten & Steuerung

| Einheit | Rolle |
|---|---|
| **Schamanin** | Wichtigste Einheit, einzige Zauberwirkerin. **HP = 4 × Brave**, **Nahkampfschaden = 2 × Brave**. Stirbt sie, **respawnt** sie nach einer Wartezeit am **Reinkarnationsplatz** (Reincarnation Site); der Stamm des Tötenden bekommt einmalig **10 % der minütlichen Manaproduktion ihres Stammes** auf seine aktiven Aufladeraten verteilt. Pro Stamm genau eine. |
| **Brave (Gefolgsmann)** | Basis-Einheit. Sammelt **passiv Holz** und baut Gebäude aus. Wird von Hütten gespawnt. |
| **Krieger** | Nahkampf-Einheit. Ausbildung in der **Kaserne** (Krieger-Trainingslager). |
| **Feuerkrieger** | Fernkampf-Einheit (Feuerbälle). Ausbildung im **Feuertempel** (Feuerkrieger-Trainingslager). Der Feuerball macht **Flächenschaden** (20 % des Hauptschadens im Umkreis von **1,2 m**, **nur Feinde**, kein Rückstoß auf Umstehende) — ohne ihn teilten Feuerkrieger viel Schaden aus und töteten fast nichts. Der Radius ist an der Einheitengeometrie ausgerichtet: 1,2 m fasst **genau ein 6er-Pack** (max. 1,10 m breit) bzw. eine Nahkampfgruppe (0,9-m-Ring) und lässt die Nachbargruppe (2,2 m) draußen. Gemessen **flach in XZ**, der Bereich ist also ein senkrechter Zylinder. **Die Wirkung skaliert mit der Dichte:** im 200er-Klumpen nimmt fast jeder Ball ~3 Umstehende mit, bei 20 gegen 20 meist keinen — Feuerkrieger sind damit bewusst eine **Masseneinheit**. |
| **Prediger** | **Konvertiert** feindliche Einheiten zum eigenen Stamm. Ausbildung im **Tempel**. Mehrere Prediger verteilen sich auf verschiedene Ziele; **Einheiten in Bekehrung sind kein gültiges Ziel** für Nah-/Fernkampf (Katapult ausgenommen). Eine **kämpfende feindliche Schamanin** im Umkreis von 6 m **unterbricht die Predigt** — laufende Bekehrungen brechen ab, neue beginnen nicht, und das gilt für alle Prediger in ihrem Radius. Bloßes Herumstehen stört nicht. **Gegnerische Prediger singen hörbar anders** als die eigenen (`preach_enemy` statt `preach`, Perspektive Spieler) — eine fremde Predigt soll man erkennen. **Luftschiffinsassen sind kein Bekehrungsziel** (am Deck unerreichbar) und werden gar nicht erst gewählt — weder vom Prediger am Boden noch von einem im Wachturm oder auf einem Deck, und ein Rechtsklick darauf wird abgewiesen. |
| **Belagerungswaffe (Katapult)** | Fernkampf-Fahrzeug mit Crew, gebaut in der **Werkstatt** (Phase 7f). |

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
  doppelt so groß, 6×6). Ablauf: Brave betritt das Gebäude → kommt nach Ausbildungszeit als
  entsprechende Kampfeinheit heraus → läuft zum Rally Point.
- **Weitere Gebäude:** **Förster** (Setzlinge/Holzwirtschaft, Phase 7d),
  **Katapultwerkstatt** (**12 Holz**) und **Feuerrammenwerkstatt** (**10 Holz**, beide
  Phase 7f), **Luftschiffwerft** (20 Holz), **Wachturm** (4 Holz, 2 Besatzungsplätze mit
  Reichweitenbonus, Phase 7h), **Holzstation** (1 Holz, 1×1, Lager für 20 Holz).
- **Reinkarnationsplatz:** Respawn-Ort der Schamanin (siehe §4).
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
- **Die Kosten wurden in Phase 10k neu gesetzt** und der Gesamtspeicher wuchs von 2460
  auf 10 310 Mana. Damit ist der **An/Aus-Schalter der Zauberleiste die zentrale
  strategische Entscheidung**: bei voller Leiste braucht ein Vulkan über 14 Minuten,
  allein geladen 45–80 s. Auch die **KI schaltet ab** — sie hält aktiv, was in ~120 s
  ladbar ist, und schaltet teure Zauber zu, sobald alles Aktive voll ist (Einkommen ohne
  Abnehmer verfällt, es gibt kein Mana-Banking).

| # | Zauber | Mana/Ladung | Ladungen | Reichweite | Effekt |
|---|---|---|---|---|---|
| 1 | **Feuerball** | 30 | 4 | 8 m | **Störwaffe, kein Killer** (10k): 20 HP Direkttreffer, 10 HP Splash — dazu wird der Direkttreffer **4 m hochgewirbelt**, Splash-Opfer 2 m. Sturzschaden nach der spielweiten Regel je Meter, Landung rollt aus wie jeder Sturz. Der Ball **verfolgt** das beim Auslösen erfasste Ziel, solange es nicht weiter als 6 m vom Zielpunkt wegläuft. Nahe dem Scheibenrand wird er dadurch zum Gruppentöter. |
| 2 | **Lightning (Blitz)** | 200 | 4 | 12 m | Trifft Einheiten (**4 × Brave-Leben** Schaden; angrenzende Einheiten kommen kurz ins Rollen) oder Gebäude (**+2 Zerstörungsstufen**). |
| 3 | **Swarm (Insektenschwarm)** | 100 | 4 | 10 m | Spawnt einen **zufällig wandernden Schwarm (10 s)**; Gegner in der Nähe geraten in **Panik (6 s)** und erleiden leichten Schaden. Schamanin ist gegen den Panikeffekt immun. |
| 4 | **Landbridge (Landbrücke)** | 150 | 4 | 9 m | Kein Schaden. Hebt Terrain in **breiter Linie** an: über Wasser auf Küstenniveau, sonst auf das Niveau des Zielpunkts; bei Höhendifferenz entsteht eine **begehbare Schräge** (→ Laufzeit-Terrainverformung, §3). |
| 5 | **Tornado** | 220 | 3 | 11 m | Windhose (8 s), wandert zufällig; der Wirkbereich ist ein **Trichter**: am Boden 2,2 m, zur Spitze hin auf das **Doppelte** aufgeweitet (`TornadoVortex.TOP_WIDEN`) — fliegende Ziele und Luftschiffe fängt er also deutlich weiter außen als Fußtruppen, und die Hochgewirbelten kreisen oben auf dem breiteren Radius; über Gebäuden **+1 Zerstörungsstufe alle 2 s**. Einheiten im Weg werden zur Spitze **hochgewirbelt**, kurz mitgetragen und mit hoher Geschwindigkeit **weggeschleudert** (Sturzschaden ½ Brave-Leben + Rollschaden; ins Wasser = Sofort-Tod). |
| 6 | **Erdbeben** | 400 | 2 | 11 m | Hebt/senkt das Terrain entlang einer zufälligen Verwerfung (Laufzeit-Verformung), beschädigt Gebäude. |
| 7 | **Vulkan** | 1600 | 1 | 12 m | Hebt einen **Vulkan mit echtem Krater** (10k): Radius 7 m, höchster Ring ist der Kraterrand bei 0,55 × Radius, innen eine 1,5 m tiefe Mulde. Die Lava quillt in der Mulde hoch, tritt über den Rand und läuft außen hinunter — **ein** großer Schwall mit längerer Lebensdauer. Danach füllt sich die Mulde zum kleinen runden Gipfelplateau. Teuerster Zauber. |
| 8 | **Feuerregen** | 775 | 2 | 12 m | **Dauerregen statt Salve** (10k): 20 s lang fallen Bälle in zufälligen Abständen (Ø 0,3 s) auf zufällige Punkte im Umkreis von 7,2 m. Je Ball 20/10 HP, **kein** Hochwirbeln, dafür **Brand** und **20 HP Gebäudeschaden** (= ein Kriegerschlag). Wer nah dabei steht, aber außerhalb der Einschläge, geräte in **Panik**. Über ~67 Bälle fallen Gebäude — gewollt. |
| 9 | **Ebene** | 300 | 3 | 10 m | Ebnet das Zielquadrat exakt ein (harte Kanten). |
| 10 | **Absinken** | 350 | 3 | 10 m | Senkt das Zielgebiet ab (nie unter den Meeresboden). |
| 11 | **Supertornado** | 1200 | 1 | 12 m | Doppelt so breiter Trichter (4,4 m am Boden, **8,8 m an der Mündung**), 12 m hoch, 16 s, dazu zwei normale Tornados als Satelliten. Die Trichter-Aufweitung ist dieselbe Regel wie beim Tornado und wächst damit automatisch mit. |
| 12 | **Hypnose** | 210 | 3 | 10 m | Bekehrt gegnerische Anhänger im **4 × 4 m**-Quadrat **vorübergehend (30 s)** zum eigenen Stamm: sie sind normal steuerbar und kämpfen für den Kontrolleur, Bevölkerung und Manaerzeugung wandern mit. Ein Zeichen über dem Kopf (Spirale, 2,25 m) zeigt die Fremdkontrolle — bei **allen** hypnotisierten Einheiten, egal wessen, und es ist das **einzige** Statussymbol, das der Brand nicht verdrängt (es sagt, wessen Einheit das ist). **Nur die Schamanin ist immun** — Prediger nicht. Eine Bekehrung durch einen Prediger gewinnt und ist endgültig. Wer damit die **letzten** Einheiten eines Stammes nimmt, beendet ihn. |

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
  ignoriert sie, und Feuerkrieger-Feuerbälle machen **+20 % Schaden**
  (`FIREWARRIOR_AIRBORNE_MULT`, auch je Flächenschaden-Opfer) und
  **beschleunigen** bei der Verfolgung. Ein tödlicher Treffer in der Luft tötet
  nicht sofort: die Einheit fällt als Ragdoll zu Boden und stirbt bei der Landung.
  Sie schreit dabei **oben**, im Moment des Treffers (`unit_air_death`, gilt auch
  für die vom Luftschiffdeck geschossene Besatzung); der eigentliche Todes-Sound
  kommt Sekunden später beim Aufprall. Die Landung eines Ragdolls ist stumm.
- **Wer die Landung überlebt, ist zu hören** (`unit_land`, `Unit.land_sfx_key()`):
  jede Landung, nicht nur die aus Zaubern — Klippensturz, Rückstoß über eine
  Kante, Tornado-Auswurf, Feuerkrieger-Uppercut. Gemeint ist die **Landung
  selbst**: dass der Rollschaden danach noch tötet, ändert den Sound nicht.
- **Verletzte fliegen leichter:** Die Anhebe-Chance des Feuerkrieger-Feuerballs
  skaliert **invers zu den Lebenspunkten** des Ziels — bei voller Gesundheit die
  Basis, kurz vor dem Tod das Dreifache (`FW_FIREBALL_LIFT_HP_MAX_MULT`, also
  4 % → 12 %; rollendes Ziel 10 % → 30 %). Die Summe aus Anheben und Umwerfen ist
  damit zur **Laufzeit nicht mehr konstant** — nur die Basiswerte sind es.

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
