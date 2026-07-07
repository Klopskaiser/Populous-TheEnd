# Phase 7f — Belagerungswaffe & Werkstatt

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).

## Ziel

Eine neue Einheit **Katapult** (Belagerungswaffe): in einer neuen **Werkstatt**
kontinuierlich aus Holz gefertigt, **von Braves bemannt**, **langsam**,
**große Reichweite**; ihre Geschosse machen **Zerstörungsstufen an Gebäuden
UND Flächenschaden an Einheiten**. Der **Belagerungs-Spezialist** über der
generellen Gebäudezerstörung aus [Phase 7g](07g_building_assault.md): normale
Einheiten demolieren im Nahkampf/mit halbem Fernkampf-Effekt und priorisieren
Gebäude zuletzt — das Katapult zerlegt aus Distanz in vollen Stufen und
priorisiert Gebäude ZUERST. Bewusst zuletzt in der Reihe: profitiert von 7g
(Targeting), 7e (Sprites) und 7c (Projektil-/AoE-Code).

**Kernunterschied zu allen bisherigen Einheiten:** Das Katapult ist ein
**Fahrzeug** — ein reines 3D-Objekt ohne eigenen „Willen", das nur handelt,
wenn es **bemannt** ist. Die Besatzung sind separate Braves, die mit dem
Katapult mitlaufen. Das Katapult selbst hat **keine HP und ist nicht direkt
angreifbar** — Angreifer treffen immer nur die Besatzung. Es gehört dem Stamm,
der es gerade bemannt, und kann den Besitzer wechseln.

## Voraussetzungen

- `TrainingBuilding`-Maschinerie (Queue-Windungen, Slot-Anlauf,
  `_admit_front`/`_finish_one`-Trainee-Swap, Rally, Produktionsbalken).
- Holz-Absorb-Pipeline der Gebäude (`wants_more_wood`/`_absorb_piles` beim
  Bau, `repair_wood`-Puffer bei Reparatur — Muster für Produktions-Holz und
  den Holzvorrat vor der Werkstatt).
- `Firewarrior` als Fernkampf-Vorlage (`_tick_attack`-Override, Projektil via
  `UnitManager.register_projectile`), `fireball_bolt.gd` als Parabel-Vorlage
  (Bogen + Schweif).
- **Phase 7g:** generisches Gebäude-Targeting (`order_attack_building`,
  Rechtsklick-Routing, Scan-Fallback) und Auswurf-/Sturmregeln.
- Gebäude-Schadenssystem (`apply_destruction_stages`, Fragil-Regel für
  Baustellen), Lava-/Schockwellen-Mechanik & Roll-Chance nach Hangneigung
  (Phase 7c/5d: `start_roll`, `ROLL_END_SLOPE`, Slope-abhängige Roll-Chance),
  KI-Wellen (`attack_wave_size`), 8-Richtungs-Atlas (7e).

## Designparameter (bewusst gewählt, hier dokumentiert)

Alle Zahlen sind Balance-Startwerte für Phase 8. Ableitungen aus der Vorgabe:

| Parameter | Wert | Herkunft/Auslegung |
|---|---|---|
| Werkstatt-Holzkosten | **15** | Vorgabe |
| Werkstatt-Footprint | **8×4** Zellen | „doppelt wie Hütte" (Hütte = 4×4); doppelte Grundfläche |
| Werkstatt-Arbeiterplätze | **max 3** | Vorgabe. Produktion braucht ≥ 1 Arbeiter |
| Katapult-Holzkosten | **5** je Stück | Vorgabe |
| Reine Bauzeit | **30 s bei 3 Arbeitern** | Vorgabe. Modell: **90 Arbeiter-Sekunden** je Katapult → 1 Arbeiter 90 s, 2 Arbeiter 45 s, 3 Arbeiter 30 s |
| Holzvorrat vor Werkstatt | **Ziel 15** | Vorgabe (Puffer = 3 Katapulte); Arbeiter füllen auf, wenn nicht in Produktion |
| Katapult-Crew (Bewegung) | **min 1** | Vorgabe |
| Katapult-Crew (Angriff) | **min 2** | Vorgabe. Bei 1 Crew Feuerrate = 0 |
| Katapult-Crew (Auto-Besetzung) | **2** idle Braves in der Nähe | Vorgabe |
| Katapult-Crew (Maximum) | **6** (3 je Seite) | „3 leute an jeder seite"; mehr Crew ⇒ höhere Feuerrate |
| Feuerrate ↔ Crew | 1→0, 2→1 Schuss/6 s, …, 6→1 Schuss/3 s | linear zwischen 2 und 6 (Startwerte, Phase-8-Balance) |
| Bewegungsgeschwindigkeit | **0,75 × Brave** | Vorgabe (langsamste Einheit) |
| Katapult-Maße (Nav-Footprint) | **1 m × 2 m** | Vorgabe → braucht breitere Wege als ein Brave |
| Reichweite | **15 m** max, **3 m** min | Vorgabe (Bogenschuss, Mindestreichweite) |

