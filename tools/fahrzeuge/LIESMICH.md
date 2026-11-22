# Fahrzeugmodelle bauen (Katapult, Feuerramme)

Dieser Ordner macht aus den gelieferten Rohmodellen die Spielmodelle mit beweglichen Teilen.
Er liegt unter `tools\` mit einer `.gdignore`, Godot importiert hier also nichts.

| | |
|---|---|
| Eingang | `quelle\siege_engine.glb`, `quelle\fire_ram.glb` (unverändert, wie geliefert) |
| Skript | `fahrzeuge_bauen.py` (Blender, Stellschrauben stehen oben im Skript) |
| Ausgang | `assets\models\units\siege_engine.glb`, `assets\models\units\fire_ram.glb` |
| Protokoll | `bau_protokoll.txt` (Knoten, Achsen, Radien, Dateigrößen; Fehler stehen als Traceback darin) |

## Bauen

Blender 5.3 aus dem Store lässt sich nur über den Starter aufrufen und gibt nichts auf der
Konsole aus, deshalb das Protokoll. Der Starter kehrt sofort zurück; fertig ist der Lauf, wenn
im Protokoll `fertig` steht.

```powershell
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\BlenderFoundation.Blender_ppwjx1n5r4v9t\blender-launcher.exe" --background --factory-startup --python D:\game\Populous-TheEnd\tools\fahrzeuge\fahrzeuge_bauen.py -- alle
```

Statt `alle` geht `katapult` oder `ramme`. Ein zweites Argument ist ein Ordner für
Vorschaubilder aus Blender (Ruhelage, Wurf, gedrehte Räder, Räder abgerückt).

Danach einmal importieren und im Spiel-Renderer ansehen:

```powershell
& $GODOT --path D:\game\Populous-TheEnd --headless --import
```

```powershell
& $GODOT --path D:\game\Populous-TheEnd -s res://tests/diag_vehicle_models.gd -- D:\game\Populous-TheEnd\tools\fahrzeuge\bilder
```

`diag_vehicle_models.gd` läuft ohne `--headless`, nutzt die echten Einheitenszenen und schreibt
sechs Standbilder und `messwerte.txt` (Radius, Seite und Drehwinkel jedes Rads; Lage des
fliegenden Steins neben der Geschossbahn).

## Was das Skript macht

**Katapult.** Das Rohmodell besteht aus 45 unverbundenen Einzelteilen in zwei Netzen (Holz und
Metall, Seile). Jedes Teil wird nach Lage und Größe seines Kastens einer Gruppe zugeordnet
(`katapult_gruppe`): vier Räder, Wurfarm (Balken, Schale, Gegengewicht, Lagerklotz), Stein,
Winde, Rumpf. Das Spannseil wird auf halber Höhe geteilt: die Schlinge um den Arm fliegt mit,
die Wicklung an der Winde bleibt stehen. Der Drehpunkt des Arms ist der Bolzen durch die
beiden Ständer, der Ursprung des Modells die Mitte der vier Radachsen.

**Feuerramme.** Das Rohmodell ist ein einziges verschmolzenes Netz. Die Räder werden an zwei
Ebenen knapp außerhalb des Rahmens abgeschnitten (`RAMME_SCHNITT`); Rad ist, was außerhalb
der Ebene und näher als `RAMME_RAD_RADIUS` an einer der beiden Achsen liegt. Die Schnittflächen
an Rad und Rumpf werden mit einer dunklen Fläche verschlossen (ein einziger UV-Punkt, der
dunkelste am Schnittrand). Die Schnauze liegt 1,15 m vor dem Ursprung, weil die Flamme im
Spiel 1,2 m vor der Mitte beginnt (`FireRam.NOZZLE_OFFSET`).

**Beide.** Vorderseite +Z, Boden bei y = 0, ein Wimpel `Flag` für die Stammesfarbe (im
Rohmodell gibt es keinen), Texturen auf 1024 Pixel verkleinert.

## Knoten, die das Spiel sucht

| Knoten | Wer bewegt ihn | Was |
|---|---|---|
| `Wheel_FL` `Wheel_FR` `Wheel_RL` `Wheel_RR` | `CrewedVehicle._spin_wheels` | Ursprung auf der Achse; dreht um X um gefahrene Strecke / Radius. Radius = Achshöhe über dem Boden. Beim Drehen auf der Stelle laufen linke und rechte Räder gegeneinander. |
| `Arm` | `SiegeEngine._tick_visual` | Ursprung im Bolzen, Ruhelage gespannt. Schnellt in 0,12 s um 1,15 rad hoch, federt 0,25 s am Querholz, wird in 0,7 s zurückgespannt (`SiegeEngine.arm_snap`). |
| `Stone` (Kind von `Arm`) | `SiegeEngine._tick_visual`, `SiegeEngine._dress_shot` | Unsichtbar vom Abwurf bis der Arm wieder gespannt ist. Sein Netz fliegt als Geschoss (`SiegeShot.stone_mesh`): 0,1 s nach dem Schuss erscheint es dort, wo der Arm den Stein dann hält, 1,6-fach vergrößert (`SiegeShot.STONE_FLIGHT_SCALE`), und läuft auf die unveränderte Geschossbahn ein. Der Ursprung muss deshalb in der Steinmitte liegen (der Stein taumelt um ihn). |
| `Winch` | `SiegeEngine._tick_visual` | Dreht eine Umdrehung mit dem Arm mit. |
| `Flag` | `CrewedVehicle._refresh_flag_color` | Stammesfarbe, grau solange niemand das Fahrzeug bedient. |

## Stolpersteine

- **Godot 4.7 lädt keine JPEGs mit ICC-Profil.** Blender bettet beim Neuschreiben einer
  sRGB-Textur eines ein, das Modell erscheint dann weiß bzw. silbern und der Import meldet
  `Couldn't load image index … image/jpeg`. `ausgeben()` markiert deshalb alle Bilder vor dem
  Export als „Non-Color“. Das muss **vor** dem Verkleinern passieren: der Farbraumwechsel lädt
  das Bild neu und verwirft die Verkleinerung (die Datei war dann 3,7 statt 0,8 MB groß).
- Der Importer von Blender legt die Meshdaten Z-oben ab und lässt Vertices an UV-Nähten
  doppelt. Alle Maße im Skript stehen im Rohsystem der glTF-Datei (`zu_gltf`, `zu_blender`),
  und vor dem Verschließen eines Schnitts werden die Vertices auf der Schnittebene verschweißt,
  sonst schließt sich der Rand nicht.
- Importierte Objekte haben Quaternion-Drehung; `rotation_euler` wirkt erst nach
  `rotation_mode = 'XYZ'`.
- Godot legt beim Import die Texturen neben das Modell (`siege_engine_Image_0.jpg` usw.). Sie
  gehören zum Modell und werden bei jedem Import neu geschrieben.
- Die Räder der Feuerramme sind nicht ganz rund und nicht gleich groß (Radius 0,225 bis
  0,238 m), und das gebackene Licht dreht sich mit. Bei Spielgröße fällt beides kaum auf.
