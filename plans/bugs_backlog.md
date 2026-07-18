# Bug-Backlog — offene Fehler für spätere Behebung

> Gesammelt am 2026-07-13 (Nutzertest nach Phase 8.2). Behebung geplant als eigener
> Bugfix-Pass **vor oder zu Beginn von Phase 9**. Pro Bug: Symptom, Soll-Verhalten,
> bekannte Code-Ansatzpunkte. Nach Behebung: Checkbox abhaken, Eintrag ggf. um
> Ursache/Fix ergänzen (Erkenntnisse zusätzlich in PROGRESS.md).

## Bug 1 — UI-Skalierung / Auflösung

- [ ] **Status: offen**

**Symptom:** UI ist ungünstig skaliert. Bei 1080p ist z. B. im Werkstatt-Panel unten
die Katapult-Anzahl abgeschnitten und die Arbeiterplätze sind nicht alle sichtbar.

**Soll:**
- Zielauflösungen sind **1920×1080 und 2560×1440** — dort müssen alle UI-Elemente
  vollständig sichtbar und gut lesbar sein.
- **Neuer Optionspunkt „Auflösung"** im Optionsmenü (Auswahl der Fensterauflösung,
  mind. 1080p und 1440p).

**Ansatzpunkte:**
- `project.godot`: aktuell `window/size/viewport_width=1280`, `viewport_height=800`,
  kein Stretch-Mode konfiguriert → Basisauflösung/Stretch-Strategie festlegen
  (z. B. `canvas_items` + `aspect=expand`), damit das UI bei 1080p/1440p konsistent skaliert.
- Werkstatt-/Gebäudepanel: `scripts/ui/selection_manager.gd`, `scripts/ui/sidebar.gd`
  (Katapult-Anzahl, Arbeiterplätze) — feste Pixelmaße/Offsets prüfen, Panel darf bei
  Zielauflösungen nicht abschneiden.
- Optionsmenü (bestehende Optionen, z. B. FPS-Anzeige) um Auflösungs-Auswahl erweitern;
  Einstellung persistieren wie die vorhandenen Optionen.

## Bug 2 — Unfertige Gebäude durch Einheiten nicht zerstörbar

- [ ] **Status: offen**

**Symptom:** Nicht fertig errichtete Gebäude (Baustellen) können von Einheiten
angegriffen werden, werden aber nie zerstört — nur Katapulte (und Zauber, siehe
`apply_destruction_stages`) können Baustellen vernichten.

**Soll:**
- Einheiten können halb fertige Gebäude **auch zerstören**.
- Unfertige Gebäude haben **Lebenspunkte auf Grundlage des bisher verbauten Holzes**:
  maximal **3 Stufen** (weil noch nicht fertig) — fertige Gebäude haben 4 Stufen.
  D. h. HP skalieren mit `wood_delivered / wood_cost`, gedeckelt bei 3/4 der
  Voll-HP.

**Ansatzpunkte:**
- `scripts/buildings/building.gd`: `take_damage()` / `under_construction` /
  `apply_destruction_stages()` (Baustellen werden dort bei Zauber-Stufenschaden sofort
  eingeebnet, Zeile ~326). Prüfen, warum Einheiten-Angriffe (Sturmangriff/Fernkampf aus
  Phase 7g) Baustellen nicht töten — vermutlich sind HP der Baustelle von Anfang an auf
  `max_health` bzw. der Sturm-/Zerstörungspfad ist auf fertige Gebäude beschränkt.
- HP-Modell für Baustellen einführen: aktuelle HP an Baufortschritt/verbautes Holz
  koppeln; bei 0 HP Baustelle zerstören (versinkt, Bauplatz wieder frei — wie Stufe 4).
- Phase-7g-Logik (Sturmangriff, Insassen-Auswurf) gegen Baustellen absichern
  (Baustellen haben keine Insassen/Raiders).

## ~~Bug 3 — Reparatur von Gebäuden~~ (gestrichen)

**Gestrichen 2026-07-13:** Reparatur ist bereits implementiert und funktioniert
(Nutzer bestätigt) — `TribeCommands.order_repair()`, `Brave.order_repair()`,
`Building.repair()` mit `floor(Schadensanteil × Holzkosten)` gemäß CLAUDE.md §5.
Kein Handlungsbedarf.

## Bug 4 — Holzsuche: Priorisierung nach Luftlinie führt zu Umwegen

- [ ] **Status: offen**