> **Assumptions, die zu bestätigen sind (Phase-8-Balance):** Footprint 8×4,
> Crew-Maximum 6, Feuerraten-Kurve und die 90-Arbeiter-Sekunden-Regel sind
> gewählte Startwerte, keine harte Vorgabe.

## Deliverables

### 1. Werkstatt — `scripts/buildings/workshop.gd` + `scenes/buildings/workshop.tscn`

`TrainingBuilding`-Subklasse „Werkstatt", Holzkosten **15**, Footprint **8×4**,
HP ~350, mit folgenden Erweiterungen:

- **Bemannung (max 3 Arbeiter):** Braves treten wie beim Training ein
  (`_admit_front` sammelt bis zu `MAX_WORKERS = 3`). **Produktion läuft nur mit
  ≥ 1 Arbeiter**; Fertigungstempo skaliert mit Arbeiterzahl (90 Arbeiter-
  Sekunden je Katapult → 3 Arbeiter = 30 s). Werden Arbeiter rausgeworfen oder
  stirbt/beschädigt das Gebäude, **pausiert** die Fertigung; **kein Holz wird
  erstattet** (auch nicht der bereits verbrauchte 5-Holz-Anteil).
- **Holzvorrat-Logik (Ziel 15 vor dem Eingang):** Die Arbeiter beschaffen Holz
  wie beim Bau und legen es **vor dem Gebäude ab** (sichtbare Stapel, Muster
  `_absorb_piles`/`repair_wood`). Sie halten den Vorrat auch dann auf Ziel
  **15**, wenn nichts produziert wird — solange sie nicht gerade im aktiven
  Produktionsprozess sind. Ein Katapult verbraucht **5 Holz aus dem Vorrat im
  Moment des Produktionsstarts** (das Holz **verschwindet**, kein Rückfluss).
  Ohne genügend Vorrat wartet die Fertigung (`wood_stalled`-Recheck-Muster).
- **Steuerung durch den Spieler:**
  - **Pause-Toggle:** Produktion pausierbar (Arbeiter füllen weiter den
    Holzvorrat, bauen aber kein Katapult).
  - **Max-Katapult-Grenze:** einstellbarer Zielwert; besitzt der Stamm bereits
    ≥ so viele **bemannte** Katapulte, stoppt die Werkstatt die Fertigung
    automatisch (Recheck bei jedem Fertigungsstart und bei Crew-Änderungen).
- **Auswurf am Eingang:** Fertiges Katapult erscheint **am Eingang**
  (`entrance_cell`). Solange dort ein noch nicht weggefahrenes Katapult steht,
  **startet keine weitere Fertigung** (Ausgang blockiert). Erst wenn das
  Katapult wegbewegt wurde (nach Bemannung), läuft die nächste Fertigung an.
- **Auto-Besetzung:** Direkt nach dem Auswurf besetzen **bis zu 2 idle Braves
  in der Nähe** das Katapult automatisch (Radius-Scan). Ist niemand in der Nähe,
  bleibt es **unbemannt** am Eingang stehen (blockiert damit die Werkstatt, bis
  es manuell bemannt/weggeführt wird).

