# Populous — The End: Spielmechaniken

> **Werte-Quelle:** `scripts/core/balance.gd` (zentrale Balance-Datei) — bei
> Balance-Änderungen dieses Dokument mitziehen. Ergänzende Quellen:
> `scripts/units/unit.gd` (Zustände, Nahkampf), `scripts/buildings/building.gd`
> (Zerstörungsstufen).
>
> **Referenz-Einheiten:** 1 Brave-Leben = **60 HP**. Zeiten in Sekunden,
> Reichweiten/Distanzen in Metern (1 Zelle = 1 m), Schaden in HP.

---

## 1. Wirtschaft & Stamm

### Holz
**Holz ist die einzige physische Ressource.** Es stammt von wilden (oder vom
Förster gepflanzten) Bäumen und wird für Bau, Reparatur und Katapulte benötigt.
Holz wird nicht abstrakt abgebucht, sondern **physisch geliefert**: Braves
fällen Bäume bzw. holen Holzstapel ab und tragen das Holz zur Baustelle
(Tragekapazität: 3 Holz je Brave).

- **Baumwachstum:** 5 Wachstumsstufen (0–4), im Mittel **75 s** pro Stufe
  (real ±50 % gestreut).
- **Holzertrag je Stufe:** 0 / 1 / 2 / 3 / 4 Holz (Stufe 0–4) — ausgewachsene
  Bäume lohnen sich am meisten.

### Mana
Mana lädt **passiv** und skaliert mit der eigenen Bevölkerung:

> **Mana/s = 0,1 × Bevölkerung + 0,3 × Anzahl betender Braves**

Betende Braves (am Reinkarnationsplatz) sind also je 4× so viel wert wie ein
normales Stammesmitglied, tun aber sonst nichts. Mana wird automatisch in
**Zauber-Ladungen** umgewandelt (siehe §7). Der Förster **verbraucht** Mana
als Arbeiter-Unterhalt (siehe §4).

### Bevölkerung & Limits
- **Hardcap: 1000 Einheiten pro Stamm** (zusätzlich zum Bevölkerungslimit der
  Hütten; jede Hütte bietet Platz für 40).
- **Hütten-Besatzung:** Eine Hütte produziert nur **mit Besatzung** (bis zu
  4 Braves, im Gebäude versteckt; sie zählen zur Bevölkerung, erzeugen aber
  **kein** Mana). Bei voller Besatzung entsteht alle **10 s** ein neuer Brave,
  volle Hütten arbeiten ~10 % schneller als die alte Basisrate; weniger
  Besatzung = proportional langsamer, leere Hütte = keine Produktion.
- **Wachstumsregler** (pro Stamm, UI bei Bevölkerung/Mana): **Kein** (leert
  alle Hütten), **Minimal** (1 Besatzung je Hütte), **Maximum** (füllt auf 4).
  Automatisch eingezogen werden nur **nahe, untätige** Braves.

---

## 2. Einheiten

