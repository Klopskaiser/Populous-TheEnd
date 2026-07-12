# Phase 8.2 — Kampfgruppen (Original-Stil) & KI-Erreichbarkeits-Fixes

> Architektur-Entscheidungen und Verifikations-Befehle: siehe [00_overview.md](00_overview.md).
> **Stand 2026-07-12:** Phase 8.1 (Pfad-Worker) ist abgeschlossen und vom
> Nutzer bestätigt (Bauphase ohne Lags). Diese Phase umfasst laut
> Nutzer-Vorgabe jetzt BEIDES: das Kampfgruppen-Verhalten (Paarungsregeln
> unten) **und** die Kampf-Performance (Deliverable 4) — Benchmark ist die
> Debugschlacht (60 FPS → 12 FPS bei Kampfbeginn, ohne Zauber).

## Kontext (Nutzertest nach Phase-8-Rückabwicklung, 2026-07-12)

Wegpunkt-/Befehls-Bug tritt nicht mehr auf (Rollback bestätigt); FPS erwartbar
niedriger. Zwei neue Beobachtungen:

1. **Bergpass-KI buggt sich fest:** Krieger laufen unten am Bergsockel gegen
   den Riegel (kommen oben nie an); die KI versucht, Gebäude auf
   unerreichbaren Gebieten zu bauen (oben auf den Bergen — begehbar, aber
   isoliert).
2. **Debugschlacht/Nahkampf:** Sobald der Kampf losgeht, schieben sich die
   Einheiten als ein großer Ball **nach Norden**; es wird deutlich weniger
   gekämpft als möglich — die meisten stehen rum oder verfolgen nur, obwohl
   sich genug Prügelpaare (2-3 gegen 1) finden könnten.

**Ziel-Design (Nutzer-Vorgabe 2026-07-12, wie im Original-Populous):** Im
Nahkampf bilden sich **Kampfgruppen**, jede Gruppe ist immer **1 gegen N**
(N = 1–3) — nie „Team gegen Team". Die Regeln im Einzelnen:

1. **Normalfall 1 gegen 1:** Treffen zwei Seiten aufeinander, teilen sich die
   Nahkämpfer in 1-gegen-1-Paare auf.
2. **Überzahl verteilt sich:** Bleiben auf einer Seite Leute übrig (oder ist
   die Überzahl im Vorhinein berechenbar), verteilen sie sich auf die
   bestehenden Kämpfe — bis zu **3 gegen 1** (Vierergruppe: 1 Verteidiger +
   3 Angreifer).
3. **Zweite Reihe:** Sind danach noch mehr übrig, stellen sie sich bei
   einigen der Viererkämpfe in die **zweite Reihe** (Warte-Ring) und warten
   auf einen freien Slot.
4. **Nachzügler der unterlegenen Seite ziehen Kämpfer ab:** Kommen neue
   Einheiten der unterlegenen Seite an, holen sie sich Gegner aus bestehenden
   Gruppen heraus — aus 1-gegen-3 wird z. B. **1-gegen-2 + 1-gegen-1**.
5. **Wartende füllen Slots jederzeit auf** (Angreifer stirbt / Ziel tot /
   Kämpfer abgezogen → nächster aus der zweiten Reihe rückt nach).
6. **Verboten: „Team-Kämpfe".** 2 gegen 2 oder 2 gegen 4 gibt es nicht —
   es wird immer in 1-gegen-N-Gruppen aufgeteilt: 2v2 → 1v1 + 1v1;
   2v4 → 1v2 + 1v2.

Die Gruppen halten **etwas Abstand zueinander** (klein, aber nicht 0),
sodass der Kampf nicht ein einziger Einheiten-Blob ist („Ballbildung" in der
Debugschlacht ist ausdrücklich Teil des Problems).

## Befund-Hypothesen (im Diagnose-Schritt zu verifizieren)

