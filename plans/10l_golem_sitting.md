# 10l – Golem: Haltung „Sitzen“ (Plan, 2026-11-17)

## Krebsgang, Sterben im Sitzen, Zeppelin-Zerstoerer (Nutzervorgaben 2026-11-18, umgesetzt)

- **Sterben im Sitzen** und im Krebsstand: Clip `sit_death` (`Golem.death_clip`), der Sitz-Versatz bleibt.
- **Schalter "Stationaer"** in der Golem-Ansicht, Standard an (wie bisher). Aus: die Sitzende wechselt selbst in den
  Krebsgang — fuer Bewegungsbefehle, fuer Angriffsbefehle (hinkrebsen, bis ein Sitzangriff trifft, hinsetzen,
  angreifen) und von selbst zu Gegnern in Aggro-Reichweite, wenn sie im Sitzen nichts mehr erreicht.
- **Ablauf:** `crab_up` -> `crab_idle`/`crab_walk` (Fuesse voran, ueberblendet, Schleifen) -> `crab_down` -> sitzen.
  Tempo **1/3 des Laufens**; gleiche Wegregeln wie beim Laufen. Am Ziel oder in Reichweite setzt sie sich — **auch auf
  Gebaeude**; die Terrainregeln des Sitzes gelten weiter, Sitzschaden und Einebnen wie beim Hinsetzen, feindliche
  Gebaeude unter der Sitzflaeche nehmen je Tick den halben Sitzschaden (eigene nichts).
- **Unterwegs:** Trampelschaden unter allen vier Gliedern, eine gemeinsame Zielobergrenze; kein Sitzschaden, keine
  Sitzangriffe. Kollisions- und Trefferkreis decken den ganzen Koerper (groesser, anfaellig fuer Angriffe).
- **Zeppelin-Zerstoerer:** Angriff im Krebsstand, Zielbereich hinter dem Kopf, der einzige Weg, aus dem Sitzen ein
  Luftschiff zu zerstoeren (stationaer also gar nicht). Huellentreffer wie der Luftschlag im Stand.
- **Annahmen (Nutzer kann aendern):** Drehrate im Krebsgang 1/3 der Stand-Drehrate; Aufrichten/Absetzen 1,2 s bei
  30 m, mit Wurzel der Hoehe; Koerperkreis 1,55 m, Gliederkreis 0,3 m, Zielbereich 1,6 m hinter der Mitte mit 1,0 m
  Radius (je 4-m-Modell); Selbst-Krebsgang nur zu Einheiten (nicht zu Gebaeuden) und zu Luftschiffen; findet sie am
  Ziel keinen Sitzplatz, bleibt sie im Krebsstand und versucht es jede Sekunde neu.

#### Clipvertrag Krebsgang

| Clip | Laenge bei Tempo 1 | Was passiert |
|---|---|---|
| `crab_up` | 0,6 s (gestreckt auf `crab_switch_time`) | Sitz -> Krebsstand |
| `crab_idle` | 2,0 s, Schleife | Ruhe im Krebsstand |
| `crab_walk` | 1,0 s, Schleife | Krebsgang auf der Stelle, Fuesse voran; Weg je Durchlauf bei 4 m: Golem 1,029, Daemon 0,997, Genesis 1,012 m |
| `crab_down` | 0,6 s (gestreckt) | Krebsstand -> Sitz |
| `sit_death` | 1,4 s | Sterben im Sitzen, bleibt in der Endpose |
| `crab_headbutt` | 1,0 s, Aufschlag 0,4 s (`GOLEM_CRAB_AIR_IMPACT`; gespielt so, dass er auf die Ausholzeit faellt) | Zeppelin-Zerstoerer: Kopfstoss nach hinten aus dem Krebsstand, beginnt und endet in der Ruhe im Krebsstand |


Status: **Clips der Sitzangriffe geliefert (2026-11-17, abends)** — alle zwölf (`sit_stomp_l/r`, `sit_kick_l/r`,
`sit_wipe_l/r`, `sit_hop`, `sit_clap`, `sit_double_stomp`, `sit_turn_l/r`, `sit_grow`) sind in den drei GLB; die
Aufschlagzeiten aus `GolemSitAnim.SIT_CLIP_IMPACT` sind eingehalten (0,35 s: der Schuh liegt im Bild bei 0,333 s auf).
Noch nicht im laufenden Spiel angesehen. Was weiter unten zu fehlenden Clips steht, ist der Stand von davor.
**Arm-Ebene mit Nacken und Kopf** (Nutzerwunsch 2026-11-17: beim Wischer wendet sie den Kopf zur Seite des Arms):
`GolemSitAnim.head_paths` stehen mit im Filter der Arm-Ebene; `sit_wipe_l/_r` tragen die Kopfdrehung.