| Einheit | HP | Tempo | Kampfwerte | Besonderheiten |
|---|---|---|---|---|
| **Brave** | 60 | 4,0 m/s | Nahkampf ×1,0 | Arbeiter: baut, sammelt Holz, betet, bemannt Hütten/Förster/Werkstatt. Wehrt sich nur, greift nicht selbst an (Idle-Aggro nur 3 m „Dorfwache"). |
| **Krieger** | 120 | 4,0 m/s | Nahkampf ×3,0 | Stärkster Nahkämpfer; schubst fast nie (4 % statt 15 %), schlägt lieber zu. Aggro-Radius 8 m. |
| **Feuerkrieger** | 60 | 4,0 m/s | Feuerball: 9 HP (Einheiten) / 5 HP (Gebäude), Reichweite 8 m, alle 1,5 s | Fernkämpfer; großer Aggro-Radius (13 m). Kann Wachtürme bemannen (+3 m Reichweite). |
| **Prediger** | 90 | 4,0 m/s | konvertiert statt zu kämpfen | **Bekehrt** Feinde (Reichweite 5 m, Dauer zufällig 4–9 s). Mehrere Prediger verteilen sich auf verschiedene Ziele; Einheiten **in Bekehrung sind kein gültiges Ziel** für Nah-/Fernkampf (Katapult ausgenommen). |
| **Schamanin** | 240 (4× Brave) | 4,0 m/s | Nahkampf ×2,0; einzige Zauberwirkerin (Wind-up 0,6 s) | Genau eine pro Stamm. Stirbt sie, **respawnt** sie nach **20 s** am Reinkarnationsplatz; der Stamm des Tötenden erhält einmalig **15 %** seiner Ladungskapazität als Manaboost. |
| **Katapult** | — (nicht direkt angreifbar) | 2,0 m/s | Schuss: Reichweite 3–15 m; Einschlag 15 HP im 2-m-Radius (**Friendly Fire!**); Gebäude +1 Zerstörungsstufe; Raider im eigenen Gebäude: 30 HP + Rauswurf | Fahrzeug mit Crew (bis 6): Schuss-Cooldown 6 s bei 2 Crew → 3 s bei voller Crew. Bekämpft wird die **Crew**, nicht das Fahrzeug; ein unbemanntes Katapult kann jeder Stamm übernehmen. |

---

## 3. Einheiten-Zustände (State-Machine)

Enum `Unit.State` in `scripts/units/unit.gd`:

| Zustand | Bedeutung |
|---|---|
| `IDLE` | Untätig; Kampfeinheiten greifen Feinde im Aggro-Radius selbstständig an. |
| `MOVE` | Läuft einen NavGrid-Pfad ab (auch Wegpunkt-Routen/Patrouillen und Attack-Move). |
| `GATHER` | Brave fällt einen Baum bzw. holt Holz (loses Hacken per Rechtsklick auf Baum). |
| `PRAY` | Brave betet am Reinkarnationsplatz (Mana-Bonus für den Stamm). |
| `BUILD` | Brave arbeitet an einer Baustelle/Reparatur (mit Sub-Tasks, s. u.). |
| `ATTACK` | Kämpft im Nahkampf/Fernkampf gegen ein Einheitenziel. |
| `TRAIN` | In einem Trainingsgebäude; kommt als Kampfeinheit wieder heraus. |
| `PANIC` | Flieht kopflos vor der Panikquelle; nicht steuerbar (Details §6 Statuseffekte). |
| `CAST` | Schamanin wirkt einen Zauber (Wind-up, dann Release). |
| `THROWN` | Durch die Luft geschleudert (Feuerball, Tornado) — Wurfparabel bis zur Landung. |
| `DEAD` | Tot; Leiche liegt 6 s und versinkt dann im Boden (1 s Animation). |
| `SIT` | Von einem feindlichen Prediger fixiert (Bekehrung läuft). |
| `ROLL` | Rollt/purzelt bis zum Ausrollen; nicht steuerbar, Rollschaden über Zeit (Details §6 Statuseffekte). |
| `FORESTER` | Beim Förster einquartiert bzw. kurz draußen einen Setzling pflanzend. |
| `CREW` | Bemannt ein Katapult (läuft an dessen Seitenslot mit, wehrt sich bei Angriff). |
| `RAID` | Nahkampf-Abreißer **im Inneren** eines feindlichen Gebäudes; steigt lebend aus, wenn es einstürzt. |
| `GARRISON` | Auf dem Weg in einen / stationiert in einem eigenen Wachturm (geschützte Reserve). |

**Brave-Sub-Tasks** (`Brave.Task`): `FLATTEN` (Fundamentzelle einebnen), `CHOP`
(Baum fällen), `PICKUP` (Holzstapel holen), `DELIVER` (Holz zur Baustelle
tragen), `CONSTRUCT` (bauen), `REPAIR` (reparieren), `PRODUCE` (Werkstatt).
Der Förster-Job hat eigene Phasen (einziehen → Pflanzstelle → knien → zurück).

---

## 4. Gebäude

Der Eingang liegt stets auf der Südseite; beim Platzieren kann gedreht werden
(Taste R). Baukosten werden als Holz physisch angeliefert.

| Gebäude | Footprint | Holz | HP | Funktion |
|---|---|---|---|---|
| **Hütte** | 4×4 | 12 | 300 | +40 Bevölkerungsplatz; spawnt Braves (10 s bei voller Besatzung von 4; leer = nichts). |
| **Kaserne** | 5×5 | 10 | 400 | Bildet Braves in **3 s** zu **Kriegern** aus. |
| **Tempel** | 6×6 | 15 | 440 | Bildet Braves in **5 s** zu **Predigern** aus. |
| **Feuertempel** | 8×8 | 20 | 600 | Bildet Braves in **4 s** zu **Feuerkriegern** aus. |
| **Förster** | 5×2 | 18 | 250 | Bis 4 Arbeiter pflanzen Setzlinge (60 Arbeiter-Sekunden je Baum → 4 Arbeiter = alle 15 s einer). **Unterhalt: 1,5 Mana/s je aktivem Arbeiter** — reicht das Mana nicht, pausieren Arbeiter. |
| **Werkstatt** | 8×4 | 15 | 350 | Baut **Katapulte**: 60 Arbeiter-Sekunden (3 Arbeiter → 20 s) + 5 Holz je Stück. |
| **Wachturm** | 2×2 | 4 | 200 | 2 Plätze für Kampfeinheiten/Schamanin (keine Braves); stationierte Fernkämpfer/Prediger erhalten **+3 m Reichweite**. Klein: max. 5 gleichzeitige Abreißer statt 15. |
| **Reinkarnationsplatz** | 3×3 | — | 500 | Respawn-Ort der Schamanin; Braves beten hier (Mana-Bonus). Kann **nicht von Einheiten gestürmt** werden (nur Beschuss/Zauber). |

**Ausbildung:** Brave per Rechtsklick ins Trainingsgebäude schicken → nach der
Trainingszeit kommt die Kampfeinheit heraus und läuft zum **Rally Point**.
Rally Points sind für alle Gebäude per Rechtsklick setzbar (bei Selektion
mehrerer Gebäude für alle gleichzeitig).

---

## 5. Gebäudeschaden & Zerstörungsstufen

Gebäude haben **4 Zerstörungsstufen** (`Building.destruction_stage()`), je
**30 % Schadensanteil** eine Stufe:

| Stufe | Schaden | Zustand |
|---|---|---|
| 0 | < 30 % | Intakt, voll nutzbar. |
| 1–3 | ≥ 30 / 60 / 90 % | **Nicht nutzbar** (keinerlei Produktion), per Rechtsklick durch Arbeiter **reparierbar**. Visuell brechen zunehmend Stücke aus dem Modell. |
| 4 | 100 % | Zerstört: das Gebäude **versinkt im Boden**, der Bauplatz ist wieder frei betret- und bebaubar. |

- **Reparaturkosten:** Holz proportional zum reparierten Schaden —
  `floor(Schadensanteil × Holzkosten)` (z. B. 90 % Schaden an der Hütte →
  10 Holz).
- **Stufen-Treffer:** Blitz +2 Stufen, Erdbeben +2, Katapultkugel +1, Tornado
  +1 alle 2 s, Lavakontakt +1 je 5 volle Kontaktsekunden. **Baustellen sind
  fragil:** jeder Stufen-Treffer zerstört sie sofort.
- **Sturmangriff (Raid):** Nahkämpfer dringen ins Gebäude ein und reißen es von
  innen ab — **6 HP/s je Raider**, max. **15** gleichzeitig (Wachturm: 5).
  Katapultbeschuss auf das **eigene** geraidete Gebäude wirft Raider lebend
  hinaus (30 HP Schaden je Treffer, kostet das eigene Gebäude 1 Stufe).
- **Insassen bei Beschuss:** Schaltet **Fernkampf** (Feuerkrieger, Katapult)
  ein besetztes Gebäude aus, sterben die Insassen **sichtbar an der Tür**
  (Leichen am Eingang). **Zauber und Nahkampf-Sturm** werfen sie dagegen
  **lebend** hinaus (kurzer Roller vom Gebäude weg).

---

## 6. Schadenssystem

**Es gibt keine Rüstung und keine Schadensmultiplikatoren am Ziel** — jeder
Schaden wird flach von den HP abgezogen. Variation entsteht auf Angreiferseite:

- **Nahkampf:** Jeder Schlag ist zufällig einer von drei Typen —
  **Punch 6 HP** (65 %), **Kick 8 HP** (20 %), **Schubser 3 HP** (15 %; wirft
  das Ziel kurz ins Rollen). Der Basiswert wird mit der `melee_strength` der
  Einheit multipliziert: Brave ×1, Schamanin ×2, Krieger ×3 (Krieger schubsen
  nur zu 4 %). Angriffs-Cooldown: **0,8 s** zwischen zwei Schlägen.
- **Kampfgruppen:** Maximal **3 Nahkampf-Angreifer** gleichzeitig pro Ziel;
  weitere warten in zweiter Reihe und rücken nach.
- **Regeneration:** **8 s** nach dem letzten Kampfkontakt heilen Einheiten mit
  **2 HP/s** selbst.
- **Klippensturz:** Wer über eine Kante (≥ 1,6 m Höhendifferenz) gestoßen wird
  oder rollt, stürzt: **6 HP je Meter Fallhöhe**, gedeckelt auf 30 HP
  (½ Brave-Leben), danach Rollen (Dauer wächst mit der Fallhöhe, max. 3 s).
  Sturz **ins Wasser = Sofort-Tod**.

### Statuseffekte

Alle vier Effekte machen die Einheit **unsteuerbar** (sie nimmt keine Befehle
an, bis der Effekt endet). Panik und Rollen brechen den laufenden Kampf ab und
**löschen die Wegpunkt-Route** — die Einheit steht danach untätig (`IDLE`) da
und braucht neue Befehle. Auch eine laufende Bekehrung durch einen Prediger
wird zurückgesetzt. Angreifbar bleibt die Einheit währenddessen normal.

**Panik** — Auslöser: Insektenschwarm (6 s) und Brand (für die Brenndauer).
- Die Einheit flieht in kurzen, zufällig wechselnden Richtungshüpfern **von der
  Panikquelle weg** (kopfloses Rennen, keine Wegfindung); sie kämpft nicht und
  wehrt sich nicht.
- Erneute Panik **verlängert** den Timer (kein Stapeln).
- Die **Schamanin ist immun** — sie brennt z. B. stehend weiter und bleibt
  steuerbar. Geschleuderte/rollende Einheiten beenden erst ihren Sturz/Roller,
  Panik greift dann nicht mehr rückwirkend.

**Rollen** — Auslöser: Schubser im Nahkampf (25 % Umwerf-Chance), Landung nach
Feuerball-/Tornado-Schleudern, Blitz (angrenzende Einheiten), Klippensturz,
sowie von selbst beim Hinablaufen sehr steiler Hänge (Stolpern).
- Rollt mit **5,5 m/s** (Hangneigung addiert Tempo) und folgt an Hängen der
  Falllinie, bis der Boden flach genug ist; Wurf-Landungen rollen mit ihrem
  Schwung weiter, der über Reibung abklingt. Auf flachem Boden endet ein
  Mini-Roller nach ~0,35 s.
- **Rollschaden: 5 HP/s.** Tödlicher Schaden wird bis zum Ende des Rollers
  **aufgeschoben** — die Einheit stirbt erst beim Ausrollen, nicht mittendrin.
- Rollen **ins Wasser = Sofort-Tod**; Gebäude stoppen den Roller; rollt die
  Einheit über eine Klippenkante, geht der Roller in einen **Sturz** über
  (Fallschaden, §oben). Harte Sicherheitsgrenze: 30 s, danach endet jeder
  Roller.
- Sonderfall **Stolpern** (steiler Hang, ohne Kampfeinwirkung): harmlos — die
  Einheit nimmt ihre vorherige Tätigkeit danach wieder auf (ein Brave lässt
  getragenes Holz fallen und hebt es wieder auf). Ein Treffer während des
  Stolperns macht daraus einen normalen Kampf-Roller inkl. Befehlsverlust.

**Schleudern (`THROWN`)** — Auslöser: Feuerball-Rückstoß, Tornado.
- Wurfparabel durch die Luft, bei der Landung Fallschaden (je nach Höhe),
  danach Schwung-Roller. Landung **im Wasser = Sofort-Tod**.

**Brand** — Auslöser für Einheiten: **nur Lavakontakt** (Vulkan, Lavaströme).
- Erstkontakt mit Lava kostet sofort **20 HP**, dann brennt die Einheit:
  **80 HP über 4 s** (für Braves und Feuerkrieger immer noch tödlich, wenn
  nichts dazwischenkommt). Erneuter Lavakontakt frischt den Brand auf,
  stapelt aber nicht.
- Brand **löst Panik aus** (für die Brenndauer): die Einheit rennt brennend
  umher. Die panik-immune Schamanin brennt stehend und bleibt steuerbar.
- Feuerball/Feuerregen zünden Einheiten **nicht** an — Feuerzauber setzen aber
  **Bäume, Holzstapel und Katapulte** in Brand (das hölzerne Fahrzeug brennt
  ab und versinkt; die Crew erleidet nur den normalen Flächenschaden).

---

## 7. Zauber & Magiesystem

**Ladungssystem:** Mana wird automatisch in Zauber-Ladungen umgewandelt (je
Zauber `charge_cost` Mana pro Ladung, gespeichert bis `max_charges`). Casts
verbrauchen Ladungen; es gibt **keinen separaten Cooldown**. Anzeige als
Ladungs-Pips in der Zauberleiste. Nur die Schamanin zaubert (Wind-up 0,6 s).

| Taste | Zauber | Mana/Ladung | Max. Ladungen | Reichweite | Effekt |
|---|---|---|---|---|---|
| 1 | **Feuerball** | 30 | 4 | 8 m | Direkttreffer 60 HP (r ≤ 0,8 m), Fläche 30 HP (r ≤ 2,5 m). Getroffene werden zurückgeschleudert (kleiner Bogen), landen im Rollzustand. |
| 2 | **Blitz** | 70 | 4 | 12 m | Einheit: **240 HP** (4× Brave; Angrenzende rollen kurz). Gebäude: **+2 Zerstörungsstufen**. |
| 3 | **Schwarm** | 50 | 4 | 8 m | Zufällig wandernder Insektenschwarm (10 s, r = 3 m): Gegner geraten in **Panik (6 s)** und erleiden 5 HP/s. Schamanin ist gegen die Panik immun. |
| 4 | **Landbrücke** | 60 | 4 | 9 m | Kein Schaden. Hebt Terrain in breiter Linie (Halbbreite 1,6 m) an: über Wasser auf Küstenniveau, sonst auf Zielpunkt-Niveau; bei Höhendifferenz entsteht eine begehbare Schräge. |
| 5 | **Tornado** | 110 | 3 | 10 m | Windhose (10 s, r = 2,2 m), wandert zufällig; Gebäude **+1 Stufe alle 2 s**. Einheiten werden hochgewirbelt und weggeschleudert (Sturzschaden 30 HP + Rollschaden; ins Wasser = Tod). |
| 6 | **Erdbeben** | 130 | 2 | 10 m | Hebt/senkt Terrain entlang einer zufälligen Verwerfung (r = 7 m); Gebäude **+2 Stufen**, Einheiten 15 HP. |
| 7 | **Vulkan** | 180 | 1 | 12 m | Teuerster Zauber: hebt einen Vulkankegel (r = 5 m), aktive Lavazone 20 s (Brand/Stufenschaden). |
| 8 | **Feuerregen** | 100 | 2 | 10 m | 12 Feuerbälle regnen über 3 s im Zielgebiet (r = 5,5 m) nieder; je Bolt Feuerball-Werte (60/30 HP). |
| 9 | **Ebene** | 90 | 3 | 10 m | Ebnet das Zielquadrat (9×9 m) exakt ein, harte Kanten. |
| 0 | **Absinken** | 60 | 3 | 10 m | Senkt das Zielgebiet (r = 6 m) um bis zu 3 m ab — nie unter den Meeresboden. |

**Terrainverformung** (Landbrücke, Erdbeben, Vulkan, Ebene, Absinken) ändert
Heightmap, Kollision und Navigation zur Laufzeit.

---

## 8. Steuerung

Alle Tastenbelegungen sind im Hauptmenü unter **Optionen → Steuerung**
einsehbar und frei umbelegbar (persistent in `user://settings.cfg`). Defaults:

| Eingabe | Funktion |
|---|---|
| **Linksklick / Ziehen** | Einheit wählen / Box-Selektion; Klick auf Boden deselektiert |
| **Doppelklick** auf Einheit | Alle sichtbaren Einheiten desselben Typs wählen |
| **Rechtsklick** | Kontextbefehl: Bewegen, Angreifen (Ziel blinkt rot), Baum hacken, Gebäude betreten/bemannen/reparieren; bei selektiertem Gebäude: Rally Point setzen |
| **Shift + Rechtsklick** | Wegpunkt anhängen (Routen/Patrouillen) |
| **W / A / S / D** | Kamera bewegen |
| **Q / E** | Kamera drehen |
| **Mausrad** | Zoom |
| **F** | Angriffsbewegung scharfstellen (nächster Rechtsklick = Attack-Move) |
| **P** | Patrouille an/aus |
| **G** | Reichweiten anzeigen |
| **H** | Hütte bauen |
| **R** | Gebäude drehen (im Platzierungsmodus) |
| **B** | Alle Hütten wählen |
| **K** | Alle Kasernen wählen |
| **T** | Alle Tempel wählen |
| **J** | Alle Feuertempel wählen |
| **1–9, 0** | Zauber wirken (Reihenfolge wie §7) |
| **Esc** | Abbrechen (Baumodus, Zauber-Ziel, Angriffs-Modus) / Pausemenü |

Die Gebäude-Hotkeys (B/K/T/J) selektieren **kartenweit** alle eigenen, fertigen
Gebäude des Typs; ein Rechtsklick setzt dann den Rally Point für **alle**
gleichzeitig. Nicht umbelegbar sind Maustasten, Esc und die Debug-Tasten
(F1 Stresstest, F2 Zeitraffer).