- **„Viele stehen rum" + „Ball schiebt nach Norden" haben vermutlich dieselbe
  Wurzel im Gegner-Scan** (`Unit._scan_for_enemy` →
  `UnitManager.get_units_in_radius(pos, radius, SCAN_MAX_CANDIDATES = 24)`):
  1. Der Kandidaten-Cap zählt **alle** Einheiten im Radius (auch Freunde) —
     mitten im eigenen Blob sind die ersten 24 fast nur Freunde → der Scan
     findet keinen Gegner → Einheit läuft weiter/verfolgt statt zu kämpfen.
  2. Die Hash-Buckets werden deterministisch von min→max iteriert (kz/kx
     aufsteigend = **Nordwest zuerst**) → bei gecapptem Scan werden Ziele
     systematisch im Norden/Westen gefunden → kollektiver Nord-Drift.
- **Bergpass-Krieger am Sockel:** Attack-Move-Ziele/Formations-Offsets, die
  in den unbegehbaren Riegel fallen, werden von
  `NavGrid.find_path`/`nearest_walkable_cell` auf die räumlich nächste
  begehbare Zelle gesnappt — das kann eine **Sockelzelle direkt an der Wand**
  (erreichbar → sie laufen hin und drängeln dort) oder eine **Plateauzelle
  oben** (unerreichbar → Pfad leer → IDLE) sein; die KI re-issued den
  Angriffsbefehl alle 4 Ticks (`ATTACK_ORDER_TICKS`) → dauerhaftes Anlaufen.
- **KI baut auf Plateaus:** `AIController._find_supplied_plot` prüft über
  `can_place_at` nur Walkability/Ebenheit/Bäume — **nicht die Erreichbarkeit
  von der Basis**. Riegel-Oberseiten sind begehbar+flach → gültige Plots;
  Arbeiter kommen nie an, die Baustelle blockiert `MAX_PARALLEL_SITES` →
  KI-Aufbau stockt.

## Deliverables / Umsetzungsschritte

### 1. Diagnose-Schritt (vor den Fixes, Befunde in PROGRESS festhalten)

- Debugschlacht headless nachstellen (zwei Armeen, Kontakt) und messen:
  Anteil Einheiten in echtem Nahkampf (`_in_melee`) vs. ATTACK-ohne-Slot vs.
  MOVE; Schwerpunkt-Drift der Gesamtmasse über die Zeit (Nord-Bias-Nachweis).
- Bergpass-Repro: festhängende Krieger untersuchen (State, `attack_target`,
  Zielzelle, Pfadstatus) — Hypothesen oben bestätigen/korrigieren.

### 2. Kampfgruppen-System (Original-Stil) — Kern-Deliverable

Vorbild ist das bestehende Idle-Gruppen-System
(`UnitManager.IdleGroup`, `_join_or_found_group`, sticky membership):

- **`CombatGroup`** (RefCounted, im UnitManager verwaltet): genau **ein
  Verteidiger** + 1–3 Nahkampf-Angreifer (ersetzt/übernimmt die bisherige
  `melee_attackers`-Slot-Logik am Ziel) + **Warteliste** (zweite Reihe)
  drumherum. Gruppen-Anker = Kampfort (folgt dem Ziel träge). Invariante:
  Gruppen sind IMMER 1-gegen-N — eine Einheit ist Mitglied höchstens EINER
  Gruppe, entweder als Verteidiger oder als Angreifer/Wartender.
- **Aufteilung & Rebalancing (Paarungsregeln oben):** Beim Aufeinandertreffen
  zuerst 1v1-Paare bilden; Überzahl füllt bestehende Gruppen auf max. 3
  Angreifer auf, weitere in die zweite Reihe. Kommt eine neue Einheit der
  unterlegenen Seite an, **zieht sie einen Angreifer aus der vollsten Gruppe
  ab** und eröffnet mit ihm ein neues 1v1 (1v3 → 1v2 + 1v1); frei werdende
  Slots füllt die zweite Reihe jederzeit nach. 2v2/2v4 dürfen nie entstehen
  (Invariante oben erzwingt das strukturell: der „Verteidiger"-Platz einer
  Gruppe ist einfach besetzt).
- **Gruppenabstand:** Neue Kämpfe entstehen nur an Ankern mit Mindestabstand
  zu bestehenden Gruppen (klein, aber > 0 — Startwert ~2,5–3 m, tunebar).
  Wer ein Ziel angreifen will, dessen Gruppe voll ist, wird **Wartender** am
  Ring der Gruppe (fester Slot mit Abstand, wie `_wait_near`, aber am
  GRUPPEN-Anker statt am Ziel klebend); Wartende rücken nach, wenn ein
  Slot frei wird (Angreifer stirbt/Ziel tot → nächster aus der Warteliste,
  sonst nächstliegende Gruppe mit freiem Slot / neues Ziel im Abstandsraster).
