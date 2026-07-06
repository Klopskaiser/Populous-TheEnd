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
- **Gebäude:** 3D-Modelle (platzierbar auf dem Terrain, an Geländehöhe ausgerichtet).
- **Einheiten:** **2D-Sprites mit Billboarding** – `Sprite3D`/`AnimatedSprite3D` mit
  `billboard = BILLBOARD_ENABLED`, immer zur Kamera gedreht.
  Benötigte Animationen pro Einheit: **Idle, Walk, Attack, Cast** (Cast nur Schamanin/Prediger).

## 4. Einheiten & Steuerung

| Einheit | Rolle |
|---|---|
| **Schamanin** | Wichtigste Einheit, einzige Zauberwirkerin. **HP = 4 × Brave**, **Nahkampfschaden = 2 × Brave**. Stirbt sie, **respawnt** sie nach einer Wartezeit am **Reinkarnationsplatz** (Reincarnation Site); der Stamm des Tötenden erhält einen **einmaligen 15-%-Manaboost in Ladungen**. Pro Stamm genau eine. |
| **Brave (Gefolgsmann)** | Basis-Einheit. Sammelt **passiv Holz**, baut Gebäude aus, generiert durch **Beten Mana**. Wird von Hütten gespawnt. |
| **Krieger** | Nahkampf-Einheit. Ausbildung in der **Kaserne** (Krieger-Trainingslager). |
| **Feuerkrieger** | Fernkampf-Einheit (Feuerbälle). Ausbildung im **Feuertempel** (Feuerkrieger-Trainingslager). |
| **Prediger** | **Konvertiert** feindliche Einheiten zum eigenen Stamm. Ausbildung im **Tempel**. |

**Steuerung:**
- **Rechtsklick** bewegt selektierte Einheiten (Standard-RTS-Selektion: Klick + Box-Select).
- **Wegpunkt-Routen:** Für Einheiten können Routen aus mehreren Wegpunkten festgelegt werden
  (Patrouillen oder einmalige Bewegungsabläufe).
- **Rally Points (Pflicht-Feature):** Für **alle Gebäude** – insbesondere Trainingshütten –
  müssen Sammelpunkte per UI oder Rechtsklick setzbar sein. Neu erzeugte/ausgebildete
  Einheiten laufen automatisch zum Rally Point.

## 5. Gebäude & Wirtschaft

- **Holz** ist die **einzige physische Ressource**. Braves sammeln es von **wilden Bäumen**;
  es wird für Bau und Ausbau von Gebäuden benötigt.
- **Hütten (Huts):**
  - **Bewusste Abweichung vom Original:** Eine Hütte bietet Platz für **100 maximale
    Bevölkerung** (nicht wenige wie im Original).
  - Hütten **spawnen über Zeit neue Braves**, solange das Bevölkerungslimit (Summe der
    Hütten-Kapazitäten) nicht erreicht ist.
- **Trainingsgebäude:** **Kaserne** (Krieger, 5 Holz/3 s), **Feuertempel** (Feuerkrieger,
  10 Holz/4 s), **Tempel** (Prediger, 5 Holz/5 s). Ablauf: Brave betritt das Gebäude → kommt
  nach Ausbildungszeit als entsprechende Kampfeinheit heraus → läuft zum Rally Point.
- **Reinkarnationsplatz:** Respawn-Ort der Schamanin (siehe §4).
- **Gebäudezerstörung (4 Zerstörungsstufen):** Stufe 0 = intakt. Stufen 1–3 (ab 30 % /
  60 % / 90 % Schaden): Gebäude **nicht nutzbar (keinerlei Produktion)**, per Rechtsklick
  durch Arbeiter **reparierbar** — die Reparatur kostet **Holz proportional zum
  reparierten Schaden** (`floor(Schadensanteil × Holzkosten)`, z. B. 90 % Schaden an der
  Hütte → 90 % der Hütten-Holzkosten, abgerundet); visuell brechen mit steigendem Schaden
  mehr Stücke aus dem Modell. Stufe 4 (100 %): Gebäude **versinkt im Boden** und ist
  zerstört, der Bauplatz ist wieder normal betretbar/bebaubar.
  Details: `plans\06_shaman_spells.md`.