### 2. Einheit / Fahrzeug — `scripts/units/siege_engine.gd` + `scenes/units/siege_engine.tscn`

`SiegeEngine` (`unit_kind &"siege"`) — **kein normaler `Unit`-Kämpfer**,
sondern ein bemannbares Fahrzeug:

- **3D-Objekt**, kein Billboard-Sprite: 3D-Modell (Placeholder aus BoxMesh +
  Wurfarm-PrismMesh, siehe Rendering). Nav-Footprint **1 m × 2 m**.
- **Keine eigene HP, nicht direkt angreifbar.** Angriffe/Zauber treffen nur die
  Besatzung (die Crew-Braves sind normale, verwundbare Einheiten). Das Katapult
  ist **kein Ziel** in Scan-/Targeting-Listen.
- **Besitz = wer es bemannt.** `tribe` folgt der aktuellen Crew. Wechselt die
  Crew (alte stirbt/flieht, neue übernimmt), **wechselt der Besitzer**.
  **Unbemannte** Katapulte können **jederzeit von jedem Stamm** übernommen
  werden (auch auf offenem Schlachtfeld).
- **Bewegung:** Speed **0,75 × Brave**, nur ab **1 Crew**. Braucht durch den
  breiteren Footprint (1×2 m) **breitere Wege**; Pfad über NavGrid mit
  Fahrzeug-Clearance (schmale Lücken sind unpassierbar) — falls kein Pfad,
  bleibt stehen. Die **Crew läuft mit** (3 Plätze je Längsseite; Positionen
  relativ zum Katapult, Y aus dem Terrain).
- **Angriff:** nur ab **2 Crew**. Reichweite **15 m**, **Mindestreichweite 3 m**
  (nähere Ziele → rückt NICHT näher an, hält Abstand / kann nicht feuern).
  Feuerrate skaliert mit Crew (2 → langsam, 6 → schnell; 1 → kein Angriff).
  Beim Schuss **steht** das Katapult (Firewarrior-Muster).
  **Auto-Aggro-Priorität: Gebäude vor Einheiten** (invers zur Normalregel).
- **Kein Panik-Selbstlauf des Fahrzeugs**; panik-/konvertierbar ist es nicht
  (Gerät, kein Gläubiger) — Effekte greifen an der **Crew**, nicht am Gerät.

### 3. Crew-System (Besatzung)