- **Separation/Blob:** Gruppen sind separationsstabil (Mitglieder um den
  Anker wie bei Idle-Gruppen); zwischen Gruppen wirkt der Mindestabstand —
  der Kampf franst sichtbar in Grüppchen aus statt in einen Ball.
- **Scan-Fixes (Wurzelbehandlung):**
  - Kandidaten-Cap zählt nur noch **Gegner-Kandidaten** (Freunde im Radius
    verbrauchen das Budget nicht mehr) — Blob-Blindheit weg.
  - Richtungs-Bias entfernen: Kandidaten über die Bucket-Range einsammeln und
    nach Distanz/Score wählen statt „first-N in NW-Reihenfolge" (bzw.
    Bucket-Besuchsreihenfolge um die eigene Zelle zentrieren).
  - Zielwahl bevorzugt Gegner mit freiem Gruppen-Slot in Reichweite
    (heutiger `incoming_attackers`-Score wird zum Gruppen-Slot-Score).
- Bestehende Regeln bleiben: Fernkämpfer unterliegen keinem 3er-Cap
  (`_is_ranged`), Prediger-/SIT-Sonderfälle, Gebäude niedrigste Priorität,
  Flee-/Retaliate-Regeln.

### 3. Bergpass-/Erreichbarkeits-Fixes

- **KI-Plot-Suche:** Nach bestandenem `can_place_at` einen
  Erreichbarkeits-Check von der Basis (`nav_grid.find_path(anchor →
  Plot-Eingang)` einmal pro gewähltem Kandidaten; unerreichbare Kandidaten in
  einen kleinen Session-Cache, damit der teure Fehlschlag nicht wiederholt
  wird). Gleiches Gate für `_send_escort_if_remote`.
- **Angriffs-/Formationsziele validieren:** Fällt ein (Formations-)Zielpunkt
  in unbegehbares Gebiet, wird er nicht mehr blind auf die räumlich nächste
  begehbare Zelle gesnappt, sondern auf eine **vom Ausgangspunkt erreichbare**
  Zelle nahe dem Pfadende geclampt (Pfad leer → Wellenziel für diese Einheit
  = letzter erreichbarer Punkt Richtung Ziel statt Dauer-Anlauf); die
  KI-Wellen-Reissue-Logik darf festhängende Einheiten nicht alle 4 s erneut
  gegen die Wand schicken (Reissue nur bei erreichbarem Ziel).

### 4. Kampf-Performance (Nutzer-Vorgabe 2026-07-12)

**Benchmark ist die Debugschlacht** (2×800, keine Zauber). Ist-Zustand auf
einem guten Rechner: **60 FPS vor Kontakt → 12 FPS**, sobald Nah- und
Fernkampf losgehen. Headless-Anhaltspunkt (`benchmark_mass`, combat 2000):
`units`-Phase ~37 ms/Tick — der Kampfcode selbst ist der Treiber, nicht
Separation/Hash.

- **Erst profilieren, dann optimieren:** Kampf-Tick aufschlüsseln
  (Gegner-Scan `_scan_for_enemy`, Angriffs-Replan/`ATTACK_ORDER_TICKS`-Reissues,
  Slot-/Wartelogik, Fernkampf-Zielsuche, Projektile) — Befunde in PROGRESS.
- Naheliegende Kandidaten (per Messung bestätigen): Scan-/Replan-Frequenz im
  Kampf (Kämpfer MIT Gruppe/Slot brauchen keinen Voll-Scan pro Tick — die
  Gruppe IST die Zielbindung; Scans nur für Ungebundene/Wartende, gestaffelt),
  redundante Pfad-Neuplanungen auf Nahdistanz, Fernkämpfer-Zielsuche cachen.
  Das Kampfgruppen-Modell aus Deliverable 2 ist selbst der größte Hebel:
  gebundene Kämpfer sind billig.
- **Ziel:** Debugschlacht nach Kontakt deutlich über 12 FPS (Messwert vorher/
  nachher dokumentieren); Verhalten unverändert korrekt (Suite + Wächter).