**Symptom:** Braves machen große Umwege, um Bäume zu fällen, die z. B. mitten an einer
Klippe wachsen (Arbeiter muss erst eine Rampe hinunter), obwohl näher erreichbare Bäume
auf der gleichen Ebene stehen.

**Ursache (verifiziert):** `TreeManager._nearest()`
(`scripts/core/tree_manager.gd:199`) wählt Bäume rein nach **XZ-Luftlinie**
(`distance_squared_to`), ohne Erreichbarkeit/Laufweg zu berücksichtigen. Genutzt von
`claim_nearest_tree()` (Brave-Holzsuche, `scripts/units/brave.gd:804`) und
`nearest_tree()` (KI).

**Soll:**
- Bäume auf der **gleichen Ebene** bevorzugen — nicht bloße Luftlinie.
- Vermutlich reicht bereits der Vergleich der **tatsächlichen Laufweg-Länge**
  (NavGrid-Pfadkosten) statt Luftlinie. Priorisierung insgesamt prüfen.

**Ansatzpunkte:**
- Kandidaten weiterhin per Luftlinie vorfiltern (Top-N), dann per
  `NavGrid.find_path()`-Länge (oder einer billigeren Erreichbarkeits-/Höhenheuristik,
  z. B. Höhendifferenz-Malus) nachsortieren — **Achtung Performance:** keine
  Pfadberechnung pro Baum pro Scan für hunderte Braves; ggf. Path-Worker (Phase 8.1)
  nutzen oder Ergebnis cachen.
- Betroffene Stellen: `tree_manager.gd` (`_nearest`, `claim_nearest_tree`,
  `nearest_tree`), Aufrufer `brave.gd` (CHOP_CHAIN_RADIUS-Suche) und
  `ai_controller.gd:884`.

## ~~Bug 5 — Katapult & Feuermechanik (Lava, Brennen, Raider-Beschuss)~~ (behoben)

- [x] **Status: behoben 2026-07-18** (gemeldet und gefixt am selben Tag)

Vier zusammenhängende Bugs, alle behoben:

1. **Katapult-Treffer auf Gebäude erzeugte keine Lavapfütze** — Einheiten am Einschlag
   brannten nicht. Fix: `SiegeShot._impact()` spawnt die Pfütze jetzt IMMER; bei
   Gebäudetreffern mit `damage_buildings = false` (das Projektil hat den Gebäudeschaden
   schon gemacht, die Pfütze beschädigt dann keine Gebäude mehr).
2. **Lava beschädigte Gebäude nicht.** Fix: `Building.add_lava_contact()` — 1
   Zerstörungsstufe je volle 5 s Lavakontakt (`Balance.LAVA_BUILDING_STAGE_TIME`),
   Zähler-Reset nach 1 s ohne Kontakt (`LAVA_BUILDING_CONTACT_GRACE`, nur DAUERHAFTER
   Kontakt zählt). `LavaSurge`/`LavaFlow` melden Kontakt im 0,2-s-Takt. Der pauschale
   `VolcanoZone._wreck_buildings()`-Schaden (alle 4 s, Radius 5) wurde ERSETZT —
   Vulkan-Gebäudeschaden kommt jetzt nur noch aus echtem Lavakontakt der Wellen
   (Reichweite 7,5).
3. **Einheiten brannten am Vulkan nicht zuverlässig** (Zündlücke zwischen den
   Eruptionswellen: molten-Fenster ~3,7 s je Welle, Intervall 4,5 s). Fix: die
   `VolcanoZone` zündet während der Eruptionsphase selbst kontinuierlich (alle 0,2 s)
   alle Einheiten im Lavabereich.
4. **Katapult gegen eigenes Gebäude mit Raidern war nutzlos** (eigene Gebäude waren für
   Befehl und Einschlag komplett gesperrt). Fix: eigenes Gebäude MIT Raidern ist gültiges
   Ziel (`SiegeEngine.order_attack_building`, `SiegeShot._building_at_impact`,
   `SelectionManager._dispatch_own_raided_building`); Treffer ruft
   `Building.blast_raiders()` — Raider fliegen mit 30 Schaden
   (`Balance.SIEGE_SHOT_RAIDER_DAMAGE`) und Roll-Effekt raus, können danach wieder rein
   oder das Katapult angreifen — und das eigene Gebäude nimmt 1 Stufe pro Treffer.
   Eigene Gebäude OHNE Raider bleiben unantastbar (Frust-Schutz).

Tests: `test_siege.gd` (+4 Tests) und `test_spells.gd` (Kadenz-Test umgeschrieben,
+3 Tests) decken alle vier Fälle ab.