## 6. Magiesystem

- **Mana** wird **passiv** generiert; die Rate skaliert mit der **eigenen Bevölkerungszahl**
  (je mehr Leute, desto schneller lädt Mana; betende Braves tragen zusätzlich bei).
- **Ladungssystem (wie im Original):** Mana wird automatisch in **Zauber-Ladungen**
  umgewandelt (je Zauber `charge_cost` und `max_charges`); Casts verbrauchen gespeicherte
  Ladungen, es gibt keinen separaten Cooldown. Anzeige als Ladungs-Pips in der Zauberleiste.
- **Zaubersprüche** (bewusst reduziertes Set):

| # | Zauber | Ladungen | Effekt |
|---|---|---|---|
| 1 | **Feuerball** | 4 | Flächenschaden am Einschlag (½ Brave-Leben, kleiner Umkreis), Direkttreffer 1 × Brave-Leben. Getroffene werden **zurückgeschleudert und in die Luft gehoben** (kleiner Bogen), landen im Rollzustand und kommen ohne Hang schnell zum Stehen. |
| 2 | **Lightning (Blitz)** | 4 | Trifft Einheiten (**4 × Brave-Leben** Schaden; angrenzende Einheiten kommen kurz ins Rollen) oder Gebäude (**+2 Zerstörungsstufen**). |
| 3 | **Swarm (Insektenschwarm)** | 4 | Spawnt einen **zufällig wandernden Schwarm (10 s)**; Gegner in der Nähe geraten in **Panik (6 s)** und erleiden leichten Schaden. Schamanin ist gegen den Panikeffekt immun. |
| 4 | **Landbridge (Landbrücke)** | 4 | Kein Schaden. Hebt Terrain in **breiter Linie** an: über Wasser auf Küstenniveau, sonst auf das Niveau des Zielpunkts; bei Höhendifferenz entsteht eine **begehbare Schräge** (→ Laufzeit-Terrainverformung, §3). |
| 5 | **Tornado** | 3 | Windhose (8 s), wandert zufällig; über Gebäuden **+1 Zerstörungsstufe alle 2 s**. Einheiten im Weg werden zur Spitze **hochgewirbelt**, kurz mitgetragen und mit hoher Geschwindigkeit **weggeschleudert** (Sturzschaden ½ Brave-Leben + Rollschaden; ins Wasser = Sofort-Tod). |

**Neue Mechaniken durch die Zauber:** Panik, Umherschleudern von Einheiten
(Wurf-Parabel → Rollen bis zum Ausrollen), Gebäudezerstörung in Stufen (§5).

## 7. Skirmish-KI

- Die KI nutzt **exakt dieselben Mechaniken** wie der Spieler (keine Cheats, gleiche
  Ressourcen-/Mana-/Trainingsregeln).
- **State-Machine** mit mindestens drei Zuständen:
  - **Build-State:** Hütten bauen, Holz sammeln lassen, Trainingslager errichten.
  - **Train-State:** Braves in Trainingsgebäude schicken, Armee aufbauen.
  - **Attack-State:** Truppen sammeln und mit Schamanin + Trupps die Spielerbasis angreifen.
- Übergänge z. B. nach Schwellwerten (Bevölkerung, Gebäudezahl, Armeegröße, Mana).

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

## 10. Fortschritts-Doku (`plans\PROGRESS.md`)

- **`plans\PROGRESS.md` ist die Ist-Stand-Doku des Projekts:** was pro Phase tatsächlich
  gebaut wurde (Dateien + Kern-APIs), Extras/Abweichungen von den Phasenplänen,
  Erkenntnisse/Stolpersteine und Verifikationsstand.
- **Bei Arbeitsbeginn an einer neuen Aufgabe/Phase zuerst lesen:**
  `plans\00_overview.md` (Phasenstatus + Arbeitsanweisung) und `plans\PROGRESS.md` –
  damit ist der bisherige Stand bekannt, ohne den Code durchsuchen zu müssen.
- **Nach Abschluss einer Phase oder größeren Erweiterung:** PROGRESS.md ergänzen
  (Schritt 7 der Arbeitsanweisung in `plans\00_overview.md`).