Status davor: **Erste Stufe umgesetzt (2026-11-17)** — Sitzen mit Taste `V` und Knopf, Sperren,
Sitzplatz, Sitzschaden, Zielradius, Wachsen im Sitzen, für alle drei Golems. **Noch offen:**
Sitzangriffe (Schritt 9), Drehen im Sitzen (Schritt 6) und der Clip `sit_grow` — dafür
fehlen die Clips `sit_stomp_l/r`, `sit_wipe_l/r`, `sit_turn_l/r`, `sit_grow`. Die Clips
`sit_down`, `sit_idle`, `sit_up` sind da (`D:\game\gymnastikschuh`, Clipvertrag unten).

### Entscheidungen zur ersten Stufe (Nutzer 2026-11-17)

- Im Sitzen erstmal **keine Angriffe**.
- Sitzfläche: **Rechteck unter dem Po**, Hände und Füße zählen nicht (gemessen am Clip
  `sit_idle`: Mitte 1,3 m hinter den Füßen im 4-m-Modell, 0,6 × 0,6 m;
  `GOLEM_SIT_SEAT_*`).
- Zielkreis, Auswahlkreis und Golem-Abstand im Sitzen auf der **Mitte der Sitzfläche**.
- Dauer 3 s × Wurzel(Höhe / 30 m), **ohne Obergrenze** (Nutzer will es erst sehen).
- Zielradius im Sitzen **× 2**.
- Gilt für **alle Golems** (auch den Genesisgolem).
- Feindliche Fahrzeuge unter der Sitzfläche nehmen Schaden; Bäume werden ignoriert; kein
  Einebnen im Sitzen; die Sitzschadenfläche wächst im Sitzen nicht mit.
- Erster Sitzschaden-Tick sofort beim Aufsetzen.
- Annahme: der Dämonengolem setzt sich wie bei allen Haltungswechseln 15 % schneller.
- Nachtrag: sitzend nie tiefer als der Boden unter Füßen, Po und Händen (höher darf sie);
  beim Hinsetzen ebnet sich der Boden unter der Figur auf Fußhöhe ein; der Auswahlkreis
  wechselt 0,5 s vor dem Aufsetzen auf die Sitzmitte (beim Aufstehen sofort).

Erreichbar: Golem nach 222 Kills (31,3 m), Dämonengolem mit der 32-m-Stufe (60 Kills),
Genesisgolem auf Stufe 8 (33 m).

### Sitzangriffe und Drehen — Vorarbeit (Nutzervorgaben 2026-11-17)

Umgesetzt in `scripts/units/golem_sit_combat.gd` (Logik) und `scripts/units/golem_sit_anim.gd`
(Animationsebenen); die **Clips fehlen noch** — bis dahin wirken die Angriffe ohne Bild und der
Animationsbaum bleibt aus.

