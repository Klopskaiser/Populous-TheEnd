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
| **Schamanin** | Wichtigste Einheit, einzige Zauberwirkerin. Stirbt sie, **respawnt** sie nach einer Wartezeit am **Reinkarnationsplatz** (Reincarnation Site). Pro Stamm genau eine. |
| **Brave (Gefolgsmann)** | Basis-Einheit. Sammelt **passiv Holz**, baut Gebäude aus, generiert durch **Beten Mana**. Wird von Hütten gespawnt. |
| **Krieger** | Nahkampf-Einheit. Ausbildung im Krieger-Trainingslager. |
| **Feuerkrieger** | Fernkampf-Einheit (Feuerbälle). Ausbildung im Feuerkrieger-Trainingslager. |
| **Prediger** | **Konvertiert** feindliche Einheiten zum eigenen Stamm. Ausbildung im Tempel. |

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
- **Trainingsgebäude:** Krieger-Trainingslager, Feuerkrieger-Trainingslager, **Tempel**
  (für Prediger). Ablauf: Brave betritt das Gebäude → kommt nach Ausbildungszeit als
  entsprechende Kampfeinheit heraus → läuft zum Rally Point.
- **Reinkarnationsplatz:** Respawn-Ort der Schamanin (siehe §4).

## 6. Magiesystem

- **Mana** wird **passiv** generiert; die Rate skaliert mit der **eigenen Bevölkerungszahl**
  (je mehr Leute, desto schneller lädt Mana; betende Braves tragen zusätzlich bei).
- **Zaubersprüche** (bewusst reduziertes Set):

| # | Zauber | Effekt |
|---|---|---|
| 1 | **Blast (Druckwelle)** | Wirft feindliche Einheiten physisch zurück (**Knockback**). |
| 2 | **Lightning (Blitz)** | Tötet eine einzelne feindliche Einheit **sofort**. |
| 3 | **Swarm (Insektenschwarm)** | Betroffene gegnerische Einheiten laufen **panisch und unkontrollierbar** umher. |
| 4 | **Landbridge (Landbrücke)** | **Hebt Terrain an**, um Wasser oder Schluchten passierbar zu machen (→ Laufzeit-Terrainverformung, §3). |
| 5 | **Tornado** | **Zerstört Gebäude** und wirft Einheiten in die Luft. |

## 7. Skirmish-KI

- Die KI nutzt **exakt dieselben Mechaniken** wie der Spieler (keine Cheats, gleiche
  Ressourcen-/Mana-/Trainingsregeln).
- **State-Machine** mit mindestens drei Zuständen:
  - **Build-State:** Hütten bauen, Holz sammeln lassen, Trainingslager errichten.
  - **Train-State:** Braves in Trainingsgebäude schicken, Armee aufbauen.
  - **Attack-State:** Truppen sammeln und mit Schamanin + Trupps die Spielerbasis angreifen.
- Übergänge z. B. nach Schwellwerten (Bevölkerung, Gebäudezahl, Armeegröße, Mana).

## 8. Geplante Projektstruktur & Konventionen

Zielbild für die kommenden Aufgaben (noch nicht angelegt):

```
D:\game\Populous-TheEnd\
├── project.godot
├── CLAUDE.md                  # diese Datei
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
