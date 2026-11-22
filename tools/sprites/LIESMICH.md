# Spritesheets der Fußeinheiten prüfen und angleichen

Die Sheets für Brave, Krieger, Feuerkrieger und Prediger kommen aus einem KI-Bildgenerator
(die der Schamanin werden aus einer 3D-Figur gerendert, siehe `tests/tool_render_unit_sprites.gd`).
Generierte Sheets stimmen in Raster, Größe und Stand oft nicht miteinander überein. Das Spiel
schneidet Frames unverändert aus, jede Abweichung ist dort ein Sprung oder ein Wachsen der Figur.
Die Regeln selbst stehen in `assets\README.md`, Abschnitt „Einheiten-Spritesheets“.

Beide Werkzeuge brauchen Python mit Pillow.

## Prüfen: `sheets_pruefen.py`

```powershell
python D:\game\Populous-TheEnd\tools\sprites\sheets_pruefen.py D:\game\Populous-TheEnd\assets\units
```

Das Argument ist der Ordner einer Einheit oder ein Ordner voller Einheiten. Gemeldet wird je
Einheit: `FEHLER` (im Spiel sichtbar falsch) und `HINWEIS` (ansehen). Geprüft werden Raster,
Größe und Stand gegen die Ruhepose, ob ein Sheet in der Ruhepose beginnt, ob die Zeilen
verschiedene Ansichten zeigen, Figuren am Zellenrand, leere Frames, der Takt von Schlag und
Wurf und welche Animationen der Einheit fehlen.

Nicht prüfbar ist, ob eine Zeile die **richtige** Ansicht zeigt (vorn, hinten, rechts …) und ob
die Bewegung gut aussieht. Das muss man ansehen.

## Angleichen: `sheet_angleichen.py`

```powershell
python D:\game\Populous-TheEnd\tools\sprites\sheet_angleichen.py <quellordner> D:\game\Populous-TheEnd\assets\units\firewarrior idle
```

Legt Frame 1 jeder Zeile gegen `stand.png`, sucht einen Maßstab fürs ganze Sheet und je Zeile die
waagerechte Verschiebung und schreibt das angeglichene Sheet in den Zielordner. Ein viertes
Argument nennt ein anderes Bezugssheet, ein fünftes einen festen Maßstab (`1.0` = nur rücken).
Voraussetzung: das Sheet beginnt in der Ruhepose. Für `walk` taugt es deshalb nicht.

Stand 2026-11-22, Feuerkrieger: `idle` Maßstab 0,920 und in den Seitenansichten 5 px gerückt,
`throw` nur gerückt (3,5 bis 5,5 px).

## Skalieren und ausrichten: `sheet_ausrichten.py`

```powershell
python D:\game\Populous-TheEnd\tools\sprites\sheet_ausrichten.py <quelle.png> <ziel.png> 0.894 frame
```

Skaliert ein Sheet um den Fußpunkt und rückt die Kopfmitte auf die Zellmitte, je Frame (`frame`,
fürs Gehen) oder je Zeile aus Frame 1 (`zeile`, für Schläge). Braucht keine Ruhepose; mit
`--stand <stand.png> fuss|schmal` schreibt es zusätzlich eine Ruhepose aus dem Frame mit dem engsten
Fußstand bzw. der schmalsten Figur, `--beginn` lässt jede Zeile mit diesem Frame beginnen.

Stand 2026-11-22: Brave `walk` und `punch` sowie Prediger `stand` auf 0,894 (94 → 84 px, die Größe des
Feuerkriegers). Der Brave hatte keine brauchbare Ruhepose: `stand.png` ist die Deckung aus `punch`
(Fäuste vor der Brust), `punch` beginnt jetzt dort. `idle.png` ist bei Brave und Prediger nur dieser
eine Frame, damit das Spiel nicht alle paar Sekunden den Platzhalter zeigt. Beides ersetzen, sobald
echte `stand`- und `idle`-Sheets kommen. `sit`, `roll` und die liegenden Posen sind unverändert,
sie passten schon zum Feuerkrieger.

## Vorgaben für neue Sheets aus dem Generator

Gilt für jedes Sheet einer Einheit:

- **Zelle 64 × 96 px**, durchsichtiger Hintergrund, harte Kante (das Spiel verwirft Alpha unter 0,5).
- **Die Figur ist in allen Sheets der Einheit gleich groß** und steht an derselben Stelle: Füße
  unten in der Zelle, Körper waagerecht mittig. Maßstab ist `stand.png`.
- **Platz lassen.** Steht die Figur schon 94 px hoch in der 96-px-Zelle, passt kein erhobener Arm
  mehr hinein und die Figur wird am Rand abgeschnitten. Der Feuerkrieger ist stehend 84 px hoch.
- **Alle Einheiten im selben Maßstab.** Geliefert sind Brave und Prediger mit 94 px, der
  Feuerkrieger mit 84 px: im Spiel wäre der Brave 12 % größer als der Feuerkrieger.