- **Zonen und Werte (Nutzervorgaben 2026-11-17, ersetzt die Vorschläge unten):** Maße des 4-m-Modells in
  `Balance.GOLEM_SIT_*`, an den Clips gemessen gegen die Mitte zwischen den ruhenden Schuhen, skaliert wie das Modell.
  Werte bei 31 m in Klammern.
  1. **Fuß-Stampfer** l/r: Kreis (mittel: 0,75 × Handschlag-Radius, 5,3 m) um die Stelle, an der der Schuh landet
     (3,3 m vor, 3,7 m neben der Fußmitte), nicht hinter die Ferse des ruhenden Schuhs. Schaden und Ziele wie der
     Handschlag; schnell wie der gebückte Handschlag (Nutzerentscheidung: der Luftschlag wäre bei 31 m langsamer).
  2. **Bein strecken** l/r: Schneise vom Hüftgelenk bis zur Spitze des gestreckten Schuhs (11,1 m hinter bis 8,7 m
     vor den Füßen, 2,6 m breit, 1,6 m neben der Mitte). Werte wie der Tritt. Deckt den Bereich unter den Knien ab.
  3. **Po-Klatscher** (`sit_hop`): Kreis des Sprungs um die Sitzmitte (8,6 m), Schaden und Ziele wie der Sprung,
     Abklingzeit 1,1 × die des Sprungs.
  4. **Doppelstampfer**: Kreis des Trommelns (7,7 m) um die Landestelle beider Schuhe (2,4 m vor den Füßen), reicht
     ein Stück hinter die Füße. Schaden, Ziele, Abklingzeit wie das Trommeln.
  5. **Arm-Wischer** l/r: Kegel um die Sitzmitte auf seiner Seite, Reichweite `reach()`, von 30° hinter der
     Querrichtung nach vorn bis zum Becken (höchstens 0,2 m des 4-m-Modells vor der Sitzmitte, 1,7 m; vorher bis 60°
     vor quer, er reichte bis zu den Beinen). Schaden und Ziele wie der Luftschlag, schnell wie der gebückte Handschlag.
  6. **Handstampfer hinten** (`sit_clap`): Kreise des Trommelns um beide Hände, nur hinter der Sitzmitte. Schaden
     und Ziele wie das Trommeln, Abklingzeit 0,83 × die des Trommelns (Nutzerentscheidung).
  Die großen (3, 4, 6) brauchen und sperren weiter beide Kanäle und mindestens 3 Ziele — **außer kein Einzelangriff
  erreicht etwas: dann reicht ein Ziel** (sonst blieb ein einzelner Feind unter oder hinter ihr unbehelligt).
  Gleichstand zweier Angriffe: der, dessen Aufschlag näher an den Getroffenen liegt (vorher wurde `sit_kick_r` nie
  gewählt). Die Bein-Schneisen reichen innen bis zur Körpermitte (die Knie berühren sich; Nutzermeldung: ein Feind
  zwischen den Schuhen wurde nie getroffen).
  - **Gebäude:** feindliche Gebäude in der Zone verlieren je Treffer eine Zerstörungsstufe (wie im Stand); sie zählen
    in der Wahl mit `GOLEM_STRUCTURE_VALUE` und füllen die Plätze der Zielzahl, die die Einheiten frei lassen.
  - **Im Sitzen greift es sich leichter an** (Nutzervorgabe 2026-11-17): alle Sitzangriffe außer dem Handstampfer
    hinten mit 0,9 × Abklingzeit (`GOLEM_SIT_COOLDOWN_FACTOR`) und 0,9 × Zielbereich (`GOLEM_SIT_AREA_FACTOR`: Radien,
    Kegel-Reichweite, Breite der Bein-Schneisen; die Zielzahl bleibt). Die Zahlen bei 31 m oben sind die von davor.
  - **Nachjustiert (Nutzervorgabe 2026-11-17):** Doppelstampfer weiter hinten (Kreismitte 0,9 m hinter statt 2,6 m
    vor den Füßen) und noch einmal 10 % kleiner (6,3 m); Bein-Schneisen länger, bis 13,9 m vor den Füßen (vorher
    bis zur gestreckten Schuhspitze, 9,0 m). Maße bei 31 m.
  - **Spieltest 2026-11-17:** Turm- und Deckschützen messen zum Rand ihres Zielkreises (`UnitManager.rim_dist`) —
    vorher schossen sie nicht auf sie, wenn ihre Sitzmitte (11 m hinter den Füßen) außer Reichweite lag; das
    Luftschiff fliegt entsprechend heran. Erreicht nichts ihre Glieder und steht kein Feind im Aggro-Radius, dreht
    sie sich zum nächsten feindlichen Gebäude darin.
  - **Drehen:** Drehrate im Sitzen halbiert (12,5 % der Drehrate im Stand). Der Drehclip ist jetzt sichtbar: der
    Grundclip ist eine Überblendung (0,3 s) zwischen `sit_idle`, `sit_turn_l`, `sit_turn_r`, die jeden Clip von vorn
    startet, und die Drehclips laufen in Schleife — vorher wurde nur der Clip im Knoten getauscht (er lief auf der
    Uhr von `sit_idle` weiter) und blieb nach einem Durchlauf stehen.
  - **Handstampfer hinten:** Kreise 15 % kleiner als die des Trommelns (`GOLEM_SIT_CLAP_AREA_FACTOR`, bei 31 m 6,6 m).
  - **Wachsen im Sitzen:** die gestreckten Beine treffen in beiden Bein-Schneisen zugleich (Zielzahl 2 × Tritt),
    0,43 s nach Beginn des Streckens (`GolemSitCombat.GROW`, `grow_strike`), mit dem Schaden eines Trampelticks
    (Nutzervorgabe 2026-11-17; zuerst der des Tritts).
  - **Runde 5 (Nutzervorgaben 2026-11-18):**
    - **Wischer** reicht 5° weiter nach vorn: die vordere Grenze ist um `GOLEM_SIT_WIPE_FRONT_DEG` geneigt (je Meter
      nach außen tan 5° weiter vorn).
    - **Po-Klatscher:** Abklingzeit × 1,165 und Ausholen × 1,136 (`GOLEM_SIT_HOP_SLOWER_*`; beim 30-m-Golem je
      +0,2 s: Abklingzeit 1,21 → 1,41 s, Animation 1,47 → 1,67 s), Kreis 10 % kleiner (`GOLEM_SIT_HOP_AREA_FACTOR`,
      `hop_radius()`). **Braucht kein Anvisieren:** während sie sich dreht, kommt er für jeden Feind in seinem Kreis
      (`_hop_while_turning`, ein Ziel reicht, beide Kanäle frei).
    - **Drehen** merkt sich sein Ziel (`_turn_goal`) und folgt ihm; ist es tot, kein Feind mehr, nicht mehr
      anvisierbar oder außer Aggro-Reichweite, hört sie sofort auf zu drehen (vorher drehte sie bis zur Richtung
      eines schon toten Ziels weiter).
    - **Drehrate im Sitzen** (`Golem.sit_turn_rate_at`): bei 30 m wie bisher 1/8 der Stand-Drehrate (41°/s), linear
      in der Höhe auf **13°/s bei 80 m** (vorher 9,1°/s) und mit derselben Neigung weiter bis **9,5°/s** (ab rund
      86 m). Der **Dämonengolem dreht 15 % schneller** (`DEMON_GOLEM_TURN_SPEEDUP`, im Stand und im Sitzen).
    - **Die Drehung zählt in der Wahl** (`_turn_sweep`, `_plan`): sie rechnet auch die Pläne von 16 Richtungen rundum
      (`GOLEM_SIT_TURN_PLAN_HEADINGS`, mindestens 20° daneben) — je Plan das, was `_choose` mit beiden freien Kanälen
      wählen würde — und schlägt die Drehzeit wie im Stand als Vorlauf auf, verteilt auf 3 Angriffe
      (`GOLEM_SIT_TURN_PLAN_ATTACKS`: Wert × Abklingzeit / (Abklingzeit + Drehzeit / 3)). Ist der beste gedrehte Plan
      mehr wert als der jetzige, dreht sie sich dorthin. Gerechnet werden 4 Richtungen je Überlegung
      (`GOLEM_SIT_TURN_PLAN_PER_THINK`, eine Runde ≈ 1 s), währenddessen greift sie normal an. In gedrehten Richtungen
      gilt die Ausnahme „ein Ziel reicht für einen großen Angriff“ nur, wenn sie jetzt nichts erreicht (sonst drehte sie
      sich weg, um einen einzelnen Feind mit dem Handstampfer zu treffen). Beim Drehen prüft sie jede Überlegung, ob
      sich der Rest der Drehung noch lohnt (`_turn_still_pays`), sonst hört sie auf. Faustregel (Stampfer): bei 31 m
      lohnt eine Vierteldrehung ab etwa dem 1,5-Fachen des jetzigen Werts, eine halbe ab dem 2-Fachen; bei 80 m ab dem
      2,2- bzw. 3,4-Fachen.
    - **Alle Sitzzonen wachsen genau mit dem Körper** (Nutzervorgabe 2026-11-18): Stampfer-, Handstampfer- und
      Doppelstampfer-Kreis sowie die Reichweite des Wischers hängen nicht mehr an Handschlag-, Trommel-Radius und
      Reichweite im Stand (die wachsen langsamer als der Körper), sondern an deren Werten beim normalen Golem in seiner
      ersten Sitzgröße (31,3 m), skaliert wie das Modell. Seit derselben Runde gilt das schon im Stand: Flächen und
      Reichweiten wachsen dort ab 30 m mit dem Körper (`GOLEM_BODY_*`, s. `CLAUDE.md`); die Sitzzonen nehmen
      Handschlag-, Trommel-Radius und Reichweite wieder direkt aus dem Stand. Lage, Bein-Schneisen und Po-Klatscher taten das schon. Damit bleibt die Aufteilung über alle Größen
      und bei allen drei Golems gleich; bei 31,3 m ändert sich nichts. Der Dämonengolem ist 25 % breiter gebaut, seine
      Zonen auch. Radien (vorher in Klammern): Golem 80 m Stampfer 12,1 (8,1), Wischer 35,9 (31,0), Handstampfer
      16,8 (11,2), Doppelstampfer 16,0 (10,7) m; Dämonengolem 119 m Stampfer 22,5 (8,0), Wischer 66,8 (43,3) m;
      Genesisgolem 100 m Stampfer 15,2 (6,1) m. Test `test_sit_zones_grow_exactly_with_the_body`.
    - **Einebnen im Sitzen** (2026-11-18): beim Hinsetzen sofort der Auswahlkreis um die Sitzmitte, danach nach und
      nach (0,1 m/s) das Rechteck der Figur in ihrer aktuellen Blickrichtung; nur gesenkt, Gelände unter Fußhöhe
      bleibt. Die Liegehöhe folgt dem sinkenden Boden.
    - **Terrain beim Sitzen und Drehen** (2026-11-18): Füße und Hände müssen auf erklimmbarem Boden aufsetzen
      (`sit_pose_ok`, Laufregel des Giganten, Wasser zählt nicht); gedreht wird nur über mögliche Richtungen
      (`free_arc`, `turn_way`), notfalls den langen Weg; unerreichbare Richtung: keine Drehung. Gebäude zählen nur
      beim Hinsetzen. Unmögliche Lage (Wachsen, Boden): zur nächsten möglichen Richtung drehen, sonst aufstehen.
      Plan-Drehung erst ab 20 % mehr Wert; während des Drehens kein Angriff, außer die Lage ändert sich; immer der
      kurze Weg, sobald er frei ist (Bugfix: falsch herum hinter einem Ziel, das die Seite wechselte).
    - **Gebäude und Fahrzeuge** (2026-11-18): Gebäude nehmen je Treffer die Hälfte des Schadens in Lebenspunkten
      (keine ganze Stufe mehr); feindliche Bodenfahrzeuge werden getroffen (Schadensschritt wie im Stand),
      Luftschiffe nicht.
    - **Bugfix:** die Ausweichdrehung zum nächsten Feind („nichts erreichbar“) kam auch, wenn nur der freie Kanal
      nichts erreichte, während der andere mit einem Feind in seiner Zone abklang — sie drehte sich von ihm weg.
      Jetzt nur, wenn kein Angriff etwas erreicht.
    - **Rechenzeit:** Orte der Glieder und Größen der Zonen werden je Blickrichtung, Position und Größe zwischengespeichert
      (`_frame`), vor jeder Zonenprüfung steht ein grober Kreistest (`bound_of`). Messung (Debug, 80 Feinde, 6 Hütten):
      eine Wahl 3,3 ms statt 26–61 ms, eine Überlegung mit 4 gedrehten Richtungen rund 16 ms.