Kann in `siege_engine.gd` (Crew-Verwaltung) + kleine Hooks in `unit.gd`
(Zustand „an ein Katapult gebunden") liegen:

- **Wer:** **alle Einheiten außer der Schamanin** können ein Katapult besetzen
  (Braves und Kampfeinheiten). Zuweisung per **Rechtsklick** einer selektierten
  Einheit auf ein (eigenes oder unbemanntes) Katapult.
- **Auto-Besetzung nach Produktion:** 2 idle Braves in der Nähe (siehe
  Werkstatt); niemand da → keine Auto-Besetzung.
- **Verhalten der Crew:** konzentriert sich auf **Steuern + Feuern**, **greift
  nicht von sich aus** in Kämpfe ein. **Wird sie angegriffen, verteidigt sie
  sich** und verlässt dafür bei Bedarf den Posten. Sie **zählt weiter als
  Crew**, solange sie **nicht zu weit** vom Katapult weg ist
  (`CREW_LEASH`-Radius), und **kehrt nach dem Kampf zurück**. Entfernt sie sich
  dauerhaft zu weit / stirbt sie, **verliert das Katapult diese Crew**.
- **Besitzerwechsel:** Fällt die Crew unter Minimum bzw. auf 0, wird das
  Katapult **unbemannt** (und bewegungs-/kampfunfähig). Übernimmt danach eine
  Crew eines anderen Stamms, wechselt der Besitzer.

### 4. Projektil — `scripts/units/siege_shot.gd`

Großer Feuerball in **hoher Parabel mit Schweif** (Vorlage `fireball_bolt`);
Einschlag unterscheidet Ziel:

- **Trifft ein Gebäude:** **+1 Zerstörungsstufe** (`apply_destruction_stages`,
  Footprint-+1-Suche wie der Blitz) **und tötet alle dort stationierten
  Einheiten** (Insassen/Garnison). Baustelle → Fragil-Regel (sofort zerstört).
- **Trifft Einheiten/Boden:** hinterlässt **eine kleine Menge Lava im Zentrum**
  des Einschlags, die **schnell wieder verschwindet** (übliche Lava-Optik und
  -Schadenswirkung aus 7c). Zusätzlich **Schockwelle im Radius 2 m**:
  **¼ Brave-Leben Schaden**; **Roll-Chance nach Hangneigung** bei getroffenen
  **Feinden**:
  - flacher Boden → **40 %**, leichter Hang → **80 %**, steiler Hang → **100 %**.
  - Rolldauer ist **auf flachem Boden kürzer**, aber **mindestens 1 s**
    (`start_roll` mit slope-abhängiger Dauer, Minimum erzwingen).
- **Friendly Fire:** an Einheiten JA im Radius (Steine kennen keine Freunde →
  Positionierung wird taktisch); **eigene Gebäude werden NICHT beschädigt**
  (Frustschutz). Die Schamanin ist gegen den Panik-/Roll-Effekt so behandelt
  wie im übrigen Spiel (Immunität dort, wo dokumentiert).

### 5. Gebäude-Targeting (aus Phase 7g)

Das generische Targeting existiert bereits (7g: `order_attack_building` für
alle, Rechtsklick-Routing, Scan-Fallback mit NIEDRIGSTER Gebäude-Priorität).
Die SiegeEngine ändert nur ihre Prioritäten: **Gebäude ZUERST** im Scan (invers
zur Normalregel) und ihr Beschuss macht **volle Zerstörungsstufen** per
Steinwurf statt des halbierten Feuerkrieger-HP-Schadens; sie betritt Gebäude
NIE (reiner Fernkämpfer, kein Sturm).

### 6. Rendering — `unit_renderer.gd`, `placeholder_sprites.gd`

Kind `&"siege"` wird als **3D-Modell** gerendert (nicht Billboard): Placeholder
= breiter Holzrahmen (BoxMesh) + Wurfarm (PrismMesh), „attack" = Wurfarm
schnellt hoch (kleine Tween-Animation). Die **Crew-Braves** werden als normale
8-Richtungs-Sprites (7e) an ihren Seiten-Positionen dargestellt. Stammfarbe des
Katapults folgt dem aktuellen Besitzer (`modulate`/Material des Fahnenteils).

### 7. KI — `ai_controller.gd`, `ai_state.gd`

- Werkstatt in `_next_building_scene` (nach dem Tempel, 1× im Grundausbau).
- Die KI **stellt Braves als Werkstatt-Arbeiter ab** (bis zu 3) und **bemannt
  ausgeworfene Katapulte** mit idle Braves (nutzt dieselbe Auto-Besetzung wie
  der Spieler — keine Cheats).
- ATTACK: bemannte Katapulte marschieren mit der Welle (Wellen-Tempo an den
  0,75-Speed anpassen bzw. Katapulte als eigene, langsamere Vorhut führen); ihre
  Gebäude-Priorität erledigt die Belagerung automatisch.
- Ziel ~1 Katapult je Welle ab Welle 2; Max-Katapult-Grenze der Werkstatt
  nutzen, damit die KI nicht endlos produziert.

### 8. UI — `sidebar.gd`, `ui_theme.gd`

- Baumenü-Eintrag „**Werkstatt (15 Holz)**" + Icon.
- **Werkstatt-Panel** (bei Selektion): Arbeiterzahl (0–3), **Pause-Toggle**,
  **Max-Katapult-Einsteller** (z. B. −/+ oder Slider), aktueller Holzvorrat
  (x/15) und Fertigungsbalken.
- Gefolgsleute-/Einheiten-Tab-Zeile „**Belagerungswaffe**"; Doppelklick-
  Typselektion greift über `unit_kind`.
- **Rechtsklick-Semantik** (SelectionManager): selektierte Einheit(en) auf
  ein Katapult → **Crew-Zuweisung**; selektiertes Katapult (mit Crew) →
  Bewegungs-/Angriffsbefehl wie bei anderen Einheiten.

### 9. Zusatz-Härtung: Roll-Zustand bricht Aktionen ab (Kampfmechanik-Check)

Übergreifender Check (nicht siege-spezifisch), hier miterledigt, weil das
Katapult massenhaft Roll-Effekte auslöst:

- **Sicherstellen:** Solange eine Einheit im **ROLL**-Zustand ist, brechen
  **alle** ihre Aktionen ab und starten nicht neu — **Angriffe, Zauber
  (Schamanin) und Bekehrungen (Prediger)**.
- Die State-Machine dispatcht per `match` (ROLL ruft `_tick_attack`/
  `_tick_cast`/`_tick_convert` ohnehin nicht auf) — **zu prüfende Lücken:**
  1. **Prediger rollt mid-Konversion:** `start_roll` muss die vom Prediger
     kanalisierten Ziele **freigeben** (Opfer-`converting_preacher` lösen,
     SIT-Ziele stehen auf), nicht nur den Prediger-State wechseln.
  2. **Opfer rollt während es bekehrt wird (SIT):** Rollt das SIT-Ziel, muss
     die laufende Konversion **abgebrochen** werden (kein „Weiter-Bekehren"
     eines rollenden Ziels).
  3. **Schamanin/Fernkämpfer mit gebundenem Ziel:** beim Eintritt in ROLL
     `attack_target`/`_cast`-Fokus lösen, damit nach dem Roll sauber neu
     gescannt wird.
- **Test:** je ein Fall (Angreifer rollt, Prediger rollt, SIT-Opfer rollt,
  Schamanin rollt) → Aktion nachweislich abgebrochen, keine Wirkung während
  des Rollens.

### 10. Tests — `tests/test_siege.gd` (neu)

## Umsetzungsschritte

1. `SiegeEngine`-Fahrzeug (kein HP/nicht angreifbar) + Crew-System (Zuweisung,
   Min-Crew Bewegung/Angriff, Besitzerwechsel, Leash/Rückkehr) headless + Tests.
2. `siege_shot` (Bogen+Schweif; Gebäude = 1 Stufe + Insassen-Kill; Einheiten =
   Lava-Klecks + 2-m-Schockwelle mit slope-abhängiger Roll-Chance) + Tests.
3. Gebäude-Targeting-Priorität (Gebäude zuerst) auf 7g aufsetzen + Tests.
4. Werkstatt (max 3 Arbeiter, tempo-skalierte Fertigung, Holzvorrat-Ziel 15,
   5-Holz-Verbrauch bei Start, Pause, Max-Katapult-Grenze, Eingang-Blockade,
   Auto-Besetzung 2 Braves) + Tests.
5. Rendering-Kind (3D-Modell + mitlaufende Crew) + UI (Baumenü, Werkstatt-Panel,
   Tab).
6. Rechtsklick: Crew-Zuweisung vs. Bewegungs-/Angriffsbefehl im
   SelectionManager.
7. **Roll-Härtung (§9)** + Tests.
8. KI-Integration (+ Sim-Lauf: KI baut Werkstatt, bemannt Katapulte, Katapulte
   marschieren mit, Gebäude fallen ohne Zauber — Match muss weiter konvergieren).
9. Verifikation, PROGRESS.md, Commit/Push.

## Tests (`tests/test_siege.gd`)

- **Fertigung:** Werkstatt + Arbeiter + Holzvorrat → nach der (tempo-
  skalierten) Bauzeit existiert 1 Katapult am Eingang; 5 Holz aus dem Vorrat
  verbraucht (kein Rückfluss). Ohne Arbeiter läuft nichts; ohne Holz stallt die
  Fertigung und läuft nach Auffüllen weiter. **Tempo:** 3 Arbeiter ≈ 30 s,
  1 Arbeiter ≈ 90 s (Arbeiter-Sekunden-Modell).
- **Vorrat/Pause/Grenze:** Arbeiter füllen den Vorrat bis 15, auch ohne
  Produktion; Pause stoppt die Fertigung (Vorrat wird weiter gefüllt);
  Max-Katapult-Grenze stoppt bei erreichter Zahl **bemannter** Katapulte.
- **Eingang-Blockade & Auto-Besetzung:** solange ein Katapult am Eingang steht,
  startet keine weitere Fertigung; 2 idle Braves in der Nähe besetzen es
  automatisch; niemand in der Nähe → bleibt unbemannt und blockiert.
- **Crew/Besitz:** min 1 Crew → bewegbar, aber Feuerrate 0; 2 Crew → feuert;
  Crew stirbt/verlässt (über Leash) → Katapult unbemannt; fremde Crew
  übernimmt unbemanntes Katapult → Besitzerwechsel; Schamanin kann NICHT
  bemannen; Katapult ist KEIN direkt angreifbares Ziel (Treffer gehen an Crew).
- **Beschuss:** Gebäude in 12 m → Schuss → +1 Stufe **und** stationierte
  Einheiten tot; Baustelle → sofort zerstört; Einheiten im 2-m-Radius nehmen
  ¼-Brave-Schaden (auch eigene), eigenes Gebäude bleibt heil; Roll-Chance
  nach Hangneigung (flach 40 % / leicht 80 % / steil 100 %), Rolldauer flach
  ≥ 1 s.
- **Reichweite/Verhalten:** 16 m → rückt nach, dann Schuss; Ziel in 2 m
  (< Mindestreichweite 3 m) → kein Schuss; Auto-Priorität Gebäude vor Einheit;
  Crew greift nicht von selbst in Kämpfe ein, verteidigt sich aber bei Angriff.
- **Roll-Härtung (§9):** Angreifer/Prediger/SIT-Opfer/Schamanin im Roll →
  Aktion abgebrochen (Konversion freigegeben, kein Cast/kein Schlag).
- **KI:** Grundausbau enthält die Werkstatt; Wellen-Mix enthält bemannte
  `siege`.

## Manuelle Prüfung

- Werkstatt bauen (großer 8×4-Umriss), Braves reinschicken; Holzstapel sammeln
  sich vor dem Eingang (bis 15) → Katapult (3D) rollt am Eingang heraus.
- 2 idle Braves in der Nähe → Katapult wird automatisch bemannt und fährt zum
  Rally-Point (langsam, Crew läuft seitlich mit); niemand da → bleibt stehen.
- Pause & Max-Katapult-Grenze in der UI testen; Grenze erreicht → Werkstatt
  stoppt.
- Rechtsklick weiterer Braves auf ein Katapult → Feuerrate steigt sichtbar;
  Crew über Leash weglocken → kehrt nach dem Kampf zurück; Crew töten →
  Katapult wird unbemannt, Gegner kann es übernehmen (Besitzerwechsel).
- Rechtsklick auf Feindgebäude → Katapult hält 3–15 m Abstand und zerlegt es
  Stufe für Stufe (Bogen + Schweif); Insassen sterben; Einschläge werfen
  umstehende Einheiten um (Roll-Chance je nach Hang) und hinterlassen kurz
  Lava.
- Katapult ohne Crew-Eskorte von Nahkämpfern angehen lassen → die Crew
  verteidigt sich, das Gerät selbst ist nicht angreifbar; fällt die Crew,
  steht das Katapult wehrlos/unbemannt.
- KI-Match: KI-Wellen bringen bemannte Katapulte mit; Spielerbasis verliert
  Gebäude auch ohne feindliche Zauber; Match konvergiert.

## Definition of Done

- [x] Testsuite grün, `--headless --quit` fehlerfrei *(1175 Tests, 0 Fehler)*
- [ ] Manuelle Prüfung bestanden
- [x] Roll-Härtung (§9) verifiziert (bricht Angriff/Zauber/Bekehrung ab)
- [x] PROGRESS.md ergänzt, Checkbox 7f in [00_overview.md](00_overview.md) abgehakt
- [x] `git add -A && git commit -m "Phase 7f: Belagerungswaffe & Werkstatt" && git push`