- **8 Zeilen** in dieser Reihenfolge: vorn, hinten, rechts, links, vorn rechts, vorn links, hinten
  rechts, hinten links. Oder 5 Zeilen (vorn, hinten, rechts, vorn rechts, hinten rechts), dann
  spiegelt das Spiel die linken Ansichten.
- **Aus der Ruhepose heraus und in sie zurück:** `idle`, `punch`, `kick`, `shove`, `throw`, `cast`,
  `attack` beginnen mit der Pose aus `stand.png` und enden so, dass die Schleife ohne Sprung
  wieder dort ankommt.
- Gleiche Kleidung, gleiche Farben, gleiches Licht wie in den vorhandenen Sheets der Einheit.

Je Animation (Frames und fps sind Vorschläge, der Takt in der dritten Spalte ist Pflicht):

| Datei | Frames × fps | Pflicht | Inhalt |
|---|---|---|---|
| `stand` | 1 | | Ruhepose, entspannt stehend. Bezug für alles andere. |
| `idle` | 8–12 × 6 | mindestens 0,4 s | Kleine Bewegung im Stand, läuft nur gelegentlich einmal durch. |
| `walk` | 6–8 × 8 | Schleife | Gehen auf der Stelle. |
| `punch` | 8 × 10 | genau 0,8 s | Faustschlag. |
| `kick` | 8 × 10 | genau 0,8 s | Tritt. |
| `shove` | 8 × 10 | genau 0,8 s | Stoß mit beiden Händen. |
| `throw` | 9 × 6 | genau 1,5 s | Nur Feuerkrieger: Feuerball werfen. |
| `cast` | 8 × 8 | Schleife | Prediger: predigen (läuft 4 bis 9 s in Schleife). Schamanin: zaubern. |
| `attack` | 4–6 × 6 | Schleife | Nur Brave: Arbeitsbewegung (hacken, bauen, pflanzen). |
| `jump` | 2 | genau 2 Frames | Nur Brave: Frame 1 stehend, Frame 2 in der Luft mit erhobenen Armen. |
| `carry` | 1–2 | | Nur Brave: stehen mit Holz. |
| `carry_walk` | 6–8 × 8 | Schleife | Nur Brave: gehen mit Holz. |
| `sit` | 1 | | Sitzt am Boden (während der Bekehrung). |
| `roll` | 8 × 8 | Schleife | Purzeln am Boden. |
| `drown` | 4 × 6 | etwa 0,7 s | Zappeln im Wasser; die untere Hälfte verdeckt das Wasser. |
| `airborne` | 5–7 × 6 | eine Zeile | Flug durch die Luft, aufrecht gezeichnet, Rücken sichtbar. |
| `dead_back`, `dead_front` | 1 | eine Zeile, beide oder keine | Leiche, aufrecht gezeichnet: Rückenlage zeigt das Gesicht, Bauchlage den Rücken. |

Welche Einheit was braucht (alle: `stand`, `idle`, `walk`, `sit`, `roll`, `drown`, `airborne`,
beide Leichen):

| Einheit | zusätzlich | Stand 2026-11-22: fehlt |
|---|---|---|
| Brave | `punch`, `kick`, `shove`, `attack`, `jump`, `carry`, `carry_walk` | echtes `stand` und `idle` (Notbehelf eingebaut), `kick`, `shove`, `attack`, `jump`, `carry`, `carry_walk`, `drown` |
| Krieger | `punch`, `kick` | `stand`, `idle`, `walk`, `punch`, `kick`, `roll`, `drown` |
| Feuerkrieger | `throw`, `kick`, `shove` | `kick`, `shove`, `roll`, `drown` |
| Prediger | `cast`, `punch`, `shove` | echtes `idle` (Notbehelf eingebaut), `walk`, `cast`, `punch`, `shove`, `sit`, `roll`, `drown` |

Im Manifest steht `fps` je Animation; für die Leichen unter `"dead"`, nicht unter
`"dead_back"` / `"dead_front"`.

## Bekannte Mängel der gelieferten Sheets (2026-11-22)

- **Brave `idle.png`:** 1116 px breit, das sind 18 Frames zu 62 statt 64 px, und alle acht Zeilen
  zeigen die Seitenansicht. Nicht eingebaut, neu erzeugen.
- **Brave `walk`, `punch`:** die Figur war 94 px hoch und stand je Ansicht bis 13 px neben der
  Zellmitte (eingebaut: skaliert und ausgerichtet). Was der Generator am Zellenrand abgeschnitten
  hat, bleibt abgeschnitten. `roll` stößt weiter in einem Drittel der Frames an den Rand.
- **Feuerkrieger `walk`:** die Rückenansicht ist 12 % niedriger als die Ruhepose.
- **Leichen:** acht Zeilen geliefert, das Spiel nimmt nur Zeile 1.