- *Stand davor (Vorschläge):*
- **Doppelklatscher**: beide Hände schlagen neben ihr auf (Kreis um jede Hand); **sperrt die Füße**.
- **Doppelstampfer**: beide Füße (Kreis um die Füße, 1,5 × Handschlag-Radius: Vorschlag); **sperrt
  die Arme**.
- Die großen drei sind Flächenangriffe: erst ab 3 Feinden in der Fläche (Vorschlag).
- **Zwei Kanäle** (Beine, Arme) mit eigener Ausholzeit und Abklingzeit, gleichzeitig möglich; die
  großen Angriffe belegen beide. Wahl nach Schaden je Sekunde (ein großer Angriff gegen die besten
  Einzelangriffe beider Kanäle zusammen).
- **Drehen im Sitzen**: erreicht kein Glied einen Feind, dreht sie sich zum nächsten im Aggro-Radius
  (ab 20° Abweichung), mit 12,5 % ihrer Drehrate im Stand (2026-11-17 halbiert, vorher 25 %), um den Po (ihr Standpunkt bleibt). **Während
  des Drehens keine Angriffe** — außer dem Po-Klatscher (seit 2026-11-18). Die Sitzfläche dreht mit; der Sitzschaden trifft weiter nur, wer beim
  Aufsetzen darunter stand.
