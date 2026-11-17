# 10l – Golem: Haltung „Sitzen“ (Plan, 2026-11-17)

Status: **Plan, noch nicht umgesetzt.** Animationen kommen später aus
`D:\game\gymnastikschuh` (Clipvertrag unten). Offene Punkte am Ende.

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