- **Nutzer-Randbedingungen bleiben:** 30-Hz-Sim, keine Genauigkeits-Tricks,
  jede Optimierung einzeln + Langzeittest (siehe PROGRESS „Rückabwicklung
  Phase 8" und 8.1 Stufe B).

## Tests

- Bestehende Suite bleibt grün (Kampf-/Slot-Tests werden auf das
  Gruppen-Modell angepasst, Semantik 1-gegen-N mit N ≤ 3 bleibt).
- **Neu (headless):**
  - Gruppenbildung: 6 Angreifer auf 1 Ziel → 3 kämpfen, 3 warten am Ring;
    Slot wird frei → Wartender rückt nach.
  - Paarungsregeln: 2v2 → zwei getrennte 1v1 (nie ein 2v2-Knäuel);
    2v4 → 1v2 + 1v2; Nachzügler der unterlegenen Seite zieht einen Angreifer
    aus einer 1v3-Gruppe ab → 1v2 + 1v1.
  - Performance-Wächter: combat-Benchmark (2000) — `units`-Phase nach dem
    Umbau messbar unter dem Ist-Wert (~37 ms/Tick), Zahlen in PROGRESS.
  - Gruppenabstand: zwei benachbarte Kämpfe entstehen mit Anker-Abstand ≥
    Mindestabstand; kein Voll-Overlap der Gruppen.
  - Blob-/Bias-Wächter: symmetrische Armeen (N vs. S gespiegelt) → der
    Massen-Schwerpunkt driftet über X Ticks nicht systematisch (Toleranz);
    Kampfquote: nach Kontakt ist ein Mindestanteil der Nahkämpfer `_in_melee`
    (Wächter gegen „alle stehen rum").
  - Scan findet Gegner auch mitten im Freundes-Blob (Cap-Fix-Test).
  - KI-Plot: Kandidat auf isoliertem Plateau wird verworfen, erreichbarer
    Plot gewählt; Bergpass-KI-Langzeitlauf (2500+ Frames) baut weiter und
    hängt nicht.
  - Zielpunkt im Riegel: Einheit erhält erreichbares Ersatzziel und pendelt
    nicht (kein Dauer-MOVE gegen die Wand über X s — Wächter analog zur
    Wegfindungs-Regression).

## Manuelle Prüfung (Nutzer)

- Debugschlacht: Kampf zerfällt in 1-gegen-N-Grüppchen (+ zweite Reihe) mit
  kleinem Abstand; keine Ballbildung, kein Nord-Schub; sichtbar mehr aktive
  Kämpfe; keine 2v2-/2v4-Knäuel.
- Bergpass-Skirmish (3 KIs, lang): keine Krieger-Trauben am Bergsockel, KI
  baut ihre Basis kontinuierlich aus, keine Baustellen auf Plateaus.
- **FPS in der Debugschlacht:** Referenz 60 FPS vor Kontakt → bisher 12 FPS
  im Kampf; nach dieser Phase spürbar besser (Zielrichtung, kein hartes
  Soll — Messwerte notieren).

## Definition of Done

- [ ] Diagnose-Befunde dokumentiert (PROGRESS), Hypothesen bestätigt/korrigiert
- [ ] Kampfgruppen: 1-gegen-N-Paarungsregeln (1v1-Aufteilung, Überzahl bis
      1v3, zweite Reihe, Abziehen durch Nachzügler, kein 2v2/2v4) +
      Gruppen-Mindestabstand umgesetzt
- [ ] Scan-Fixes: kein Freundes-Cap-Blindflug, kein Richtungs-Bias
- [ ] Kampf-Performance: Profiling-Befunde + Optimierung, combat-Benchmark
      messbar besser (Ist: units ~37 ms/Tick bei 2000; Debugschlacht-FPS
      vorher/nachher dokumentiert)
- [ ] KI baut nicht mehr auf unerreichbaren Plots; keine Sockel-Trauben mehr
- [ ] Suite grün inkl. neuer Wächter, Ladecheck + lagtest fehlerfrei
- [ ] PROGRESS.md ergänzt, Checkbox in [00_overview.md](00_overview.md) abgehakt,
      Commit + Push