- **Werte vorerst geborgt** (Vorschlag, Nutzer legt fest): Stampfer und Wischer wie der Handschlag,
  Bein strecken wie der Tritt, Doppelklatscher und Doppelstampfer wie das Trommeln (alle drei Schläge
  in einem), Po-Hüpfer doppelter Sprung (= 4 × Trampeln); Takt, Ausholzeit und Zielzahl ebenso.
- **Noch nicht**: Gebäude und Fahrzeuge als Ziele der Sitzangriffe, Rückstoß, Luftschiffe; ob Füße
  und Hände beim Drehen über Gebäude oder Wasser wandern dürfen.

**Animationsebenen** (`GolemSitAnim`): ein `AnimationTree` über dem `AnimationPlayer` des Modells —
Grundclip (`sit_idle`, beim Drehen `sit_turn_l/_r`), darüber je ein OneShot für die **Beine** (Filter
auf die Beinknochen), die **Arme** (Armknochen) und den **ganzen Körper** (ohne Filter), jeder mit
eigenem Tempo. Die Spuren werden aus `sit_idle` gelesen. Der Baum wird nur aktiv, solange sie sitzt
und das Modell wenigstens einen der Clips unten hat.

#### Clipvertrag der Sitzangriffe

| Clip | Ebene (Knochen) | Aufschlag bei Tempo 1 | Was passiert |
|---|---|---|---|
| `sit_stomp_l` / `sit_stomp_r` | Beine (nur `*UpperLeg`, `*LowerLeg`, `*Foot`) | 0,35 s | ein Fuß hebt ab und stampft auf (Fuß-Stampfer, links/rechts) |
| `sit_kick_l` / `sit_kick_r` | Beine | 0,5 s | ein Bein schnellt gestreckt nach vorn (Bein strecken, lange Schneise) |
| `sit_wipe_l` / `sit_wipe_r` | Arme (nur `*Shoulder`, `*UpperArm`, `*LowerArm`, `*Hand`) | 0,35 s | EIN Arm löst sich aus der Stütze und fegt seitlich/leicht hinter ihr über den Boden |
| `sit_hop` | ganzer Körper | 0,6 s | Po-Hüpfer: auf die Hände gestützt den Po heben und plumpsen lassen |
| `sit_clap` | ganzer Körper | 0,35 s | Doppelklatscher: beide Hände heben ab und schlagen neben ihr auf |
| `sit_double_stomp` | ganzer Körper | 0,35 s | Doppelstampfer: beide Füße kurz heben und aufschlagen |
| `sit_turn_l` / `sit_turn_r` | Grundclip (alle Knochen), Schleife | – | langsames Drehen im Sitzen um den Po (rutschen/umsetzen) |
| `sit_grow` | ganzer Körper | – (1,0 s lang) | Strecken beim Wachsen im Sitzen |

Alle beginnen und enden in der Ruhe im Sitz (Pose von `sit_idle` bei 0 s), damit die Ebenen ohne
Sprung ein- und ausblenden. Ein Clip der Bein- oder Armebene darf andere Knochen enthalten — das
Spiel filtert sie weg —, sollte sie aber in der Ruhepose lassen. Das Spiel spielt jeden
Angriffsclip so schnell, dass sein Aufschlag auf die Ausholzeit fällt (`GolemSitAnim.SIT_CLIP_IMPACT`);
die Aufschlagzeiten oben sind Vorschläge und werden mit den Clips festgelegt.

## Nutzervorgaben (2026-11-16/17)

- Dritte Haltung **Sitzen** für **alle Golems ab 30 m Körperhöhe** (Golem und
  Dämonengolem; Golem nach ~267 Kills, Dämonengolem ab Wachstumsstufe 28 = 138 Kills).
- **Nur manuell**: Hinsetzen und Aufstehen löst ausschließlich der Spieler aus. Die
  Haltungsautomatik (`_choose_attack`, `_tick_stance`) setzt ihn nie hin und lässt ihn
  nie von selbst aufstehen. **Die KI benutzt Sitzen vorerst nicht.**
- **Reihenfolge:** stehen → bücken (vorhandener Wechsel) → hinsetzen. Aufstehen
  rückwärts und **endet stehend**.
- **Dauer bücken → sitzen: 3 s bei 30 m** (lang, gewollt). **Aufstehen dauert genauso
  lang** (sitzen → gebückt 3 s bei 30 m, danach der normale Wechsel zum Stehen).
- **Taste `V`** (Hinsetzen/Aufstehen im Wechsel), dazu Knöpfe in der Seitenleiste.
- **Drehen im Sitzen ist möglich, aber langsam**, möglichst mit eigener Animation.
- Im Sitzen **keine Bewegung**. **Bewegungs- und Angriffsbefehle werden ignoriert**
  (Abgelehnt-Ton), solange er sitzt; nur „Aufstehen“ wirkt.
- **Nicht auf Gebäude:** die Sitzfläche darf kein Gebäude und keine Baustelle berühren.
  Gibt es keinen freien Platz **innerhalb eines halben Körperradius**, wird der Befehl
  ignoriert.
- **Sitzschaden (Friendly Fire):** die Fläche deckt **nur den Körper** ab (leicht oval
  bzw. rechteckig, genaue Form legt der Nutzer noch fest). Schaden = **4 × Trampelschaden**,
  **alle 5 s, solange er sitzt**. Getroffen wird, was beim Hinsetzen darunter liegt;
  **neu herankommende Ziele werden nicht verletzt**. **Die Opfer dürfen herauslaufen**
  (werden nicht festgehalten) — wer draußen ist, nimmt keinen Sitzschaden mehr.
- **Eigene Opfer zählen nicht als Kill** (kein Heilen/Wachsen durch eigene Einheiten).
- **Zielradius für Gegner massiv erhöht** (er ist im Sitzen das größere Ziel).
- **Wachsen im Sitzen:** eigene Streck-Animation im Sitzen, er steht dafür **nicht** auf.
- **Sitzangriffe:** Arme und Beine greifen **unabhängig** an — **zwei Kanäle (Beine,
  Arme)** — und haben wegen ihrer Lage **verschiedene Zielbereiche und Reichweiten**. Erstmal: **Beine = Stampfer**,
  **Arme = Wischer**. Sitzposition: angewinkelte Beine vor sich, Arme locker hinten/
  seitlich abgestützt.

## Umsetzung (Schritte)

1. **Haltung `STANCE_SIT`** in `golem.gd`, `can_sit()` = `height_m() >= GOLEM_SIT_MIN_HEIGHT`
   (30). Gilt über die Basisklasse auch für `DemonGolem`.
2. **Übergänge als Zwei-Schritt-Wechsel:** `_begin_sit()` startet den normalen Bückwechsel
   (`stance_switch_time()`, bei 30 m ~1,0 s), danach `sit_down` mit
   `sit_switch_time()` = 3 s × Wurzel(Höhe / 30) (Vorschlag: 100 m ≈ 5,5 s, gleiche
   Skalierung wie der Haltungswechsel). Aufstehen: `sit_up` (gleiche Dauer wie
   `sit_down`), dann `crouch_up`, Ende stehend. Während der Übergänge: kein Angriff, keine Bewegung.
3. **Befehle:** `TribeCommands.order_golem_sit(units)` / `order_golem_stand(units)`;
   nicht berechtigte Golems (unter 30 m, schon sitzend, im Wechsel) werden übersprungen,
   ist keiner übrig oder kein Platz: Rückgabe 0 → Abgelehnt-Ton. In der Seitenleiste
   (Golem-Ansicht) Knöpfe „Hinsetzen“ / „Aufstehen“, dazu **Taste `V`** (neue
   Eingabeaktion `golem_sit_toggle`: sitzt keiner der gewählten Golems, setzen sich alle
   berechtigten hin, sonst stehen alle sitzenden auf). Gemischte Auswahl: sitzende Golems ignorieren Bewegungs-/Angriffsbefehle,
   der Rest führt sie aus.
4. **Sitzplatz (`find_seat`)**: Sitzfläche (Form aus Schritt 5) frei von Gebäuden und
   Baustellen (eigene und fremde), ganz auf der Scheibe (`in_disc`), an Land. Gesucht
   wird an der eigenen Stelle, dann bis **halber Körperradius** (30 m: ~2,5 m) daneben;
   gefunden → kurzer Schritt dorthin vor dem Bücken, sonst Befehl ignorieren.
5. **Sitzschaden:**
   - Fläche in Körperrichtung, nur der Körper: Gesäß + Oberschenkel bis zu den Füßen
     (Form/Maße: offen, Nutzer).
   - **Beim Aufsetzen** (Ende von `sit_down`) wird die Opferliste festgelegt: alle
     Einheiten in der Fläche, **alle Stämme**. Nur diese nehmen Schaden: 4 ×
     `trample_damage()` sofort und dann alle 5 s, solange sie noch in der Fläche
     stehen, bis sie tot sind oder er aufsteht (30 m: 24 je Tick → Brave 60 LP nach 3
     Ticks, Krieger 120 LP nach 5).
   - **Opfer dürfen herauslaufen** (keine Sperre); wer die Fläche verlassen hat, fällt
     aus der Liste und wird auch beim Zurückkommen nicht mehr getroffen.
   - Wer später unter ihn läuft, wird nicht getroffen — auch nicht, wenn die Fläche
     durch Drehen über ihn wandert.
   - Eigener Schadensweg ohne Stammesfilter; `_credit_kill` nur für fremde Opfer.
6. **Drehen im Sitzen:** langsam, `sit_turn_rate()` = `turn_rate()` ×
   `GOLEM_SIT_TURN_SHARE` (Wert offen, Vorschlag 0,25), Clip `sit_turn_l` /
   `sit_turn_r` während der Drehung. Die Arme greifen dabei nicht an (sie setzen um),
   die Beine schon (Vorschlag). Damit beim Drehen nie ein Gebäude unter die Sitzfläche
   gerät, prüft `find_seat` den **Kreis um die Sitzfläche** statt nur die Fläche in der
   aktuellen Richtung (Vorschlag).
7. **Fest am Platz:** alle Bewegungsquellen sperren — Wegsuche, Angriffsmove,
   Zurückschlagen (`_maybe_retaliate`), Luftschiffjagd (`_tick_air_chase`), Abstand der
   Golems (`_tick_golem_separation`: ein Sitzender wird nicht geschoben, der andere weicht
   ganz aus), Trampeln (läuft nicht), Strecken (`_tick_stretch` ohne Aufstehen, Clip
   `sit_grow`). Er greift nur an, was er vom Platz aus erreicht.
8. **Zielradius:** `target_radius()` im Sitzen × `GOLEM_SIT_TARGET_RADIUS_FACTOR`
   (Faktor offen). Prüfen, ob `soa_reach` im UnitManager den Wert zwischenspeichert.
9. **Sitzangriffe** (eigenes Modul in `golem.gd`, nur in `STANCE_SIT`):
   - **Zwei Kanäle, Beine und Arme** (Nutzerentscheidung), jeder mit eigener Ausholzeit und Abklingzeit;
     beide dürfen gleichzeitig laufen.
   - **Stampfer (Beine):** Fläche um die Füße vor ihm (links/rechts).
   - **Wischer (Arme):** Bogen um die abgestützten Hände, seitlich und hinter ihm.
   - Zielwahl je Kanal wie bisher nach Schaden je Sekunde, Zielanteil der Grundzahl
     (`GOLEM_TARGET_PERCENT_*`), Schaden/Flächen skalieren mit der Größe.
   - Werte: offen (Nutzer oder mein Vorschlag nach Freigabe).
10. **Optik ohne Clips:** solange `sit_*` fehlen, wird das Modell im Sitzen um ~45 %
   abgesenkt (nur Optik), sonst sähe er gebückt aus.
11. **Tests** (`test_golem.gd`): Freischaltung ab 30 m; Reihenfolge und Dauern der
    Übergänge (Aufstehen so lang wie Hinsetzen); Taste `V`; Drehen im Sitzen langsamer
    als im Stand; nur manuell (Automatik setzt nie hin und steht nie auf); Bewegungs- und
    Angriffsbefehle im Sitzen ignoriert; kein Sitzplatz auf/an Gebäuden, Ausweichen bis
    halber Körperradius, sonst ignoriert; Sitzschaden trifft eigene Einheiten, nur die
    beim Aufsetzen darunter Liegenden, alle 5 s, Herausgelaufene nicht mehr; eigene Opfer kein Kill; Zielradius im
    Sitzen; Wachsen im Sitzen ohne Aufstehen; Arme und Beine unabhängig; KI nutzt es nie.
    Dazu Spalten in `tests/diag_golem_values.gd` und `diag_demon_golem_values.gd`.
12. **Doku:** `CLAUDE.md` §4 (Golem und Dämonengolem), `PROGRESS.md`,
    `gymnastikschuh/LIESMICH_POPULOUS.md` (Clipvertrag).

## Clipvertrag (für die spätere Animation)

| Clip | Zweck | Länge bei Tempo 1 (Vorschlag) |
|---|---|---|
| `sit_down` | gebückt → sitzend, endet in `sit_idle` | 3,0 s |
| `sit_up` | sitzend → gebückt (so lang wie `sit_down`) | 3,0 s |
| `sit_idle` | Ruhe im Sitzen (Beine angewinkelt, Arme hinten/seitlich gestützt) | Schleife |
| `sit_grow` | Strecken beim Wachsen im Sitzen | 1,0 s |
| `sit_turn_l` / `sit_turn_r` | langsames Drehen im Sitzen (Schleife, rutscht/setzt um) | Schleife |
| `sit_stomp_l` / `sit_stomp_r` | Stampfer linkes/rechtes Bein | offen |
| `sit_wipe_l` / `sit_wipe_r` | Wischer linker/rechter Arm | offen |

## Hindernisse

- **Arme und Beine gleichzeitig animieren:** heute spielt `_play_clip` genau einen Clip
  auf dem `AnimationPlayer`. Unabhängige Glieder brauchen einen `AnimationTree` mit
  Bone-Filtern (Ober-/Unterkörper) oder getrennte Teil-Clips; die Baukette in
  `gymnastikschuh` (`golem_bewegung.mjs`, `golem_export.mjs`) muss dafür Clips liefern,
  die nur die Arm- bzw. nur die Beinknochen bewegen. Größter Umbau des Vorhabens.
- **Viele Bewegungsquellen** (Schritt 6): jede vergessene Stelle lässt ihn im Sitzen
  rutschen. Wird über Tests je Quelle abgesichert.
- **Gefangene unter ihm:** dürfen herauslaufen (entschieden); der Sitzschaden trifft
  damit vor allem Langsame, Sitzende (Bekehrung), Kämpfende und Gebäudebesatzung nicht.
- **Drehen mit fester Sitzfläche:** dreht er sich, wandert die ovale Fläche — der
  Gebäudetest muss daher den Kreis um sie prüfen, was den Sitzplatz weiter verknappt.
- **Sitzplatz in Basen:** bei 30 m ist die Sitzfläche grob 10–15 m groß; mit Bauabstand
  1 m und nur 2,5 m Ausweichen wird er in dichten Basen selten Platz finden (so gewollt).
- **Gelände unter ihm** (Erdbeben, Absinken, sein Einebnen): Vorschlag, er bleibt sitzen,
  Ertrinken nach der vorhandenen Regel.

## Offene Punkte

1. Form und Maße der Sitzfläche (Nutzer legt fest).
2. Erster Sitzschaden-Tick sofort beim Aufsetzen (Vorschlag) oder erst nach 5 s?
3. Zielradius im Sitzen: welcher Faktor (Vorschlag × 3)?
4. Stampfer und Wischer: Flächen, Reichweiten, Schaden, Tempo.
5. Tempo der Drehung im Sitzen (Vorschlag 25 % der Drehrate im Stand); greifen die Arme
   während der Drehung an (Vorschlag: nein)?
6. Luftschiffe im Sitzen schlagen? Fahrzeuge/Bäume unter der Sitzfläche? Einebnen im
   Sitzen?
7. Wächst die Opferliste mit, wenn er im Sitzen wächst (Vorschlag: nein)?

## Entschieden (2026-11-17)

- Opfer dürfen herauslaufen.
- Zwei Angriffskanäle: Beine und Arme.
- Drehen im Sitzen möglich, langsam, möglichst mit Animation.
- Aufstehen dauert so lang wie Hinsetzen.
- Taste `V`.
