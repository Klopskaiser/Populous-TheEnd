class_name Balance

## ZENTRALE BALANCE-DATEI — hier werden alle Spielwerte gepflegt.
##
## Jede Konstante wird von genau einer Stelle im Code referenziert (die
## Klassen behalten ihre lokalen Konstantennamen und beziehen den Wert von
## hier). Einen Wert ändern = hier ändern; nach der Änderung das Spiel neu
## starten (und bei Balancing-Läufen die Testsuite prüfen — einige Tests
## binden Werte bewusst fest, z. B. die Zauber-Ladungszahlen).
##
## Einheiten-Referenz: 1 Brave-Leben = 60 HP. Zeiten in Sekunden,
## Reichweiten/Radien in Metern (1 Zelle = 1 m), Schaden in HP.

# =============================================================================
# EINHEITEN — Leben, Tempo, Kampfwerte
# =============================================================================

## Mittlere Ruhezeit (s) einer stehenden Einheit, bevor ihre Idle-Animation
## EINMAL durchläuft. Dazwischen zeigt sie einen statischen Standframe — eine
## dauernd wippende Armee machte das Spielbild unruhig. Pro Typ überschreibbar:
## `<TYP>_IDLE_ANIM_INTERVAL` anlegen und in der Unterklasse
## `_idle_anim_interval()` überschreiben (Muster WARRIOR_SHOVE_CHANCE).
## **0.0 stellt die alte Dauerschleife wieder her.**
const UNIT_IDLE_ANIM_INTERVAL: float = 8.0
## Streuung der Ruhezeit als Anteil des Intervalls: bei 0,8 liegt der Abstand
## zweier Wiedergaben zwischen 20 % und 180 % davon (bei 8 s also 1,6 bis
## 14,4 s), im Mittel genau beim Intervall. Ohne Streuung zuckte eine
## angekommene Gruppe im Gleichtakt; 2026-09-05 von 0,4 verdoppelt, weil die
## Abstände im Spiel noch zu gleichmäßig wirkten (Nutzerurteil).
## **Obergrenze:** der Renderer deckelt die Streuung bei
## `1 - Animationsdauer/Intervall` — sie muss kleiner bleiben, sonst könnten
## sich zwei Durchläufe überlappen. Für 8 s und die 1-s-Idle sind das 0,875.
const UNIT_IDLE_ANIM_JITTER: float = 0.8

# --- Brave (Gefolgsmann) ---
const BRAVE_HP: int = 60
const BRAVE_SPEED: float = 4.0
## Aggro-Radius unbeschäftigter Braves (kleine Dorfwache).
const BRAVE_IDLE_AGGRO_RADIUS: float = 3.0

# --- Krieger ---
const WARRIOR_HP: int = 120
const WARRIOR_SPEED: float = 4.0
## Nahkampf-Multiplikator auf die Basis-Schlagwerte (Punch/Kick/Shove).
## 3,0 -> 2,5 (Nutzervorgabe 2026-09-07): der Krieger schlaegt weniger hart zu,
## tritt dafuer deutlich oefter (s. WARRIOR_KICK_CHANCE).
const WARRIOR_MELEE_STRENGTH: float = 2.5
## Nahkampf-Attackenchancen (Rest = Punch, s. Unit._roll_attack_kind):
## Der Krieger schubst GAR NICHT mehr (2026-09-07, vorher 0,04) und tritt in
## 35 % der Schlaege — 65 % bleiben der Faustschlag.
const WARRIOR_SHOVE_CHANCE: float = 0.0
const WARRIOR_KICK_CHANCE: float = 0.35

# --- Golem (beschworene Einheit, Zauber 13, 2026-09-06) ---
## Beschworene Riesin, seit 2026-11-15 eine schlanke Figur statt eines 4 x 3 m
## breiten Klotzes: so hoch wie der Wachturm, 2,3 m breit x 1,8 m tief, eigenes
## 3D-Modell, lebt GOLEM_LIFETIME Sekunden (+GOLEM_LIFE_PER_KILL je Kill) und
## zerfaellt dann. 400 -> 800 nach dem ersten Spieltest ("viel zu schwach").
const GOLEM_HP: int = 800
## Statur der Figur: Breite und Tiefe wie bei einer 5,25 m hohen Figur (die
## Zinnen des Wachturms: Schaft 4,2 + Plattform + Zinnen, Nutzervorgabe
## 2026-11-15), die HOEHE aber 10 % weniger — sie wirkte zu schlank
## (Nutzervorgabe, selber Tag). Das Modell ist auf 4 m gebaut; das Spiel skaliert
## Breite/Tiefe mit GOLEM_BUILD_HEIGHT und die Hoehe mit GOLEM_HEIGHT.
const GOLEM_BUILD_HEIGHT: float = 5.25
const GOLEM_HEIGHT: float = 4.725
const GOLEM_SPEED: float = 3.5
## Nahkampf-Reichweite (Abstand zum Ziel, ab dem angegriffen wird — gross, damit
## die Riesin nicht an ihrem Opfer klebt). Beide Angriffe reichen weiter.
const GOLEM_REACH: float = 3.0
## Koerperbox (Halbmasse im Blickrahmen): 1,55 m breit, 1,22 m tief — erst 75 %,
## dann noch einmal 90 % der frueheren 2,3 x 1,8 m (Nutzer 2026-11-15; die Figur
## selbst misst stehend 2,0 x 1,0 m). Sie bestimmt Auswahl, Schatten und Abstand
## UND, mit der Stufe skaliert, den Trampelradius und die Flaeche, die der Gigant
## einebnet. Die Wirkflaechen der Angriffe stehen unten.
const GOLEM_BODY_HALF_WIDTH: float = 0.77625
const GOLEM_BODY_HALF_DEPTH: float = 0.6075
## ZWEI ANGRIFFE (Nutzervorgabe 2026-11-15), beide im Takt GOLEM_STRIKE_COOLDOWN:
##
## HANDSCHLAG (slam): sie bueckt sich und schlaegt beide Haende auf den Boden —
## Flaechenschaden RUNDHERUM. Kreis mit GOLEM_SLAM_RADIUS um den Punkt
## GOLEM_SLAM_FORWARD vor ihr (dort treffen die Haende auf: seit 2026-11-16
## liegen beide Hand-Schuhe dicht nebeneinander auf diesem Punkt, im Clip 0,91 m
## bei 4 m Modellhoehe, also 1,2 m bei 5,25 m). 2,6 m Radius sind 21 m2, genau die
## Flaeche des alten Schlags (Hitbox 4x3 + Feld 3x3).
const GOLEM_SLAM_RADIUS: float = 2.6
const GOLEM_SLAM_FORWARD: float = 1.2
const GOLEM_SLAM_DAMAGE: int = 25
## Sekunden vom Ansetzen bis zum Aufschlag — aus der GEBUECKTEN Haltung (Clip
## `slam_low`). Bis 2026-11-16 waren es 0,8 s: das Buecken steckte im Angriff.
## Jetzt ist das Buecken der Haltungswechsel (GOLEM_STANCE_SWITCH_TIME 0,4 s),
## aus dem Stand dauert der erste Handschlag also 0,75 s.
const GOLEM_SLAM_WINDUP: float = 0.35
## HALTUNG (Nutzervorgabe 2026-11-15, gebaut 2026-11-16): der Golem steht ODER
## ist gebueckt.
##   STEHEND  — Tritt, Luftschlag, Laufen.
##   GEBUECKT — Handschlag und Trommeln; die kommen von dort schneller (kuerzere
##              Ausholzeit; der Handschlag kommt alle GOLEM_SLAM_COOLDOWN wieder,
##              das Trommeln im normalen Takt), aber er kann so weder laufen
##              noch treten.
## Der Wechsel dauert GOLEM_STANCE_SWITCH_TIME Sekunden mal Wurzel(Groesse),
## hoechstens GOLEM_STANCE_SWITCH_MAX — in der Zeit greift er nicht an und laeuft
## nicht. Er wechselt von selbst, nach dem ERWARTETEN SCHADEN (s.
## GOLEM_STRUCTURE_VALUE): er nimmt den Angriff mit dem meisten Schaden je
## Sekunde, und braucht der die andere Haltung, wechselt er. Ausserdem steht er
## auf, wenn ein Luftschiff in Schlagweite kommt oder er laufen muss.
## Freiwillige Wechsel fruehestens GOLEM_STANCE_MIN_TIME Sekunden nach dem
## letzten (sonst pendelte er); wer laufen MUSS, steht sofort auf.
## 0,45 -> 0,4 s bei Startgroesse (Nutzer 2026-11-16); mit der Wurzel der Groesse
## waechst es wie bisher: Stufe 6: 0,69 s, Stufe 7: 0,85 s, 100 m: 1,84 s.
const GOLEM_STANCE_SWITCH_TIME: float = 0.4
const GOLEM_STANCE_SWITCH_MAX: float = 2.0
const GOLEM_STANCE_MIN_TIME: float = 3.0
## SITZEN (Nutzervorgabe 2026-11-17, plans/10l_golem_sitting.md, erste Stufe): dritte
## Haltung fuer ALLE Golems ab GOLEM_SIT_MIN_HEIGHT Koerperhoehe, nur ueber die gebueckte
## erreichbar (stehen -> buecken -> sitzen und denselben Weg zurueck, endet stehend).
## NUR VON HAND (Taste V, Knopf in der Seitenleiste): nichts setzt sie von selbst hin
## oder laesst sie aufstehen, die KI nutzt es nicht. Solange sie sich setzt, sitzt oder
## aufsteht, nimmt sie keine Befehle an, laeuft nicht, greift nicht an (erste Stufe: es
## gibt noch keine Sitzangriffe), wird von anderen Golems nicht geschoben, trampelt und
## ebnet nicht ein; waechst sie, streckt sie sich nicht (kein Clip, sie bleibt sitzen).
## Hinsetzen und Aufstehen dauern je GOLEM_SIT_TIME Sekunden bei GOLEM_SIT_REF_HEIGHT,
## mal Wurzel(Hoehe / GOLEM_SIT_REF_HEIGHT), OHNE Obergrenze (Nutzer: erst ansehen;
## 80 m: 4,9 s; der Daemonengolem 15 % schneller). Die Clips sit_down / sit_up sind 1,5 s lang.
const GOLEM_SIT_MIN_HEIGHT: float = 30.0
const GOLEM_SIT_TIME: float = 3.0
const GOLEM_SIT_REF_HEIGHT: float = 30.0
## SITZFLAECHE: ein Rechteck unter dem Po (Haende und Fuesse zaehlen nicht), in Metern
## des 4-m-Modells — die Mitte GOLEM_SIT_SEAT_BACK hinter den Fuessen (gemessen am Clip
## sit_idle: Becken 1,3 m dahinter, Hueftgelenke 0,38 m auseinander), quer
## GOLEM_SIT_SEAT_WIDTH, laengs GOLEM_SIT_SEAT_LENGTH; skaliert wie das Modell (breit wie
## Modellbreite x Groesse — beim Daemonengolem also 25 % breiter). Bei 30 m: 5 x 5 m, 10,8 m
## hinter den Fuessen. Im Sitzen liegt der Standpunkt des Golems (Zielkreis,
## Auswahlkreis, Abstand der Golems) auf der Mitte dieser Flaeche.
const GOLEM_SIT_SEAT_BACK: float = 1.3
const GOLEM_SIT_SEAT_WIDTH: float = 0.6
const GOLEM_SIT_SEAT_LENGTH: float = 0.6
## Kein Gebaeude und keine Baustelle (gleich welchen Stamms) darf die Sitzflaeche
## beruehren, sie liegt ganz an Land. Ist ihr Platz belegt, sucht sie bis
## GOLEM_SIT_SEARCH_SHARE ihres Koerperradius daneben (und rueckt beim Buecken dorthin),
## sonst setzt sie sich nicht.
const GOLEM_SIT_SEARCH_SHARE: float = 0.5
## SITZSCHADEN: wer beim Aufsetzen unter der Sitzflaeche steht (alle Staemme), nimmt
## GOLEM_SIT_DAMAGE_MULT x Trampelschaden — sofort und dann alle
## GOLEM_SIT_DAMAGE_INTERVAL Sekunden, solange er noch darunter steht. Wer herauslaeuft,
## faellt heraus; wer spaeter darunter kommt, wird nicht getroffen. Die Flaeche waechst
## nicht mit, wenn sie im Sitzen groesser wird. Feindliche Bodenfahrzeuge darunter
## nehmen je Tick einen Treffer wie unter dem Trampeln. Eigene Opfer zaehlen nicht als Kill.
const GOLEM_SIT_DAMAGE_MULT: int = 4
const GOLEM_SIT_DAMAGE_INTERVAL: float = 5.0
## Im Sitzen ist sie das groessere Ziel: Zielradius mal diesem Faktor.
const GOLEM_SIT_TARGET_RADIUS_FACTOR: float = 2.0
## So viele Sekunden VOR dem Aufsetzen wechselt ihr Standpunkt (und mit ihm der
## Auswahlkreis) schon auf die Mitte der Sitzflaeche (Nutzer 2026-11-17); der
## Sitzschaden faellt erst beim Aufsetzen.
const GOLEM_SIT_SEAT_LEAD: float = 0.5
## HOEHE IM SITZEN (Nutzer 2026-11-17): die sitzende Figur liegt nie tiefer als der
## Boden unter Fuessen, Po und Haenden (sonst verschwanden Arme und Beine im Hang);
## hoeher darf sie liegen. Die Haende liegen GOLEM_SIT_HAND_BACK hinter und
## GOLEM_SIT_HAND_SIDE neben den Fuessen (Clip sit_idle, Metern des 4-m-Modells).
const GOLEM_SIT_HAND_BACK: float = 2.1
const GOLEM_SIT_HAND_SIDE: float = 0.7
## EINEBNEN BEIM HINSETZEN (Nutzer 2026-11-17): waehrend sie sich setzt, gleicht sich
## der Boden unter der ganzen sitzenden Figur — von GOLEM_SIT_LEVEL_FRONT vor bis
## GOLEM_SIT_LEVEL_BACK hinter den Fuessen, GOLEM_SIT_LEVEL_HALF_WIDTH zu jeder Seite
## (4-m-Modell) — an die Hoehe ihrer Fuesse an, gehoben wie gesenkt; ringsum eine
## begehbare Boeschung (GOLEM_FLATTEN_SLOPE). Gebaeude (mit einer Zelle Rand), das
## Ufer und der Meeresboden bleiben, nichts sinkt unter die Wasserlinie (wie beim
## Einebnen des Giganten). Die Figur ist bei 4 m Bauhoehe 2,6 m lang und 1,5 m breit.
## Seit 2026-11-18 (Nutzer) in zwei Teilen: beim Hinsetzen SOFORT der Auswahlkreis um die
## Sitzmitte (selection_ring_radius), im Sitzen dann NACH UND NACH das Rechteck der Figur in ihrer
## aktuellen Blickrichtung (dreht sie sich, wandert es mit) — alle GOLEM_FLATTEN_INTERVAL Sekunden
## hoechstens GOLEM_FLATTEN_RATE Meter je Sekunde auf die Fusshoehe vom Hinsetzen. NUR GESENKT (Nutzer
## 2026-11-18): liegt Gelaende tiefer als ihre Fuesse, bleibt es so.
const GOLEM_SIT_LEVEL_FRONT: float = 0.35
const GOLEM_SIT_LEVEL_BACK: float = 2.35
const GOLEM_SIT_LEVEL_HALF_WIDTH: float = 0.8
## SITZANGRIFFE (Nutzervorgabe 2026-11-17, scripts/units/golem_sit_combat.gd): Beine und
## Arme greifen unabhaengig an. ZONEN UND WERTE DER SITZANGRIFFE (Nutzervorgaben
## 2026-11-17). Masse in Metern des 4-m-Modells, gemessen an den Clips
## (gymnastikschuh, golem_bewegung_niedlich_sitzen.mjs) gegen feet_point (den Ursprung des
## Modells; die Mitte der ruhenden Schuhe liegt 0,03 davor); das Spiel skaliert sie wie das Modell
## (model_scale() x size_factor()). Wer einen Clip aendert, misst sie nach.
## Ruhender Schuh: seine Mitte so weit neben feet_point, seine Ferse so weit dahinter.
const GOLEM_SIT_FOOT_SIDE: float = 0.245
const GOLEM_SIT_HEEL_BACK: float = 0.16
## 1. Fuss-Stampfer (links/rechts): Aufschlag, wo der Schuh im Clip landet (seine Mitte
## so weit aussen / vorn gegen die Ruhelage); Kreis mit diesem Anteil des Handschlag-
## Radius ("Bereich mittel", Vorschlag), der nicht hinter die Ferse des ruhenden Schuhs
## reicht. Schnell wie der gebueckte Handschlag (Ausholen, Abklingzeit), Schaden und
## Zielzahl wie der Handschlag.
const GOLEM_SIT_STOMP_LAND: Vector2 = Vector2(0.18, 0.41)
const GOLEM_SIT_STOMP_RADIUS_SHARE: float = 0.75
## Die Sitzzonen wachsen genau mit dem Koerper (Nutzervorgabe 2026-11-18): ihre Kreise und der
## Wischer nehmen Handschlag-, Trommel-Radius und Reichweite im Stand, und die wachsen ab
## GOLEM_BODY_SCALE_HEIGHT (also immer, wenn sie sitzt) mit dem Koerper — GOLEM_BODY_*.
## 2. Bein strecken (links/rechts): eine Schneise vom Koerper (Hueftgelenk, so weit hinter
## feet_point) nach vorn bis GOLEM_SIT_KICK_TO (die gestreckte Schuhspitze liegt bei 1,03;
## Nutzervorgabe 2026-11-17: "muss laenger sein, aber nicht uebertreiben" — gut halb so
## weit noch einmal darueber hinaus), so breit wie das Bein, so weit neben der Mitte.
## Schaden, Zielzahl, Takt wie der Tritt.
const GOLEM_SIT_KICK_SIDE: float = 0.18
const GOLEM_SIT_KICK_FROM: float = 1.25
const GOLEM_SIT_KICK_TO: float = 1.6
const GOLEM_SIT_KICK_WIDTH: float = 0.3
## 3. Po-Klatscher (Po-Huepfer): Flaeche, Schaden und Zielzahl wie der Sprung, um die
## Mitte der Sitzflaeche; Abklingzeit die des Sprungs mal diesem Faktor (minimal langsamer
## als der Sprung, schneller als der Luftschlag).
const GOLEM_SIT_HOP_COOLDOWN_FACTOR: float = 1.1
## Nutzervorgabe 2026-11-18: Abklingzeit und Animation um 0,2 s laenger (beim 30-m-Golem), der
## Kreis 10 % kleiner. Die Faktoren sind beim normalen Golem mit 30 m gerechnet (Abklingzeit
## 1,21 -> 1,41 s, Animation 1,47 -> 1,67 s, also Ausholen 0,73 -> 0,83 s) und gelten fuer
## jede Groesse gleich. Der Po-Klatscher braucht kein Anvisieren: er kommt auch, waehrend sie
## sich dreht (wie der Sprung im Stand).
const GOLEM_SIT_HOP_SLOWER_COOLDOWN: float = 1.165
const GOLEM_SIT_HOP_SLOWER_ANIM: float = 1.136
const GOLEM_SIT_HOP_AREA_FACTOR: float = 0.9
## 4. Doppelstampfer: Kreis des Trommelns um eine Stelle so weit vor feet_point (negativ:
## dahinter; Nutzervorgabe 2026-11-17: "geht zu weit nach vorn, weiter nach hinten" —
## vorher 0,30 vor, an der Landestelle der Schuhe), mit diesem Anteil des Radius;
## Zielzahl, Takt und Schaden wie das Trommeln.
const GOLEM_SIT_DOUBLE_STOMP_LAND: float = -0.10
const GOLEM_SIT_DOUBLE_STOMP_AREA_FACTOR: float = 0.9
## 5. Arm-Wischer (links/rechts): ein Kegel neben ihr auf seiner Seite, von der Mitte der
## Sitzflaeche aus, Reichweite reach(), von so viel Grad hinter der Querrichtung (etwas
## hinter den Ruecken) nach vorn bis zum Becken: hoechstens GOLEM_SIT_WIPE_FRONT (Meter
## des 4-m-Modells) vor der Sitzmitte (Nutzerhinweis 2026-11-17: vorher reichte er bis zu
## den Beinen). Schaden und Zielzahl wie der Luftschlag, schnell wie der gebueckte Handschlag.
const GOLEM_SIT_WIPE_FRONT: float = 0.2
## ... und die vordere Grenze ist um so viel Grad nach vorn geneigt (Nutzervorgabe 2026-11-18:
## "kann 5 Grad weiter nach vorn reichen"): je Meter nach aussen tan(5 Grad) weiter vorn.
const GOLEM_SIT_WIPE_FRONT_DEG: float = 5.0
const GOLEM_SIT_WIPE_BACK_DEG: float = 30.0
## 6. Handstampfer hinten (Doppelklatscher): Kreis des Trommelns um jede Hand, aber nur
## hinter der Mitte der Sitzflaeche (Rueckenbereich); Schaden und Zielzahl wie das
## Trommeln, Abklingzeit die des Trommelns mal diesem Anteil (zwischen den schnellen
## Einzelangriffen und dem Trommeln; Nutzerentscheidung).
const GOLEM_SIT_CLAP_COOLDOWN_SHARE: float = 0.83
## Radius seiner Kreise: dieser Anteil des Trommel-Radius (Nutzervorgabe 2026-11-17: um 15 %
## kleiner).
const GOLEM_SIT_CLAP_AREA_FACTOR: float = 0.85
## Im Sitzen greift es sich leichter an (Nutzervorgabe 2026-11-17): alle Sitzangriffe ausser
## dem Handstampfer hinten kommen um diesen Faktor schneller wieder (Abklingzeit x 0,9) und
## haben dafuer um diesen Faktor kleinere Zielbereiche (Radien, Kegel-Reichweite, Breite der
## Bein-Schneisen; deren Laenge haengt an Huefte und Schuhspitze). Die Zielzahl bleibt.
const GOLEM_SIT_COOLDOWN_FACTOR: float = 0.9
const GOLEM_SIT_AREA_FACTOR: float = 0.9
## Die grossen Sitzangriffe (Po-Huepfer, Doppelklatscher, Doppelstampfer) sind
## Flaechenangriffe: sie kommen erst in Frage, wenn sie mindestens so viele Feinde
## treffen (Vorschlag).
const GOLEM_SIT_BIG_MIN_TARGETS: int = 3
## DREHEN IM SITZEN: erreicht keines ihrer Glieder einen Feind, dreht sie sich zum
## naechsten in ihrem Aggro-Radius, wenn er mehr als GOLEM_SIT_TURN_MIN_DEG neben ihrer
## Blickrichtung liegt — mit GOLEM_SIT_TURN_SHARE ihrer Drehrate im Stand, um den Po;
## fertig bis auf GOLEM_SIT_TURN_DONE_DEG. Waehrend sie sich dreht, greift sie nicht an
## (Vorschlaege; die Drehrate hat der Nutzer am 2026-11-17 halbiert, vorher 0,25).
const GOLEM_SIT_TURN_SHARE: float = 0.125
## Seit 2026-11-18 (Nutzer) gilt GOLEM_SIT_TURN_SHARE nur noch bei GOLEM_SIT_MIN_HEIGHT (30 m:
## 41 Grad/s). Von dort faellt die Sitz-Drehrate linear in der Koerperhoehe auf
## GOLEM_SIT_TURN_RATE_AT_MAX_DEG bei GOLEM_MAX_HEIGHT (80 m: 13 statt 9,1 Grad/s) und mit derselben
## Neigung weiter, bis GOLEM_SIT_TURN_RATE_MIN_DEG (ab rund 86 m). Im Stand bleibt alles wie es war.
const GOLEM_SIT_TURN_RATE_AT_MAX_DEG: float = 13.0
const GOLEM_SIT_TURN_RATE_MIN_DEG: float = 9.5
const GOLEM_SIT_TURN_MIN_DEG: float = 20.0
const GOLEM_SIT_TURN_DONE_DEG: float = 3.0
## Drehen fuer einen besseren Angriff (Nutzervorgabe 2026-11-18): die Wahl rechnet auch die Plaene
## anderer Blickrichtungen (GOLEM_SIT_TURN_PLAN_HEADINGS Richtungen rundum, mindestens
## GOLEM_SIT_TURN_MIN_DEG daneben) und rechnet die Drehzeit wie im Stand als Vorlauf an, verteilt auf
## GOLEM_SIT_TURN_PLAN_ATTACKS Angriffe. Ist ein gedrehter Plan mehr wert als der jetzige, dreht sie
## sich. Je Ueberlegung (alle 0,25 s) werden GOLEM_SIT_TURN_PLAN_PER_THINK Richtungen gerechnet, eine
## Runde dauert also rund 1 s (Rechenzeit); waehrenddessen greift sie normal an.
const GOLEM_SIT_TURN_PLAN_ATTACKS: int = 3
## Gegen grundloses Hin- und Herdrehen (Bugmeldung 2026-11-18): ein gedrehter Plan muss mindestens so viel
## mehr bringen (mit der Drehzeit schon eingerechnet).
const GOLEM_SIT_TURN_PLAN_MARGIN: float = 1.2
const GOLEM_SIT_TURN_PLAN_HEADINGS: int = 16
const GOLEM_SIT_TURN_PLAN_PER_THINK: int = 4
## TERRAIN BEIM SITZEN UND DREHEN (Nutzervorgabe 2026-11-18): Fuesse und Haende muessen auf Boden aufsetzen
## (kein Void), und von der Sitzmitte bis zu jedem Aufsetzpunkt darf keine Klippe liegen, die sie beim
## Laufen nicht nehmen koennte (Golem.giant_line_clear, GOLEM_GIANT_STEP_SHARE); Wasser zaehlt nicht.
## Sie setzt sich nur so hin; im Sitzen dreht sie sich nur ueber Richtungen, in denen das gilt (geprueft alle
## GOLEM_SIT_TURN_SAMPLE_DEG Grad) — notfalls den laengeren Weg herum; ist die Richtung gar nicht erreichbar,
## dreht sie sich nicht dorthin.
const GOLEM_SIT_TURN_SAMPLE_DEG: float = 10.0
## STRECKEN BEIM WACHSEN (Nutzer 2026-11-16): bei jedem Stufenaufstieg und jedem
## Wachstumsschritt nach Stufe 7 reckt sich der Golem einmal (Clip "grow", Sound
## "golem_grow"). Das kostet GOLEM_GROW_TIME Sekunden, in denen er weder
## angreift noch laeuft; er steht danach (aus der gebueckten Haltung richtet er
## sich dabei auf) und darf sofort weiter angreifen — auch sich sofort wieder
## buecken. Eine laufende Angriffsanimation wird vorher zu Ende gespielt, und
## solange das Strecken aussteht, beginnt er keinen neuen Angriff.
## Seit 2026-11-16 (Nutzer) eine ganze Sekunde statt einer halben; der Clip ist
## ebenso lang (Golem.GROW_CLIP_LENGTH).
const GOLEM_GROW_TIME: float = 1.0
## ANGRIFFSWAHL NACH SCHADEN (Nutzer 2026-11-16, ersetzt die festen Zielzahlen
## 3 / 5 / 2): fuer Tritt, Handschlag und Trommeln wird gerechnet, was der Angriff
## JETZT treffen wuerde (dieselbe Flaeche, dieselbe Zielobergrenze wie beim
## Aufschlag) —
##   Wert = Summe ueber die getroffenen Einheiten von min(Schaden, deren Leben)
##          + GOLEM_STRUCTURE_VALUE je getroffenem Gebaeude/Fahrzeug
##   Zeit = Abklingzeit des Angriffs
##          + Haltungswechsel / GOLEM_STANCE_PLAN_ATTACKS, wenn er dafuer die
##            Haltung wechseln muesste (der Wechsel lohnt sich ueber mehrere
##            Angriffe, deshalb nur anteilig)
## und der Angriff mit dem hoechsten Wert / Zeit gewinnt. Gleichstand: der Angriff
## der aktuellen Haltung, sonst der Tritt. "min(Schaden, Leben)" heisst: gegen
## fast tote Ziele zaehlt kein Ueberschaden — dort gewinnt der schnelle
## Handschlag, gegen gesunde das staerkere Trommeln.
## Ein Gebaeude oder Fahrzeug nimmt je Angriff eine Stufe, egal von welchem; es
## zaehlt deshalb fuer alle gleich viel (etwa ein Einheitentreffer).
##
## PLAENE (2026-11-16, mit dem Sprung): dieselbe Rechnung, als Plan gelesen —
## "Einleitung + GOLEM_STANCE_PLAN_ATTACKS Angriffe", gewertet nach Schaden je
## Sekunde ueber den ganzen Plan:
##   ohne Einleitung:   der Angriff der aktuellen Haltung (Wert / Abklingzeit)
##   Haltungswechsel:   kostet die Wechselzeit und bringt nichts; danach die
##                      Angriffe der anderen Haltung (das ist die Formel oben)
##   SPRUNG (stehend):  kostet seine Abklingzeit und bringt seinen eigenen
##                      Schaden; danach ist sie gebueckt und schlaegt Handschlag
##                      oder Trommeln — oder sie richtet sich auf (Abklingzeit
##                      bzw. Clip + Wechselzeit, je nachdem was laenger ist) und
##                      tritt weiter.
## Der Sprung wird nur erwogen, wenn er selbst etwas trifft (Golem.stomp_plan_value).
const GOLEM_STRUCTURE_VALUE: float = 30.0
const GOLEM_STANCE_PLAN_ATTACKS: int = 3
## Abklingzeit des Handschlags bei Startgroesse (1,35 -> 1,25 s, Nutzer
## 2026-11-16). Sie waechst mit der Groesse im selben Verhaeltnis wie der normale
## Takt (GOLEM_STRIKE_COOLDOWN 1,8 s -> 4 s bei 100 m, der Handschlag also 2,78 s).
const GOLEM_SLAM_COOLDOWN: float = 1.25
## TRITT (kick): ein Fussballtritt nach vorn — Schaden in einer SCHNEISE:
## GOLEM_KICK_WIDTH breit, von der Riesin GOLEM_KICK_LENGTH nach vorn (9 m2,
## weniger als die Haelfte des Handschlags). Dafuer mehr Schaden und VIEL
## Rueckstoss: JEDER Ueberlebende fliegt in Trittrichtung davon.
## 2026-11-15 (Nutzer): die Schneise reicht auch nach HINTEN — das Bein holt aus.
## Vorn 15 % kuerzer (5,0 -> 4,25 m), dafuer GOLEM_KICK_BACK_SHARE (70 %) der
## vorderen Laenge auch hinter ihr: 1,8 x 7,2 m = 13 m2. Wer hinten getroffen
## wird, fliegt nach hinten weg.
const GOLEM_KICK_WIDTH: float = 1.8
const GOLEM_KICK_LENGTH: float = 4.25
const GOLEM_KICK_BACK_SHARE: float = 0.7
const GOLEM_KICK_DAMAGE: int = 45
const GOLEM_KICK_WINDUP: float = 0.5
## Wurf des Tritts (waagerecht / senkrecht, m/s): dreimal so weit wie der Wurf
## des Handschlags (GOLEM_LIFT_PUSH). Wer geworfen wird, entscheidet seit
## 2026-11-16 die Groesse (GOLEM_KNOCK_*).
const GOLEM_KICK_PUSH: float = 9.0
const GOLEM_KICK_UP: float = 5.5
## 2,0 -> 1,8 s (Nutzervorgabe 2026-09-09). Gilt fuer beide Angriffe.
const GOLEM_STRIKE_COOLDOWN: float = 1.8
## RUECKSTOSS NACH GROESSE (Nutzervorgabe 2026-11-16, ersetzt "Tritt wirft jeden,
## Handschlag 30 % Hochwirbeln / 30 % Rollen"): ob ein Ueberlebender geworfen oder
## gerollt wird, haengt an der KOERPERHOEHE. Unter GOLEM_KNOCK_MIN_HEIGHT (8 m) bei
## allem 0 %. Ab 8 m steigt jede Chance stufenweise — die erste Stufe gilt ab genau
## 8 m, jede weitere nach ihrer Schrittweite:
##   Tritt wirft         +10 % je 5 m   (8 m 10 %, 13 m 20 % ... ab 53 m jeden)
##   Handschlag wirft     +8 % je 10 m  (8 m 8 %, 18 m 16 % ... ab 48 m 40 %, Grenze)
##   Handschlag rollt     +8 % je 10 m  (ebenso, Grenze 40 %)
##   Trommeln             wirft nie; rollt +8 % je 10 m, ohne eigene Grenze
##                        (98 m 80 %, ab 128 m jeden — der Daemonengolem)
##   Sprung               wirft und rollt nie (wie bisher)
## Beim Handschlag wird EINMAL gewuerfelt: unter der Wurfchance fliegt das Opfer,
## darueber bis Wurf + Roll rollt es, sonst nimmt es nur den Schaden. Beim
## Trommeln gilt das nur fuer den letzten der drei Schlaege (wie bisher). Wie weit
## geworfen und gerollt wird, bleibt fest (GOLEM_KICK_PUSH/_UP, GOLEM_LIFT_PUSH/_UP,
## GOLEM_ROLL_DURATION/_SPEED). Golem.knock_chance rechnet die Treppe.
const GOLEM_KNOCK_MIN_HEIGHT: float = 8.0
const GOLEM_KICK_THROW_STEP_M: float = 5.0
const GOLEM_KICK_THROW_PER_STEP: float = 0.10
const GOLEM_KICK_THROW_MAX: float = 1.0
const GOLEM_SLAM_LIFT_STEP_M: float = 10.0
const GOLEM_SLAM_LIFT_PER_STEP: float = 0.08
const GOLEM_SLAM_LIFT_MAX: float = 0.4
const GOLEM_SLAM_ROLL_STEP_M: float = 10.0
const GOLEM_SLAM_ROLL_PER_STEP: float = 0.08
const GOLEM_SLAM_ROLL_MAX: float = 0.4
const GOLEM_DRUM_ROLL_STEP_M: float = 10.0
const GOLEM_DRUM_ROLL_PER_STEP: float = 0.08
const GOLEM_DRUM_ROLL_MAX: float = 1.0
## Wurfstaerke des Handschlags (waagerecht / senkrecht, m/s) — deutlich schwerer
## als der Feuerkrieger-Uppercut (1,2 / 3,0).
const GOLEM_LIFT_PUSH: float = 3.0
const GOLEM_LIFT_UP: float = 4.5
const GOLEM_ROLL_DURATION: float = 1.0
const GOLEM_ROLL_SPEED: float = 4.0
## Gebaeudestufen je Angriff auf jedes feindliche Gebaeude in der Wirkflaeche
## (Handschlag und Tritt gleich).
const GOLEM_BUILDING_STAGES: int = 1
## GEBAEUDESCHADEN DER GOLEMS (Nutzervorgabe 2026-11-18, alle Angriffe aller Golems, im Stand und im Sitzen):
## nicht mehr eine Zerstoerungsstufe je Treffer, sondern Lebenspunkte wie bei allen anderen Angreifern — die
## Stufe faellt erst, wenn genug Schaden beisammen ist. Ein Treffer nimmt einem Gebaeude so viel, wie er einer
## Einheit naehme, mal diesem Anteil (abgerundet, mindestens 1); das Trommeln mit jedem seiner drei Schlaege.
## In der Wahl zaehlt ein Gebaeude mit diesem Schaden (hoechstens seinen Restlebenspunkten) statt pauschal
## GOLEM_STRUCTURE_VALUE. Das Trampeln des Giganten bleibt bei einer Stufe je GOLEM_TRAMPLE_BUILDING_INTERVAL.
const GOLEM_BUILDING_DAMAGE_SHARE: float = 0.5
const GOLEM_LIFETIME: float = 180.0
## 3 -> 6 s nach dem ersten Spieltest.
const GOLEM_LIFE_PER_KILL: float = 6.0
## Je Kill heilt der Golem um GOLEM_HP_PER_KILL (Nutzervorgabe 2026-09-09) UND
## seine Lebensobergrenze steigt um GOLEM_MAX_HP_PER_KILL (2026-11-15) — bis
## hoechstens GOLEM_MAX_HP_CAP (flat 1000, Nutzervorgabe; nach 40 Kills erreicht,
## auf Stufe 7 gilt sie in jedem Fall). Nach Stufe 7 hebt jeder WACHSTUMSSCHRITT
## sie um GOLEM_GROWTH_MAX_HP (2026-11-17: 18 statt 7, am 80-m-Ende 1378). Die Obergrenze GILT: Kill-Heilung und
## Dauerheilung enden an ihr — sonst heilte er sich passiv unendlich hoch.
## Als Kill zaehlt auch ein vom Golem zerstoertes GEBAEUDE.
const GOLEM_HP_PER_KILL: int = 10
const GOLEM_MAX_HP_PER_KILL: int = 5
const GOLEM_MAX_HP_CAP: int = 1000
const GOLEM_GROWTH_MAX_HP: int = 18
## Der AUSGEWACHSENE Golem (80 m) heilt noch einmal so viel Leben je Sekunde
## mehr (Nutzer 2026-11-16: 21 -> 24).
const GOLEM_FULL_SIZE_REGEN: float = 3.0
## STUFEN (Nutzervorgabe 2026-11-15): der Golem beginnt auf Stufe 0 und steigt
## nach GOLEM_LEVEL_KILLS Kills je Stufe auf (s. dort), bis Stufe
## GOLEM_FINAL_BONUS_LEVEL (6). Je Stufe:
##   + GOLEM_LEVEL_LIFETIME Sekunden Lebenszeit (einmalig beim Aufstieg),
##   + GOLEM_LEVEL_REGEN Leben je Sekunde Dauerheilung (Stufe 1: 3/s, Stufe 6: 18/s)
##     bis zur Lebensobergrenze,
##   GOLEM_LEVEL_GROWTH groesser als auf der Stufe davor (aufgezinst: 1,2 hoch
##     Stufe — Stufe 6 ist das 2,99-Fache, 15,7 m),
##   GOLEM_LEVEL_REACH_GROWTH mehr Reichweite, Handschlag-Radius und Schneise als
##     auf der Stufe davor (aufgezinst: 1,1 hoch Stufe — Stufe 6: 1,77-fach).
##     Bewusst langsamer als die Koerpergroesse (Nutzervorgabe),
##   + GOLEM_LEVEL_DAMAGE Schaden auf Handschlag, Tritt und Trampeln.
## Tempo: GOLEM_SPEED * Wurzel(Groessenfaktor) — die Schritte werden laenger, die
## Schrittfolge etwas ruhiger (Stufe 6: 6,05 m/s).
## DIE ENDBONI gibt es ab Stufe GOLEM_FINAL_BONUS_LEVEL (6): keine
## Lebenszeitbegrenzung mehr, und er jagt Luftschiffe (s. GOLEM_SWAT_WINDUP).
##
## STUFE 7, der GIGANT (Nutzervorgabe 2026-11-15, 2026-11-17 neu): 20 weitere
## Kills nach Stufe 6, also 62 insgesamt. Der Koerper waechst noch einmal um
## GOLEM_TOP_LEVEL_GROWTH (20 %: 3,58-fach, 16,9 m), Reichweite und Wirkflaechen
## um GOLEM_TOP_LEVEL_REACH_GROWTH (10 %: 1,95-fach), die Dauerheilung wie gehabt
## um 3/s (21/s), der Schaden wie jede Stufe um +5 (+35), das Tempo folgt der
## Groesse. Und: wo der Gigant steht, wird der Boden EBEN — auf die tiefste Stelle
## unter seinem Koerper (s. GOLEM_FLATTEN_*). (Bis 2026-11-17: 45 Kills, +50 %
## Koerper, +25 % Flaechen, kein Schaden.)
## Kills, die jede Stufe ZUSAETZLICH zur vorigen braucht (Index 0 = Stufe 1).
## Nutzervorgabe 2026-11-15 (vorher 6 je Stufe und 50 fuer Stufe 7): 5, 6, 7, -, 8,
## 9, 45. Fuer Stufe 4 war kein Wert genannt — angenommen ist 7 (wie Stufe 3).
## Stufe 7 seit 2026-11-17 nach 20 statt 45 Kills.
## Aufsummiert: Stufe 1 nach 5, 2 nach 11, 3 nach 18, 4 nach 25, 5 nach 33,
## 6 nach 42, 7 nach 62 Kills.
const GOLEM_LEVEL_KILLS: Array[int] = [5, 6, 7, 7, 8, 9, 20]
## ZIELOBERGRENZE (Nutzervorgabe 2026-11-15): gegen dichte Nahkampfhaufen
## eskalierte der Flaechenschaden. Jeder Schadenstick des Golems — Handschlag,
## Tritt, und beim Trampeln je Sekunde — trifft hoechstens so viele Ziele
## (Index = Stufe; fuer Stufe 6 war kein Wert genannt, angenommen 8 wie davor
## und danach). Nach Stufe 7 kommt alle GOLEM_GROWTH_STEPS_PER_TARGET
## Wachstumsschritte eines dazu (2026-11-17: jeder Schritt eines, 80 m: 29). Einheiten gehen vor Fahrzeugen und
## Gebaeuden, die naechsten zuerst; das Ziel, das er gerade angreift, wird immer
## getroffen und zaehlt mit.
const GOLEM_MAX_TARGETS: Array[int] = [5, 6, 6, 6, 7, 8, 8, 8]
## ZIELZAHL JE ANGRIFF (Nutzer 2026-11-16, ersetzt GOLEM_KICK_TARGETS_LESS "der
## Tritt trifft eines weniger"): GOLEM_MAX_TARGETS ist die GRUNDZAHL. Jeder
## Angriff trifft einen Anteil davon (Prozent, ABGERUNDET, mindestens 1):
##   Handschlag und Trampeln  100 %   (Stufe 0-7: 5 / 6 / 6 / 6 / 7 / 8 / 8 / 8)
##   Tritt                     60 %   (40 % weniger:  3 / 3 / 3 / 3 / 4 / 4 / 4 / 4)
##   Trommeln                 125 %   (je Schlag:     6 / 7 / 7 / 7 / 8 / 10 / 10 / 10)
##   Sprung                   200 %   (              10 / 12 / 12 / 12 / 14 / 16 / 16 / 16;
##                                     doppelt so viele wie das Trampeln, Nutzer 2026-11-16 —
##                                     vorher 150 %)
## Golem.max_targets_of(). Bei 80 m (Grundzahl 29): 17 / 36 / 58.
const GOLEM_TARGET_PERCENT_KICK: int = 60
const GOLEM_TARGET_PERCENT_DRUM: int = 125
const GOLEM_TARGET_PERCENT_STOMP: int = 200
const GOLEM_GROWTH_STEPS_PER_TARGET: int = 1
const GOLEM_MAX_LEVEL: int = 7
const GOLEM_FINAL_BONUS_LEVEL: int = 6
const GOLEM_TOP_LEVEL_GROWTH: float = 0.2
const GOLEM_TOP_LEVEL_REACH_GROWTH: float = 0.1
## Einebnen unter dem Giganten (Stufe 7): alle GOLEM_FLATTEN_INTERVAL Sekunden
## wird geprueft; liegt unter seinem Koerper mehr als GOLEM_FLATTEN_MIN_SPREAD
## Hoehenunterschied, senkt sich alles dort auf die tiefste Stelle. Ringsum
## bleibt eine BEGEHBARE Boeschung stehen (hoechstens GOLEM_FLATTEN_SLOPE Meter
## Anstieg je Meter), sonst graebe er sich in eine Grube mit Steilwaenden ein,
## aus der er selbst nicht mehr herauskaeme. Es wird nur gesenkt, nie gehoben.
## Seit 2026-11-18 (Nutzer) ebnen ALLE Golems erst ab GOLEM_FLATTEN_MIN_HEIGHT Koerperhoehe ein
## (Golem ab 31,3 m statt Stufe 7, Daemon ab 32 m, Genesis ab 33 m statt Stufe 4).
const GOLEM_FLATTEN_MIN_HEIGHT: float = 30.0
const GOLEM_FLATTEN_INTERVAL: float = 0.6
const GOLEM_FLATTEN_MIN_SPREAD: float = 0.25
const GOLEM_FLATTEN_SLOPE: float = 1.0
const GOLEM_FLATTEN_DURATION: float = 0.5
## ...und ALLMAEHLICH (Nutzer 2026-11-15: schlagartig war es zu stark): der
## Boden sinkt hoechstens so viele Meter je Sekunde. Ein 2 m hoher Buckel unter
## ihm braucht damit 20 s; wer nur durchlaeuft, hinterlaesst kaum eine Spur.
## 0,25 -> 0,1 m/s (Nutzer, selber Tag: noch langsamer).
const GOLEM_FLATTEN_RATE: float = 0.1
## Das Einebnen senkt NIE unter die Wasserlinie: tiefer als so viele Meter ueber
## TerrainData.SEA_LEVEL geht kein Punkt (Land bleibt Land, niemand ertrinkt
## durch den Giganten), und Gelaende, das schon darunter liegt (Meeresboden),
## wird gar nicht angefasst — weder gesenkt noch gehoben.
const GOLEM_FLATTEN_ABOVE_WATER: float = 0.15
## Ein Golem (auch der Daemon) ertrinkt bei Gelaendeaenderungen erst, wenn der
## Boden unter ihm so viele Meter unter der Wasserlinie liegt - tiefer, als eine
## begehbare Uferzelle je reicht (0,75 m). Am Ufer entlangwaten ist damit sicher,
## Land unter ihm versenken (Sink: 3 m) toetet ihn weiter (Bugfix 2026-11-16).
const GOLEM_DROWN_DEPTH: float = 0.8
## Zielradius des Golems (und des Daemons) als Anteil am Radius seines Auswahlkreises
## (Nutzervorgabe 2026-11-16): Angreifer sind in Reichweite, sobald sie ihre Reichweite
## vom RAND dieses Kreises entfernt stehen, statt sich unter ihm zu draengen. Der
## Gigant ebnet den Boden nur noch in diesem Kreis ein.
const GOLEM_TARGET_RADIUS_SHARE: float = 0.5
## Mehrere Golems mit einem Bewegungsbefehl bekommen Zielpunkte, die um die Summe
## ihrer Koerperradien plus diesen Rand (m) auseinanderliegen (Bugfix 2026-11-16:
## die festen Packabstaende legten die Ziele ineinander).
const GOLEM_SLOT_MARGIN: float = 0.5
## WACHSTUM NACH STUFE 7 (Nutzervorgabe 2026-11-15, 2026-11-17 neu): der Gigant
## waechst weiter, ohne eine neue Stufe — alle GOLEM_GROWTH_KILLS (20) Kills ein
## Schritt, der Koerper je Schritt GOLEM_GROWTH_SIZE (8 %) groesser als davor
## (aufgezinst; bis 2026-11-17 alle 15 Kills 3 %).
## Flaechen (Handschlag-, Trommel- und Schneisenbreite) und Tempo wachsen viel
## langsamer als der Koerper, als POTENZ seines Wachstums seit Stufe 7:
##   Flaechen  x (Groesse / Stufe-7-Groesse) ^ GOLEM_GROWTH_AREA_EXPONENT (je 8 %
##             Koerper 1,96 %; das Verhaeltnis der frueheren 0,75 % je 3 %),
##   Tempo     x (Groesse / Stufe-7-Groesse) ^ GOLEM_GROWTH_SPEED_EXPONENT (je
##             Schritt 0,65 %; frueher 0,25 % je 3 %).
## Dieselben Potenzen gelten fuer Daemonen- und Genesisgolem ueber die ganze Groesse.
## Je Schritt +GOLEM_GROWTH_MAX_HP Lebensobergrenze und +1 Ziel; Dauerheilung und
## Schaden steigen nicht mehr. Schluss ist bei GOLEM_MAX_HEIGHT (80 m, Nutzer
## 2026-11-17, vorher 100 m) nach 21 Schritten = 420 Kills ueber Stufe 7 (482
## insgesamt); dort gibt es die Haertung und +3 Leben/s (s. is_full_size).
const GOLEM_GROWTH_KILLS: int = 20
const GOLEM_GROWTH_SIZE: float = 0.08
const GOLEM_GROWTH_AREA_EXPONENT: float = 0.2527848   # = log(1,0075) / log(1,03)
const GOLEM_GROWTH_SPEED_EXPONENT: float = 0.0844716  # = log(1,0025) / log(1,03)
const GOLEM_MAX_HEIGHT: float = 80.0
const GOLEM_LEVEL_LIFETIME: float = 20.0
const GOLEM_LEVEL_REGEN: float = 3.0
const GOLEM_LEVEL_GROWTH: float = 0.2
const GOLEM_LEVEL_REACH_GROWTH: float = 0.1
const GOLEM_LEVEL_DAMAGE: int = 5
## AB STUFE 1 ignoriert der Golem die Kollision mit Einheiten (er laeuft durch sie
## hindurch, niemand wird von ihm weggeschoben) und TRAMPELT: jeder Feind unter
## seinem Koerper nimmt den Trampelschaden (aus der Groesse, s. u.), solange der Golem
## sich schneller als GOLEM_TRAMPLE_MIN_SPEED bewegt — im Stehen nie. Dasselbe
## Opfer hoechstens alle GOLEM_TRAMPLE_INTERVAL Sekunden.
## Trampelschaden seit 2026-11-15 (Nutzer) aus der GROESSE: Koerperhoehe in
## Metern / GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE, gerundet, mindestens 1. Seit
## 2026-11-17 25 bei 80 m (vorher 20 bei 100 m; zwischendurch 40): Stufe 1 mit
## 5,7 m: 2; Stufe 6 mit 14,1 m: 4; Stufe 7 mit 16,9 m: 5. Kein Stufenbonus obendrauf.
const GOLEM_TRAMPLE_HEIGHT_PER_DAMAGE: float = 3.2
## Ab der hoechsten Stufe trampelt der Gigant auch GEBAEUDE nieder: jedes
## feindliche Gebaeude unter seinem Koerper verliert alle
## GOLEM_TRAMPLE_BUILDING_INTERVAL Sekunden eine Zerstoerungsstufe (wie unter dem
## Tornado), solange er laeuft. Seit 2026-11-16 (Nutzer: der Gebaeudeschaden beim
## Trampeln war zu hoch) alle 4 statt alle 2 Sekunden — die halbe Schadensrate.
## Fahrzeuge behalten ihre 2 s (GOLEM_TRAMPLE_VEHICLE_INTERVAL).
const GOLEM_TRAMPLE_BUILDING_INTERVAL: float = 4.0
const GOLEM_TRAMPLE_VEHICLE_INTERVAL: float = 2.0
## GERADE WEGE ab der hoechsten Stufe (Nutzer 2026-11-15): der Gigant laeuft in
## geraden Linien — Gebaeude, Baeume und normales Gelaende (auch Haenge, die fuer
## alle anderen zu steil sind) halten ihn nicht mehr auf, kein Zickzack ums
## Hindernis. Was bleibt: das Meer, der Kartenrand und GROSSE Klippen — eine Stufe
## von mehr als GOLEM_GIANT_STEP_SHARE seiner Koerperhoehe auf einem Meter Weg
## (Stufe 7 mit 21 m: 4,3 m; zum Vergleich: fuer Fusseinheiten ist bei 1,5 m
## Schluss). Ist die Luftlinie versperrt, wird der normale Weg gesucht und
## danach begradigt.
const GOLEM_GIANT_STEP_SHARE: float = 0.2
## GOLEMS UNTEREINANDER (Nutzer 2026-11-16): sie koennen nicht ineinander stehen.
## Zwei Golems — egal welcher Stufe und welchen Stamms — halten mindestens die
## Summe ihrer Koerperradien mal GOLEM_BODY_GAP Abstand; ueberlappen sie, schieben
## sie sich auseinander (der kleinere weicht staerker aus). Die Kollision mit
## normalen Einheiten bleibt ab Stufe 1 ausgeschaltet.
## 1,0 -> 0,9 (Nutzervorgabe 2026-11-18: der Kollisionsradius der Golems untereinander 10 % kleiner).
const GOLEM_BODY_GAP: float = 0.9
## KLEINE GOLEMS AN GROSSEN (Nutzervorgabe 2026-11-18): reicht der kleinere hoechstens bis
## GOLEM_KNEE_HEIGHT_SHARE der Hoehe des groesseren (bis zu dessen Knien), zaehlt vom grossen nur der
## Beinbereich: GOLEM_LEG_RADIUS_SHARE seines Koerperradius. Die Regel gilt je Paar (symmetrisch) fuer den
## Abstand, die Zielplaetze und das Ausweichen. Beide Werte sind Schaetzwerte der Proportionen.
const GOLEM_KNEE_HEIGHT_SHARE: float = 0.28
const GOLEM_LEG_RADIUS_SHARE: float = 0.6
## WASSER AB 30 m (Nutzervorgabe 2026-11-18, alle Golems): ab dieser Koerperhoehe ertrinken sie nicht
## mehr und laufen ueber Wasser — auf dem Meeresboden (Insel bis 2 m, Seen bis 8 m tief; die Klippenregel
## des geraden Wegs gilt dort wie an Land). Gerade Linien ueber Wasser nimmt jeder Golem ab dieser Hoehe;
## die normale Wegsuche kennt weiter nur Land (ein Umweg ueber Wasser wird nicht gesucht).
const GOLEM_WATER_WALK_HEIGHT: float = 30.0
## BEWEGUNGSFREIHEIT (Nutzer 2026-11-17): ist der Zielort eines Bewegungsbefehls von
## anderen Golems belegt (ihr Koerper passte dort nicht hin), gilt sie als
## angekommen, sobald sie bis auf GOLEM_BLOCKED_ARRIVE_BODIES eigene Koerperradien an
## die Stelle heran ist, an der sie den Blockierer beruehrt — statt ihn wegzuschieben.
const GOLEM_BLOCKED_ARRIVE_BODIES: float = 2.0
## Beruehrung zweier Golems: Abstand hoechstens Summe der Koerperradien plus dieser
## Anteil des eigenen Radius (mindestens GOLEM_CONTACT_MIN Meter).
const GOLEM_CONTACT_SHARE: float = 0.25
const GOLEM_CONTACT_MIN: float = 0.3
## AUSWEICHEN (Nutzer 2026-11-17): ein untaetiger grosser Koerper (Golem, Katapult,
## Feuerramme, Luftschiff — Luftschiffe nur unter sich), der einem laufenden im Weg
## steht, tritt zur Seite (quer zu dessen Laufrichtung), sobald der bis auf
## BODY_YIELD_LOOKAHEAD seiner eigenen Koerperradien heran ist — mit
## BODY_YIELD_SPEED_SHARE seines Tempos. Nicht, wenn der Laufende genau dorthin
## will, wo er steht. Ein Fahrzeug braucht dafuer Fahrbesatzung.
const BODY_YIELD_LOOKAHEAD: float = 3.0
const BODY_YIELD_SPEED_SHARE: float = 0.6
## Wie GOLEM_BLOCKED_ARRIVE_BODIES fuer Fahrzeuge: angekommen, sobald es bis auf
## diesen Anteil seines eigenen Abstandsradius an die Beruehrungsstelle heran ist.
const VEHICLE_BLOCKED_ARRIVE_SHARE: float = 1.0
## ANLAUF IN SCHLAGDISTANZ (Nutzer 2026-11-17): muss sie zum Ziel hinlaufen (oder
## kommt sie aus der Bewegung), laeuft sie naeher heran als ihre Reichweite: bis das
## Ziel im Kreis des Handschlags liegt — Aufschlagpunkt der Haende plus dieser Anteil
## des Handschlag-Radius. Aus dem Stand greift sie weiter auf volle Reichweite an;
## steht ein anderer Golem im Weg, reicht ebenfalls die volle Reichweite.
const GOLEM_CLOSE_IN_SLAM_SHARE: float = 0.5
## REICHWEITE WAECHST MIT DEM KOERPER (Nutzer 2026-11-16): Arme und Beine werden
## mit dem Koerper laenger — bis dahin wuchs die Reichweite nur 10 % je Stufe
## (wie die Wirkflaechen) und der grosse Golem musste fast auf sein Ziel treten.
## Jetzt waechst alles, was an der GLIEDERLAENGE haengt, mit dem "Gliederfaktor"
## = Groessenfaktor hoch e, wobei e so gewaehlt ist, dass bei 100 m genau
## GOLEM_LIMB_SHARE_AT_MAX (60 %) des rein koerperproportionalen Werts
## herauskommt (e = 0,833; sanfter als 1:1, Nutzervorgabe):
##   Reichweite (Stufe 6: 7,5 m, Stufe 7: 10,5 m, 100 m: 38 m),
##   Laenge der Tritt-Schneise nach vorn und hinten,
##   Abstand des Handschlag-Aufschlagpunkts vom Koerper.
## Die GROESSE der Flaechen (Radius des Handschlags, Breite der Schneise) bleibt
## beim langsamen Wachstum von 10 % je Stufe (GOLEM_LEVEL_REACH_GROWTH).
const GOLEM_LIMB_SHARE_AT_MAX: float = 0.6
## Hoehe, an der GOLEM_LIMB_SHARE_AT_MAX und GOLEM_KICK_LENGTH_SHARE_AT_MAX gelten
## (Nutzer 2026-11-17): die alten 100 m, auch nachdem der Golem bei 80 m aufhoert
## zu wachsen — so bleiben Reichweite und Schneise der Stufen 1-6 unveraendert
## (80 m: 34,5 m Reichweite).
const GOLEM_LIMB_ANCHOR_HEIGHT: float = 100.0
## ... und der ZUWACHS daraus faellt ueber alle Stufen noch einmal 10 % staerker
## aus (Nutzer 2026-11-16): Gliederfaktor = 1 + (Groesse^e - 1) x
## GOLEM_LIMB_GROWTH_BONUS. Stufe 0 bleibt bei 3,0 m; Stufe 6: 7,9 m, Stufe 7:
## 11,2 m, 100 m: 41,6 m (statt 7,5 / 10,5 / 38,1).
const GOLEM_LIMB_GROWTH_BONUS: float = 1.1
## LAENGE DER TRITT-SCHNEISE (Nutzer 2026-11-16): sie waechst langsamer als die
## Glieder — bei 100 m ist sie GOLEM_KICK_LENGTH_SHARE_AT_MAX der Laenge, die der
## Gliederfaktor allein ergaebe (90 %: 53,0 statt 58,9 m vor, 37,2 statt 41,3 m
## zurueck). Auf Stufe 0 unveraendert; dazwischen ist der Zuwachs ueber 1 um
## denselben Anteil gekuerzt (Golem.kick_limb_factor). Die Reichweite bleibt.
const GOLEM_KICK_LENGTH_SHARE_AT_MAX: float = 0.9
## RADIUS VON HANDSCHLAG UND TROMMELN am Wachstumsende (Nutzer 2026-11-16: "kann
## auch besser skalieren, am Ende koennen da 12 m sein"). Bis Stufe 7 bleibt es
## beim langsamen Flaechenwachstum (Stufe 7: 5,8 m); in den Wachstumsschritten
## danach waechst der Radius gleichmaessig bis auf diesen Wert bei 100 m (1,4 %
## je Schritt statt 0,75 % — vorher endete er bei 8,6 m). Die Breite der
## Tritt-Schneise bleibt bei 0,75 % je Schritt.
const GOLEM_SLAM_RADIUS_AT_MAX: float = 12.0
## FLAECHEN UND REICHWEITEN WACHSEN AB 30 m GENAU MIT DEM KOERPER (Nutzervorgabe 2026-11-18,
## alle drei Golems): ab GOLEM_BODY_SCALE_HEIGHT nehmen reach_factor (Breite der Tritt-Schneise),
## slam_scale (Handschlag- und Trommel-Radius), limb_factor (Reichweite, Aufschlagpunkt der Haende)
## und kick_limb_factor (Laenge der Tritt-Schneise) die Werte des normalen Golems in seiner ersten
## Sitzgroesse (31,3 m, GOLEM_BODY_*_AT_ANCHOR), mal Koerperbreite / GOLEM_BODY_ANCHOR_WIDTH
## (Breite = Modellmassstab x Groesse). Darunter alles wie bisher. Gleiche Koerperanteile fuer alle
## drei Golems (Nutzerentscheidung): der Daemonengolem ist 25 % breiter, seine Flaechen also auch;
## Daemon und Genesis springen an der Schwelle etwas nach oben. Normaler Golem bei 80 m: Reichweite
## 40 statt 34,5 m, Handschlag-Radius 18 statt 12 m, Schneise 10,5 statt 5,2 m breit.
const GOLEM_BODY_SCALE_HEIGHT: float = 30.0
const GOLEM_BODY_ANCHOR_WIDTH: float = 8.704786
const GOLEM_BODY_REACH_FACTOR_AT_ANCHOR: float = 2.276884
const GOLEM_BODY_SLAM_SCALE_AT_ANCHOR: float = 2.706449
const GOLEM_BODY_LIMB_FACTOR_AT_ANCHOR: float = 5.215458
const GOLEM_BODY_KICK_LIMB_AT_ANCHOR: float = 4.761154
## Ab GOLEM_BODY_SCALE_HEIGHT ist die Tritt-Schneise VORN um diesen Anteil kuerzer (Nutzervorgabe
## 2026-11-18: "auf 31,3 m vorne etwas kuerzen, 5 %" — 31,3 m: 19,2 statt 20,2 m; hinten unveraendert).
const GOLEM_BODY_KICK_FRONT_SHARE: float = 0.95
## EIGENE SCHNEISE JE BEIN (Nutzervorgabe 2026-11-18, wie im Sitzen): die Schneise des Tritts liegt
## um den Abstand des Beins zur Seite versetzt — rechtes Bein (Clip kick) rechts, linkes (kick_l) links.
## Der Abstand waechst mit dem Koerper und ist so gewaehlt, dass die beiden Schneisen sich ab
## GOLEM_BODY_SCALE_HEIGHT in der Mitte genau beruehren (halbe Schneisenbreite bei 31,3 m); darunter ist
## die Schneise im Verhaeltnis breiter und sie ueberlappen (gewollt). Getreten wird mit dem Bein, das
## mehr trifft; bei Gleichstand das auf der Seite des Ziels, sonst abwechselnd. Ein Ziel genau vor ihr
## liegt in beiden Schneisen (GOLEM_KICK_LANE_SLACK).
const GOLEM_KICK_LANE_SLACK: float = 0.001
## ANGRIFFSTAKT NACH GROESSE (Nutzer 2026-11-15, ersetzt "der Takt bleibt 1,8 s"):
## die Abklingzeit waechst langsam mit dem Koerper — linear in der Koerperhoehe
## von GOLEM_STRIKE_COOLDOWN (1,8 s, Startgroesse) bis GOLEM_STRIKE_COOLDOWN_MAX
## bei 100 m (Stufe 7 mit 21 m: 2,18 s). Die Angriffsanimationen werden
## entsprechend langsamer und fuellen die Abklingzeit weiter aus.
## Nutzer 2026-11-17: 3 s bei 80 m (vorher 4 s bei 100 m; bei 80 m waren es 3,54 s).
const GOLEM_STRIKE_COOLDOWN_MAX: float = 3.0
## DREHRATE (Nutzer 2026-11-15): der Golem dreht sich nicht mehr augenblicklich.
## Sein Koerper folgt der Blickrichtung mit GOLEM_TURN_RATE (rad/s) bei
## Startgroesse, linear in der Koerperhoehe fallend bis GOLEM_TURN_RATE_FULL_SHARE
## der Feuerrammen-Drehrate bei 100 m. Seit 2026-11-16 (Nutzer) dauert die Drehung
## dort 10 % laenger: 0,7 / 1,1 = 63,6 % (1,27 rad/s: eine halbe Drehung in 2,5 s
## statt 2,2 s); dazwischen faellt die Rate weiter linear. Angegriffen wird erst, wenn er bis auf GOLEM_ATTACK_ALIGN_DEG auf
## das Ziel gedreht ist; solange er sich dreht, laeuft er langsamer (mindestens
## GOLEM_TURN_MIN_SPEED_SHARE seines Tempos), damit er nicht seitwaerts gleitet.
const GOLEM_TURN_RATE: float = 8.0
const GOLEM_TURN_RATE_FULL_SHARE: float = 0.7 / 1.1
const GOLEM_ATTACK_ALIGN_DEG: float = 25.0
const GOLEM_TURN_MIN_SPEED_SHARE: float = 0.2
## TROMMELN (Nutzer 2026-11-15): eine Variante des Handschlags — drei Schlaege
## auf den Boden, linke Hand, rechte Hand, linke Hand (Clip "drum_low", Aufschlaege
## GOLEM_DRUM_HITS Sekunden nach Beginn; aus dem Stand kommt das Buecken davor).
## Flaeche wie der Handschlag. Werte seit 2026-11-16 (Nutzer; vorher 40 Schaden
## gesamt, 1,4-fache Abklingzeit des Handschlags):
##   JEDER Schlag macht GOLEM_DRUM_HIT_DAMAGE (14, zusammen 42);
##   je Stufe bekommt jeder Schlag GOLEM_DRUM_LEVEL_DAMAGE_PER_HIT (+1) dazu,
##   ZUSAETZLICH zum normalen Stufenbonus (GOLEM_LEVEL_DAMAGE, +5 fuer den ganzen
##   Angriff, auf die drei Schlaege verteilt) — also +8 je Stufe insgesamt
##   (Stufe 6: 3 x 30 = 90);
##   die Abklingzeit ist der normale Angriffstakt (1,8 s bei Startgroesse), nicht
##   der verkuerzte der gebueckten Haltung.
## Gewaehlt wird es, wenn es mehr Schaden je Sekunde bringt als Handschlag und
## Tritt (s. GOLEM_STRUCTURE_VALUE). Hochwirbeln/Rollen, Gebaeudestufe und
## Fahrzeugtreffer gibt es nur beim LETZTEN der drei Schlaege.
## RADIUS DES TROMMELNS (Nutzer 2026-11-16): 10 % groesser als der Kreis des
## Handschlags, auf allen Stufen (Golem.ground_radius) — Mittelpunkt wie dort.
const GOLEM_DRUM_RADIUS_FACTOR: float = 1.1
const GOLEM_DRUM_HIT_DAMAGE: int = 14
const GOLEM_DRUM_LEVEL_DAMAGE_PER_HIT: int = 1
const GOLEM_DRUM_HITS: Array[float] = [0.35, 0.8, 1.25]   # aus der gebueckten Haltung (Clip drum_low)
## SPRUNG (stomp, Nutzer 2026-11-16): sie springt auf der Stelle und landet auf
## beiden Fuessen — Schaden RUNDHERUM UM SIE SELBST. Nur aus dem Stand.
##   Flaeche:  Kreis um ihre Mitte, der Trampelradius (Koerper) mal
##             GOLEM_STOMP_RADIUS_FACTOR (zwei Drittel groesser: Stufe 0 1,29 m,
##             Stufe 6 3,87 m, Stufe 7 5,80 m)
##   Schaden:  GOLEM_STOMP_TRAMPLE_MULT mal der Trampelschaden (aus der Groesse,
##             kein Stufenbonus: Stufe 0-2 2, Stufe 3-5 4, Stufe 6 6, Stufe 7 8,
##             100 m 40) — bei der LANDUNG, GOLEM_STOMP_WINDUP nach dem Ansetzen
##   Ziele:    doppelt so viele wie die Grundzahl, also wie das Trampeln
##             (GOLEM_TARGET_PERCENT_STOMP, 2026-11-16; vorher die Haelfte mehr)
##   Gebaeude: jedes in der Flaeche verliert GOLEM_STOMP_BUILDING_STAGES Stufen
##             (wie bei den anderen Angriffen; 0 = der Sprung laesst Gebaeude
##             stehen), der Gigant trifft auch Fahrzeuge. Niemand wird geworfen.
## NACH DER LANDUNG IST SIE GEBUECKT (der Clip "stomp" endet in der gebueckten
## Ruhe). Das Abfangen gehoert zum Angriff, der Schaden ist da schon gefallen.
## Danach bleibt sie unten, wenn sie von dort weiterschlagen will — oder sie
## richtet sich sofort wieder auf; das kostet die normale Zeit eines
## Haltungswechsels (Clip "crouch_up") und gehoert ebenfalls noch zum Angriff
## (die Mindestzeit der Haltung gilt dafuer nicht).
## Abklingzeit GOLEM_STOMP_COOLDOWN bei Startgroesse: genau die Laenge des Clips —
## wer unten bleibt, schlaegt gleich nach dem Abfangen weiter. Sie waechst mit der
## Groesse wie der normale Takt.
const GOLEM_STOMP_RADIUS_FACTOR: float = 5.0 / 3.0
const GOLEM_STOMP_TRAMPLE_MULT: int = 2
## (2026-11-16, Nutzer: 0,2 s schneller — vorher Landung 0,8 s, Abklingzeit 1,2 s.)
const GOLEM_STOMP_WINDUP: float = 0.6
const GOLEM_STOMP_COOLDOWN: float = 1.0
const GOLEM_STOMP_BUILDING_STAGES: int = 1
## LUFTSCHLAG NACH HOEHE (Nutzer 2026-11-15): Luftschiffe fliegen auf 10 m, schon
## der Stufe-6-Golem ist 14 m gross — ein Schlag nach OBEN passt dann nicht mehr.
## Die Animation richtet sich nach der Hoehe des Schiffs ueber seinen Fuessen,
## gemessen an seiner Koerperhoehe: darueber als GOLEM_AIR_HIGH_SHARE der Schlag
## nach oben ("swat"), darunter als GOLEM_AIR_LOW_SHARE ein Tritt, dazwischen ein
## waagerechter Schwinger ("swipe"). Wirkung und Reichweite sind dieselben.
const GOLEM_AIR_HIGH_SHARE: float = 0.8
const GOLEM_AIR_LOW_SHARE: float = 0.4
## AGGRO (Nutzer 2026-11-15: "am Ende greift der kaum noch was von sich aus an"):
## der Radius, in dem er von sich aus angreift, waechst mit dem KOERPER —
## MELEE_AGGRO_RADIUS (8 m) x Groessenfaktor, also immer rund 1,7 Koerperhoehen
## (Stufe 6: 23,9 m, Stufe 7: 35,8 m). Gedeckelt bei GOLEM_AGGRO_MAX, sonst
## reichte der Radius des 100-m-Giganten (169 m) ueber die ganze Karte.
const GOLEM_AGGRO_MAX: float = 60.0
## FAHRZEUGE ab der hoechsten Stufe (Nutzer 2026-11-15): Tritt, Handschlag und
## Trampeln treffen auch Bodenfahrzeuge, die nicht unter der eigenen Flagge
## stehen (feindliche, bemannt oder verlassen). Es gelten die Schadensstufen
## des Fahrzeugs (CrewedVehicle.take_crush_hit): Katapult sofort zerstoert,
## Feuerramme verliert eines ihrer 3 Leben. Getrampelt wird je Fahrzeug
## hoechstens alle GOLEM_TRAMPLE_VEHICLE_INTERVAL (2 s; Gebaeude seit 2026-11-16
## nur noch alle 4 s).
const GOLEM_TRAMPLE_INTERVAL: float = 1.0
const GOLEM_TRAMPLE_MIN_SPEED: float = 0.5
## AUF DER HOECHSTEN STUFE schlaegt der Golem auch nach LUFTSCHIFFEN (Nutzervorgabe
## 2026-11-15): steht ein bemanntes feindliches Luftschiff in seiner Reichweite
## (flach gemessen, dieselbe wie am Boden), holt er mit einem eigenen Schlag nach
## oben aus (Clip `swat`, Aufschlag nach GOLEM_SWAT_WINDUP). Jeder Treffer ist EIN
## Huellentreffer wie beim Katapult — AIRSHIP_HULL_HITS (2) zerstoeren das Schiff.
const GOLEM_SWAT_WINDUP: float = 0.5
## ...und er VERFOLGT sie: steht er sonst untaetig herum, laeuft er einem bemannten
## feindlichen Luftschiff im Umkreis GOLEM_AIR_CHASE_RADIUS nach — aber nur, wenn
## er eine Stelle in Schlagweite des Schiffs zu Fuss erreichen kann (gleiche
## Insel; ein Schiff ueber offenem Wasser laesst er ziehen).
const GOLEM_AIR_CHASE_RADIUS: float = 25.0
## KONTER gegen den Golem (Nutzervorgabe 2026-11-15):
##  * FEUER macht wieder vollen Schaden (15/s wie bei jeder Einheit) — weiterhin
##    ohne Panik. Das Rinnsal GOLEM_BURN_DPS gilt nur noch fuer den
##    AUSGEWACHSENEN Golem (100 m): der ist feuerresistent.
##  * BLITZ macht GOLEM_LIGHTNING_MULT-fachen Schaden (480 statt 240) — beim
##    ausgewachsenen nur den normalen.
##  * KATAPULT: ein Volltreffer (Einschlag im Koerperkreis) macht umso mehr
##    Schaden, je groesser der Golem ist: vom normalen Schockschaden (15) bei
##    Startgroesse linear bis GOLEM_SIEGE_DAMAGE_MAX kurz vor 100 m. Der
##    ausgewachsene nimmt hoechstens GOLEM_SIEGE_DAMAGE_FULL_SIZE.
const GOLEM_BURN_DPS: float = 5.0
const GOLEM_LIGHTNING_MULT: float = 2.0
const GOLEM_SIEGE_DAMAGE_MAX: int = 80
const GOLEM_SIEGE_DAMAGE_FULL_SIZE: int = 40
## Abstand, den andere grosse Koerper (Fahrzeuge, Golems) zum Golem halten
## (2,0 -> 1,5 mit dem schlanken Koerper, -> 1,125 mit der kleineren Koerperbox,
## beides 2026-11-15).
const GOLEM_SEPARATION: float = 1.0

# --- Daemonengolem (beschworene Einheit, Zauber 14, 2026-11-16) ---
## Ein zweiter Golem (Nutzervorgabe 2026-11-16, scripts/units/demon_golem.gd): die
## Figur mit den Jeansschuhen, muskuloeser und gedrungen. Er erbt alles vom Golem
## (Angriffe, Haltung, Zielwahl, Immunitaeten, Konter) und unterscheidet sich so:
##  * KEINE STUFEN, keine Lebenszeit. Er beginnt DEMON_GOLEM_START_HEIGHT (2 m)
##    klein und waechst je WACHSTUMSSTUFE um genau DEMON_GOLEM_GROWTH_HEIGHT (3 m,
##    kein Prozentwert; Nutzer 2026-11-17, vorher 1 m). Mit der 40. Stufe erreicht
##    er DEMON_GOLEM_MAX_HEIGHT (120 m, vorher 150 m) und zerfaellt; lebend wird
##    er hoechstens 119 m gross.
##  * Kills je Wachstumsstufe (Nutzervorgabe 2026-11-18): DEMON_GOLEM_GROWTH_KILLS (4), und alle
##    DEMON_GOLEM_GROWTH_KILLS_STEP (2) Stufen DEMON_GOLEM_GROWTH_KILLS_ADD (2) mehr — bis zur Stufe,
##    die ueber DEMON_GOLEM_SLOW_HEIGHT (60 m) fuehrt (20. Stufe, 62 m): Stufe 1-2 je 4, 3-4 je 6 ...
##    19-20 je 22. Danach je Stufenpaar 2 weniger: 21-22 je 20 ... 39-40 je 2 (mindestens 1).
##    62 m nach 260 Kills, 119 m nach 478, Tod nach 480 (bis 2026-11-18: einer mehr alle 2 Stufen,
##    540 Kills).
##  * Ziele: ab DEMON_GOLEM_SLOW_HEIGHT nur noch +1 alle DEMON_GOLEM_SLOW_TARGETS_STEP (2) Stufen
##    statt +DEMON_GOLEM_GROWTH_TARGETS je Stufe (Nutzervorgabe 2026-11-18): 62 m 63, 119 m 72.
##  * Alles je Stufe wurde 2026-11-17 VERDREIFACHT (Leben, Dauerheilung, Schaden,
##    Ziele, Heilung beim Wachsen) — bei 3 m je Stufe ist der Zuwachs JE METER
##    derselbe wie vorher.
##  * GEDRUNGEN: bei gleicher Hoehe DEMON_GOLEM_WIDTH_FACTOR (25 %) breiter und
##    tiefer als der Golem — Modell und Koerperbox (Trampeln, Sprung, Einebnen).
##  * Alles, was beim Golem an der GROESSE haengt, nimmt dieselbe Formel mit seiner
##    Groesse (Hoehe / GOLEM_HEIGHT): Reichweite, Laenge der Tritt-Schneise,
##    Aufschlagpunkt, Tempo, Takt, Haltungswechsel, Drehrate, Trampel- und
##    Sprungschaden, Katapult-Volltreffer. Die FLAECHEN (Radius von Handschlag und
##    Trommeln, Breite der Schneise) wachsen wie beim Golem NACH Stufe 7, und zwar
##    von Anfang an: je 3 % Koerper 0,75 % (Handschlag 1,4 %); bei 4,7 m sind sie so
##    gross wie die eines frischen Golems.
##  * Je Wachstumsstufe: +DEMON_GOLEM_GROWTH_MAX_HP Lebensobergrenze (Start
##    DEMON_GOLEM_HP), +DEMON_GOLEM_GROWTH_REGEN Leben/s Dauerheilung,
##    +DEMON_GOLEM_GROWTH_TARGETS Ziele (Grundzahl, Start DEMON_GOLEM_TARGETS; die
##    Anteile je Angriff wie beim Golem), und Schaden: Handschlag +0,75, Tritt +0,8,
##    Trommeln +1 fuer alle drei Schlaege zusammen. Startschaden: die Haelfte des
##    Golems plus DEMON_GOLEM_START_*_BONUS (2026-11-16: Handschlag +3, Tritt +2,
##    Trommeln +3 fuer alle drei Schlaege) — 15,5 / 24,5 / 24. Bruchteile zaehlen
##    mit, gerundet wird beim Treffer.
##  * UNTERHALT (Nutzervorgabe 2026-11-16): solange er lebt, kostet er
##    DEMON_GOLEM_MANA_UPKEEP (5) Mana je Sekunde — wie die Foersterei ein Anspruch auf
##    das laufende Einkommen, VOR dem Aufladen der Zauber. Verdient der Stamm weniger,
##    nimmt er das ganze Einkommen (es gibt keinen Manavorrat und keine Schuld, die
##    nach seinem Tod weiterliefe).
##  * Kill (Nutzer 2026-11-17): er heilt die LEBENSOBERGRENZE des Opfers, die
##    Haelfte (abgerundet) sofort, den Rest ueber DEMON_GOLEM_KILL_HEAL_DURATION
##    Sekunden, stapelbar. Hat das Opfer keine Lebenspunkte (Gebaeude, Fahrzeug,
##    Belohnung der Ritualkammer), gibt es DEMON_GOLEM_KILL_HEAL sofort und
##    DEMON_GOLEM_KILL_HEAL_OVER_TIME ueber die Zeit (die alten 25).
##  * ALLES 15 % SCHNELLER als beim Golem GLEICHER GROESSE: Abklingzeit, Ausholzeit,
##    Animationen und Haltungswechsel mal (1 - DEMON_GOLEM_ATTACK_SPEEDUP), das
##    Lauftempo mal (1 + DEMON_GOLEM_MOVE_SPEEDUP) (Nutzer 2026-11-17; vorher
##    liefen Haltungswechsel und Tempo wie beim Golem, mindestens 4 m/s — die
##    Untergrenze ist entfallen). Bei 80 m 2,55 statt 3 s Takt. Der Takt laeuft
##    ueber 80 m hinaus im selben Anstieg weiter (119 m: 3,08 s) und unter 4,7 m
##    entsprechend zurueck.
##  * Ab DEMON_GOLEM_AIR_HEIGHT (20 m) schlaegt er nach Luftschiffen; ab
##    DEMON_GOLEM_GIANT_HEIGHT (30 m) gilt das Riesenpaket des Golems: Boden
##    einebnen, Kollision mit Einheiten ignorieren und trampeln, gerade Wege,
##    Gebaeude niedertrampeln, Fahrzeuge treffen.
##  * Er wird NIE gehaertet (kein "ausgewachsen"): Feuer, doppelter Blitz und der
##    wachsende Katapultschaden bleiben seine Schwaechen bis zum Ende.
##  * Untergrenze, solange er klein ist (Annahme 2026-11-16): Aggro mindestens
##    MELEE_AGGRO_RADIUS. (Die Tempo-Untergrenze von 4 m/s ist 2026-11-17 entfallen:
##    bei 2 m laeuft er 2,6 m/s.)
##  * Sein Handschlag-Radius waechst als Groesse hoch DEMON_GOLEM_SLAM_EXPONENT —
##    fest auf dem Wert von vor 2026-11-17, damit die Umstellung des Golems auf
##    80 m ihn nicht veraendert.
## Die Werte aller Groessen druckt tests/diag_demon_golem_values.gd.
const DEMON_GOLEM_HP: int = 500   # 400 -> 500 (Nutzervorgabe 2026-11-16)
const DEMON_GOLEM_START_HEIGHT: float = 2.0
const DEMON_GOLEM_GROWTH_HEIGHT: float = 3.0
const DEMON_GOLEM_MAX_HEIGHT: float = 120.0
const DEMON_GOLEM_WIDTH_FACTOR: float = 1.25
const DEMON_GOLEM_GROWTH_KILLS: int = 4
const DEMON_GOLEM_GROWTH_KILLS_STEP: int = 2
const DEMON_GOLEM_GROWTH_KILLS_ADD: int = 2
const DEMON_GOLEM_SLOW_HEIGHT: float = 60.0
const DEMON_GOLEM_SLOW_TARGETS_STEP: int = 2
const DEMON_GOLEM_GROWTH_MAX_HP: int = 15
const DEMON_GOLEM_GROWTH_REGEN: float = 0.45
const DEMON_GOLEM_DAMAGE_SHARE: float = 0.5
const DEMON_GOLEM_START_SLAM_BONUS: float = 3.0
const DEMON_GOLEM_START_KICK_BONUS: float = 2.0
const DEMON_GOLEM_START_DRUM_BONUS: float = 3.0
const DEMON_GOLEM_MANA_UPKEEP: float = 5.0
const DEMON_GOLEM_GROWTH_SLAM_DAMAGE: float = 2.25
const DEMON_GOLEM_GROWTH_KICK_DAMAGE: float = 2.4
## 1,0 -> 1,2 (Nutzervorgabe 2026-11-16): mit +1 wuchs das Trommeln langsamer als der
## Handschlag (+0,75 bei 1,44-mal so schnellem Takt = effektiv +1,08) und war ab ~22 m
## je Einzelziel schwaecher - er trommelte spaeter nie mehr.
## 2026-11-17 alle Zuwaechse je Stufe verdreifacht (1,2 -> 3,6 usw.).
const DEMON_GOLEM_GROWTH_DRUM_DAMAGE: float = 3.6
const DEMON_GOLEM_TARGETS: int = 3
const DEMON_GOLEM_GROWTH_TARGETS: int = 3
const DEMON_GOLEM_KILL_HEAL: int = 10
const DEMON_GOLEM_KILL_HEAL_OVER_TIME: int = 15   # 10 -> 15 (Nutzervorgabe 2026-11-16)
const DEMON_GOLEM_KILL_HEAL_DURATION: float = 5.0
## Je WACHSTUMSSTUFE heilt er zusaetzlich DEMON_GOLEM_GROWTH_HEAL sofort und
## DEMON_GOLEM_GROWTH_HEAL_OVER_TIME ueber DEMON_GOLEM_GROWTH_HEAL_DURATION Sekunden
## (Nutzervorgabe 2026-11-16), auf die schon angehobene Lebensobergrenze und neben der
## Heilung des Kills, der die Stufe gebracht hat.
const DEMON_GOLEM_GROWTH_HEAL: int = 90   # 30 -> 90 (Nutzervorgabe 2026-11-17)
const DEMON_GOLEM_GROWTH_HEAL_OVER_TIME: int = 135   # 45 -> 135 (Nutzervorgabe 2026-11-17)
const DEMON_GOLEM_GROWTH_HEAL_DURATION: float = 5.0
const DEMON_GOLEM_ATTACK_SPEEDUP: float = 0.15
const DEMON_GOLEM_MOVE_SPEEDUP: float = 0.15
## Er dreht sich auch 15 % schneller als der Golem gleicher Groesse, im Stand und im Sitzen
## (Nutzer 2026-11-18; die Untergrenze im Sitzen also 10,9 Grad/s).
const DEMON_GOLEM_TURN_SPEEDUP: float = 0.15
## = log(12 / 2,6 / 2,214) / (53 * log(1,03)): der Exponent, den der Golem bis
## 2026-11-17 (100 m, 53 Schritte zu 3 %) fuer seinen Handschlag hatte.
const DEMON_GOLEM_SLAM_EXPONENT: float = 0.4687749
const DEMON_GOLEM_AIR_HEIGHT: float = 20.0
const DEMON_GOLEM_GIANT_HEIGHT: float = 30.0

# --- Genesisgolem (beschworene Einheit, Zauber 15, Nutzervorgabe 2026-11-17) ---
## Der dritte Golem (scripts/units/genesis_golem.gd), vorerst mit dem Modell des
## Golems. Er waechst NICHT durch Kills:
##  * Start GENESIS_GOLEM_START_HEIGHT (5 m), GENESIS_GOLEM_HP (1000) Leben, keine
##    Lebenszeit.
##  * STUFEN aus eigenen Braves: jeder Brave, den eine Huette des Stammes erzeugt,
##    zaehlt fuer die Genesisgolems des Stammes (bei mehreren geteilt).
##    GENESIS_GOLEM_STAGE_BRAVES je Stufe (8 Stufen, zusammen 154; 2026-11-17 fiel
##    die neunte weg), jede Stufe +GENESIS_GOLEM_STAGE_HEIGHT (3,5 m, Stufe 8 =
##    33 m; 2026-11-17 erst 5 -> 4, dann 3,5 m), +GENESIS_GOLEM_STAGE_MAX_HP
##    Leben, +GENESIS_GOLEM_STAGE_REGEN Leben/s.
##  * Startwerte: Schaden wie der frisch beschworene Daemonengolem (15,5 / 24,5 / 24),
##    Reichweite, Flaechen und Ziele wie der frische Golem. Mit der Groesse steigen
##    Schaden, Flaechen, Reichweite, Zielzahl und Trampelschaden wie beim
##    Daemonengolem JE METER (dessen Zuwachs je Stufe / DEMON_GOLEM_GROWTH_HEIGHT),
##    aber nur GENESIS_GOLEM_GROWTH_SHARE (2/3) so stark.
##  * Ab Stufe GENESIS_GOLEM_GIANT_STAGE (4, vorher 5): Kollision mit Einheiten ignorieren (und
##    trampeln), Boden einebnen, Luftschlag.
##  * HOLZ: er faellt Baeume (Rechtsklick, B-Bereich) mit einem Schlag und bekommt
##    deren Holz plus GENESIS_GOLEM_HARVEST_BONUS (50 %, abgerundet); ab Stufe
##    GENESIS_GOLEM_TRAMPLE_WOOD_STAGE (7, vorher 8) auch beim Trampeln. Das Holz traegt er bei
##    sich; Braves holen es wie von einem Stapel. Bleibt es GENESIS_GOLEM_WOOD_IDLE_TIME
##    (30 s) unberuehrt und kommt keins dazu, verbraucht er GENESIS_GOLEM_WOOD_BURN_RATE
##    (15) Holz je Sekunde und waechst dabei um GENESIS_GOLEM_WOOD_GROWTH_RATE (2 %)
##    je Sekunde, bis GENESIS_GOLEM_MAX_HEIGHT (100 m, vorher 200 m); je Meter daraus
##    +GENESIS_GOLEM_WOOD_HP_PER_M Leben und +GENESIS_GOLEM_WOOD_REGEN_PER_M Leben/s.
const GENESIS_GOLEM_HP: int = 1000
const GENESIS_GOLEM_START_HEIGHT: float = 5.0
const GENESIS_GOLEM_STAGE_HEIGHT: float = 3.5
const GENESIS_GOLEM_STAGE_BRAVES: Array[int] = [10, 12, 14, 17, 20, 23, 27, 31]
const GENESIS_GOLEM_STAGE_MAX_HP: int = 40
const GENESIS_GOLEM_STAGE_REGEN: float = 2.0
const GENESIS_GOLEM_GROWTH_SHARE: float = 2.0 / 3.0
const GENESIS_GOLEM_GIANT_STAGE: int = 4
const GENESIS_GOLEM_TRAMPLE_WOOD_STAGE: int = 7
const GENESIS_GOLEM_HARVEST_BONUS: float = 0.5
## Nutzervorgabe 2026-11-17: seine Aggroreichweite ist die halbe der anderen Golems
## (gleicher Groesse), und ein Gebaeude, das er zerstoert, bringt ihm diesen Anteil
## seiner Baukosten als Holz (abgerundet).
const GENESIS_GOLEM_AGGRO_SHARE: float = 0.5
const GENESIS_GOLEM_BUILDING_WOOD_SHARE: float = 0.5
const GENESIS_GOLEM_WOOD_IDLE_TIME: float = 30.0
const GENESIS_GOLEM_WOOD_BURN_RATE: float = 15.0
const GENESIS_GOLEM_WOOD_GROWTH_RATE: float = 0.02
const GENESIS_GOLEM_MAX_HEIGHT: float = 100.0
const GENESIS_GOLEM_WOOD_HP_PER_M: float = 3.0   # 2 -> 3 (Nutzervorgabe 2026-11-17)
const GENESIS_GOLEM_WOOD_REGEN_PER_M: float = 0.15
## Abstand des mitgefuehrten Holzstapels vor seinem Koerperrand (Annahme): dort
## erreichen ihn die Braves, ohne unter den Koerper zu muessen.
const GENESIS_GOLEM_PILE_GAP: float = 0.8

# --- Feuerkrieger ---
const FIREWARRIOR_HP: int = 70   # 65 -> 70 (Nutzervorgabe 2026-11-17)
const FIREWARRIOR_SPEED: float = 4.0
## 8 -> 9 m (Nutzerentscheidung 2026-09-06 nach dem 200-gegen-200-Labor).
const FIREWARRIOR_FIRE_RANGE: float = 9.0
const FIREWARRIOR_FIRE_COOLDOWN: float = 1.5
const FIREWARRIOR_AGGRO_RADIUS: float = 13.0
## Schaden eines Feuerballs an Einheiten.
## 9 -> 10 (Nutzerentscheidung 2026-09-06, zweiter Labor-Schritt nach der Reichweite).
const FIREWARRIOR_FIREBALL_DAMAGE: int = 10
## Fluggeschwindigkeit (m/s) des Feuerkrieger-Feuerballs (zielsuchend).
const FIREWARRIOR_FIREBALL_SPEED: float = 12.0
## Verfolgt der Ball ein LUFTZIEL (geschleuderte Einheit, Zeppelin), gewinnt er
## kontinuierlich Tempo (m/s²) — mit dem Grundtempo holte er hochgeschleuderte
## Ziele kaum ein. Gedeckelt, damit er nicht durch das Ziel hindurchschießt.
const FIREWARRIOR_FIREBALL_AIR_ACCEL: float = 22.0
const FIREWARRIOR_FIREBALL_AIR_MAX_SPEED: float = 34.0
## Schaden eines Feuerballs an Gebäuden.
const FIREWARRIOR_BUILDING_DAMAGE: int = 5
## Nahkampf-Attackenchancen (Rest = Punch, s. Unit._roll_attack_kind). Neu
## 2026-09-07 (vorher die Standardwerte 0,15 / 0,20): Der Feuerkrieger ist im
## Nahkampf ein Draengler und Treter — die beiden Chancen summieren sich zu
## 1,0, der Faustschlag entfaellt damit BEWUSST vollstaendig (Nutzervorgabe).
const FIREWARRIOR_SHOVE_CHANCE: float = 0.4
const FIREWARRIOR_KICK_CHANCE: float = 0.6

# --- Prediger ---
## 90 -> 85 (Nutzerentscheidung 2026-09-06, Labor-Schritt 3).
const PREACHER_HP: int = 90   # 85 -> 90 (Nutzervorgabe 2026-11-17)
const PREACHER_SPEED: float = 4.0
const PREACHER_CONVERT_RANGE: float = 5.0
## Bekehrdauer: pro Ziel zufällig aus [MIN, MAX] gewürfelt.
const PREACHER_CONVERT_TIME_MIN: float = 4.0
const PREACHER_CONVERT_TIME_MAX: float = 9.0
## Nahkampf-Attackenchancen (Rest = Punch): schubst viel häufiger als der
## Standard und tritt GAR NICHT (2026-09-07, vorher 0,5 / 0,1) — er draengt den
## Gegner weg, statt ihn zu verletzen. 40 % bleiben der Faustschlag.
const PREACHER_SHOVE_CHANCE: float = 0.6
const PREACHER_KICK_CHANCE: float = 0.0

# --- Schamanin ---
const SHAMAN_HP: int = 240              # 4 x Brave
const SHAMAN_SPEED: float = 4.0
const SHAMAN_MELEE_STRENGTH: float = 2.0   # 2 x Brave-Schaden
## Wind-up vor dem Zauber-Release: die Zeit, in der die Schamanin die
## Zauberformel spricht (Phase 10b). Für alle Zauber gleich.
## Dauer der Zauber-Animation (Wind-up). Phase 10k-Nachtrag: 1,0 -> 0,5 s
## (Nutzervorgabe) — die Schamanin ist danach wieder frei, der EFFEKT tritt bei
## den schweren Zaubern erst spaeter ein (SPELL_EFFECT_DELAY_*).
const SHAMAN_CAST_TIME: float = 0.5
## Verzoegerung des Effekts NACH dem Wind-up. 0 = sofort (etwas schneller als
## vorher), MID = wie bisher insgesamt 1,0 s, LATE = 1,5 s fuer die schweren
## Zauber. Die Schamanin wartet nicht mit — ein kleiner Traeger auf der
## Projektilliste zuendet den Effekt (Muster FirestormShower).
const SPELL_EFFECT_DELAY_MID: float = 0.5
const SPELL_EFFECT_DELAY_LATE: float = 1.0
## Mana-Bonus (Anteil der Ladungskapazität) für den Stamm, der sie tötet.
## Schamanentötung: Der Töter bekommt diesen Anteil der MINÜTLICHEN
## Manaproduktion des getöteten Stammes einmalig auf seine aktiven
## Aufladeraten verteilt (Phase 10c; vorher 15 % der eigenen Ladungskapazität).
const SHAMAN_KILL_MANA_MINUTE_SHARE: float = 0.10
## Wartezeit bis zum Respawn am Reinkarnationsplatz.
const SHAMAN_RESPAWN_TIME: float = 20.0

# --- Katapult (Belagerungswaffe) ---
const SIEGE_SPEED: float = 2.0          # langsamste Einheit
## Crew-Plätze: ab MIN_MOVE fährt es, ab MIN_FIRE schießt es (Cooldown skaliert
## bis zur vollen Crew, s. u.). Nicht direkt angreifbar — bekämpft wird die Crew.
const SIEGE_MAX_CREW: int = 6
const SIEGE_MIN_MOVE_CREW: int = 1
const SIEGE_MIN_FIRE_CREW: int = 2
## Abstand, ab dem eine zusteigende Einheit als "am Fahrzeug" gilt.
const SIEGE_BOARD_RANGE: float = 2.5
## Leine der Crew: weiter entfernte Mitglieder (Kampf) laufen zurück/steigen ab.
const SIEGE_CREW_LEASH: float = 8.0
## Zeitlimit für einen NOCH NICHT eingestiegenen Rekruten (alle Fahrzeuge).
## Bugfix nach Nutzertest: die Leine oben gilt nur für eingestiegene Mitglieder,
## ein Rekrut hatte also weder Leine noch Frist. Ein Zeppelin, dessen Bodenpunkt
## unerreichbar ist (über Wasser, andere Insel) oder der wegfliegt, sammelte so
## bis zu 6 „Geister-Rekruten" an: Plätze belegt, `boarded_count()` = 0 — das
## Fahrzeug galt überall als unbemannt/neutral und war weder angreifbar noch
## bemannbar. Wer es in dieser Zeit nicht an Bord schafft, kommt gar nicht.
const VEHICLE_CREW_BOARD_TIMEOUT: float = 45.0
## Neutral-Regel (2026-09-06): Ein Fahrzeug ohne HANDLUNGSFÄHIGE Besatzung
## (niemand in State.CREW an Bord — alle sitzen in Bekehrung, panieren, brennen,
## rollen oder kämpfen einzeln) ist neutral: kein Angriffsziel, fährt und feuert
## nicht. Ein Bodenfahrzeug, das so lange neutral bleibt, ohne dass die alte
## Besatzung zurückkehrt, darf danach von JEDEM bemannt (gekapert) werden —
## ein wirklich verlassenes (keine Crew zugeordnet) sofort. Luftschiffe sind
## sofort kaperbar, sobald niemand mehr an Deck ist.
const VEHICLE_NEUTRAL_TAKEOVER_TIME: float = 10.0
## Brenndauer des Fahrzeugs nach Feuerzauber-Treffer, dann versinkt das Wrack.
const SIEGE_VEHICLE_BURN_TIME: float = 3.0
const SIEGE_FIRE_RANGE: float = 16.0
## Ziele näher dran kann der Bogenschuss nicht treffen.
const SIEGE_MIN_RANGE: float = 3.0
const SIEGE_AGGRO_RADIUS: float = 20.0
## Schuss-Cooldown: 2 Crew -> MIN_CREW-Wert, volle Crew (6) -> FULL_CREW-Wert.
const SIEGE_COOLDOWN_MIN_CREW: float = 6.0
const SIEGE_COOLDOWN_FULL_CREW: float = 3.0
## Kugel-Einschlag: Flächenschaden (Friendly Fire!) und Radius.
const SIEGE_SHOT_SHOCK_DAMAGE: int = 15    # 1/4 Brave-Leben
const SIEGE_SHOT_SHOCK_RADIUS: float = 2.0
## Zerstörungsstufen, die ein Treffer einem Gebäude zufügt.
const SIEGE_SHOT_BUILDING_STAGES: int = 1
## Schaden pro Treffer an feindlichen Raidern im EIGENEN Gebäude (sie werden
## dabei rausgeworfen, nicht getötet — 1/2 Brave-Leben).
const SIEGE_SHOT_RAIDER_DAMAGE: int = 30
## Luftschuss (Ziel Luftschiff): Abfangradius um die Kugel und Flächenfaktor
## des Schockschadens (doppelte FLÄCHE -> Radius x sqrt(2)); keine Lava.
## INTERCEPT_RADIUS entscheidet, wie viele Zeppeline EIN Schuss trifft (jede
## Hülle mit Mittelpunkt im Radius bekommt einen Treffer) — die Schiffe sind
## ~2 m breit / 6 m lang, daher muss der Radius groß sein für Mehrfachtreffer.
const SIEGE_SHOT_AIR_INTERCEPT_RADIUS: float = 4.0
const SIEGE_SHOT_AIR_SPLASH_FACTOR: float = 4.0

# --- Feuerramme ---
const FIRERAM_SPEED: float = 3.0
## Crew: ab 1 fährt UND feuert sie (Cooldown skaliert bis zur vollen Crew).
const FIRERAM_MAX_CREW: int = 4
const FIRERAM_MIN_MOVE_CREW: int = 1
const FIRERAM_MIN_FIRE_CREW: int = 1
## Flammenstoß nach vorn: Rechteck LÄNGE x BREITE (Zellen). Einheiten NÄHER
## als MIN_RANGE stehen hinter der Düse — gegen sie hält die Ramme das Feuer
## (Gebäude direkt an der Wand brennen weiter, die Flammen reichen hin).
const FIRERAM_FIRE_RANGE: float = 5.0
const FIRERAM_MIN_RANGE: float = 1.0
## Flammenrechteck: Breite an der Düse (Anfang) und am Reichweitenende. Der
## Kegel fächert linear von FLAME_WIDTH auf FLAME_END_WIDTH auf.
const FIRERAM_FLAME_WIDTH: float = 2.0
const FIRERAM_FLAME_END_WIDTH: float = 3.0
## Dauer eines Flammenstoßes; danach Nachladen (1 Crew -> MIN, 4 Crew -> FULL).
const FIRERAM_FLAME_DURATION: float = 1.1
const FIRERAM_COOLDOWN_MIN_CREW: float = 3.0
const FIRERAM_COOLDOWN_FULL_CREW: float = 1.4
const FIRERAM_AGGRO_RADIUS: float = 12.0
## Echte Dreh-Rate des Rumpfs (rad/s); Stoß startet erst bei Ausrichtung
## innerhalb der Toleranz (rad) zum Ziel.
const FIRERAM_TURN_RATE: float = 2.0
const FIRERAM_AIM_TOLERANCE: float = 0.33
## Lava-Kontakt-Gutschrift pro Flammensekunde an Gebäuden. MUSS zusammen mit
## FLAME_DURATION >= LAVA_BUILDING_STAGE_TIME ergeben, sonst verfällt der
## Kontakt im Grace-Fenster (1 s) zwischen zwei Stößen und Gebäude nehmen
## nie eine Stufe: 1,1 s Flamme x 5.0 = 5,5 s Kontakt >= 5 s = 1 Zerstörungsstufe
## je Stoß (der Überschuss verfällt im Grace, eine 2. Stufe bräuchte >= 2 s Flamme).
const FIRERAM_FLAME_CONTACT_FACTOR: float = 5.0
## Feuerfestigkeit: die Ramme hält so viele FEUER-Treffer aus (pro Quelle/Attacke
## max. 1), bevor sie abbrennt; bemannt regeneriert sie 1 Treffer je REGEN_TIME.
## Physische Zerstörung (Wasser, Terrainriss, Tornado) bleibt sofort tödlich.
const FIRERAM_FIRE_LIVES: int = 3
const FIRERAM_LIFE_REGEN_TIME: float = 30.0
## Todesexplosion (nur Boden-Tode: Feuer, Terrainriss, Verlassen-Timeout —
## Ertrinken/Tornado nicht): Rechteck 2·HALF_WIDTH Zellen breit (3), FRONT
## Zellen vor und BACK Zellen hinter der Rumpf-Mitte. Trifft ALLES im Feld
## (auch die eigene, gerade freigelassene Crew): Einheiten DAMAGE +
## Feuerball-Rückstoß, Gebäude +1 Zerstörungsstufe, Fahrzeuge 1 Feuertreffer/
## Hüllentreffer.
const FIRERAM_DEATH_BLAST_DAMAGE: int = 30
const FIRERAM_DEATH_BLAST_FRONT: float = 2.0
const FIRERAM_DEATH_BLAST_BACK: float = 4.0
const FIRERAM_DEATH_BLAST_HALF_WIDTH: float = 1.5

# --- Luftschiff ---
const AIRSHIP_SPEED: float = 5.0
const AIRSHIP_MAX_CREW: int = 6
const AIRSHIP_MIN_MOVE_CREW: int = 1
## Horizontaler Abstand zum Bodenschatten, ab dem Zusteigen zählt.
const AIRSHIP_BOARD_RANGE: float = 1.5
## Reiseflughöhe über "normalem Boden" (über Wasser: über Meeresspiegel).
## Gelände zählt für das Reiseziel nur bis Kartendurchschnitt + CRUISE_CAP;
## darüber folgt das Schiff dem Terrain mit MIN_CLEARANCE Abstand.
const AIRSHIP_FLY_HEIGHT: float = 10.0
## Hartes Minimum über dem Boden direkt unter dem Rumpf (sofort erzwungen).
const AIRSHIP_MIN_CLEARANCE: float = 2.0
## Gelände über Kartendurchschnitt + Cap gilt als "hoch" (kein +10-Ziel mehr).
const AIRSHIP_CRUISE_TERRAIN_CAP: float = 5.0
## Steig-/Sinkgeschwindigkeit (m/s) Richtung Zielhöhe (weiche Übergänge).
const AIRSHIP_VERTICAL_RATE: float = 3.0
## Kleine Kollisions-/Separationsdistanz zwischen Luftschiffen (kein 100%-Stack;
## kleiner als Bodenfahrzeuge ~3,0). Luftschiffe separieren nur gegeneinander.
const AIRSHIP_SEPARATION: float = 2.0
## Push-Tempo-Faktor: Luftschiffe schieben sich viel schneller frei als Bodeneinheiten.
const AIRSHIP_SEPARATION_SPEED_MULT: float = 4.0
## Formations-Spreizung für Luftschiffe: skaliert die (engen) Member-/Gruppen-
## Offsets, sodass die Zielpunkte mehrerer Luftschiffe außerhalb der
## Separationsblase (~2 m) liegen und leicht erreichbar sind (0,55 m × 5 ≈ 2,75 m).
const AIRSHIP_FORMATION_SCALE: float = 5.0
## Formations-Spreizung für Bodenfahrzeuge (Katapult/Feuerramme): ihre
## Separationsblase (~3,0–3,2 m) ist größer als beim Luftschiff, daher ein
## größerer Faktor, damit die Zielpunkte mehrerer Fahrzeuge außerhalb der Blase
## liegen (0,55 m × 7,5 ≈ 4,0 m > 3,2 m) — sonst drängen sie sich am Ziel.
const VEHICLE_FORMATION_SCALE: float = 7.5
## Reichweiten-Bonus für Fernkampf/Bekehrung/Zauber von Bord (nur im Stand).
const AIRSHIP_RANGE_BONUS: float = 3.0
## Hüllentreffer (Feuerball-Zauber-Bolts + Katapult-Lufttreffer) bis zur Explosion.
const AIRSHIP_HULL_HITS: int = 2
## Explosionsschaden an allen Insassen; der anschließende Sturz aus Flughöhe
## nutzt den normalen Wurf-Pfad (Wasser = Ertrinken).
const AIRSHIP_CRASH_DAMAGE: int = 30
## Leere Luftschiffe treiben langsam Richtung erreichbarem Terrain.
const AIRSHIP_DRIFT_SPEED: float = 0.5
## Maximaler Abstand zum Absetzpunkt beim "Absetzen an..."-Befehl.
const AIRSHIP_UNLOAD_RANGE: float = 2.0
## Feuerkrieger-Schadensfaktor gegen Ziele in der Luft (Deck-Crew UND
## hochgeschleuderte Einheiten — `Unit.is_airborne()`). Phase 10c trimmte den
## Verdoppler auf +20 %, weil die Kombo „hochwerfen und abschießen" mit dem Lift
## zuverlässig wurde; 2026-09-02 auf **+10 %** halbiert (Nutzerentscheidung, im
## selben Zug mit dem stärkeren Flächenschaden).
const FIREWARRIOR_AIRBORNE_MULT: float = 1.1

# =============================================================================
# NAHKAMPF ALLGEMEIN (alle Einheiten)
# =============================================================================

const MELEE_RANGE: float = 1.2
## Standard-Aggro-Radius von Nahkämpfern (Krieger etc.).
const MELEE_AGGRO_RADIUS: float = 8.0
## Sekunden zwischen zwei Schlägen.
const ATTACK_COOLDOWN: float = 0.8
## Basis-Schadenswerte der drei Schlagarten (x melee_strength der Einheit).
const MELEE_PUNCH: int = 6
const MELEE_KICK: int = 8
const MELEE_SHOVE: int = 3
## Wahrscheinlichkeiten für Kick/Schubser (Rest = Punch).
const KICK_CHANCE: float = 0.2
const SHOVE_CHANCE: float = 0.15
## Selbstheilung: Verzögerung nach dem letzten Kampf und HP/s danach.
const REGEN_DELAY: float = 8.0
const REGEN_RATE: float = 5.0

# =============================================================================
# LEICHEN
# =============================================================================

## Liegezeit der Leiche, danach versinkt sie im Boden.
const CORPSE_DURATION: float = 6.0
## Dauer der Versink-Animation. ACHTUNG: verlängert die Gesamt-Lebenszeit von
## Leichen in der Welt — der Zentroid-Drift-Test (test_combat_groups) misst
## über alle Einheiten inkl. Leichen und reagiert auf große Änderungen.
const CORPSE_SINK_DURATION: float = 1.0
## Wie tief das Leichen-Sprite versinkt (Sprite-Höhe + Rand).
const CORPSE_SINK_DEPTH: float = 1.6
## Anteil der Einheiten, die in den liegenden Posen (Leiche, Flug) auf dem
## BAUCH statt auf dem Rücken landen. Einmal je Einheit gewürfelt, damit nicht
## jede Leiche gleich herum liegt. 0 = alle auf dem Rücken, 1 = alle auf dem
## Bauch.
const LIE_FACE_DOWN_CHANCE: float = 0.4

# =============================================================================
# ERTRINKEN (Phase 10a)
# =============================================================================
# Eine ins Wasser gerollte/geschleuderte Einheit stirbt sofort, zappelt aber
# noch kurz an der Oberfläche und versinkt dann unter der (undurchsichtigen)
# Wasserfläche. Zusammen deutlich kürzer als eine Leiche an Land — im Wasser
# soll nichts treiben.

## Zappeldauer an der Oberfläche (Drown-Animation).
const DROWN_FLAIL_DURATION: float = 0.7
## Absinkdauer danach; anschließend ist die Leiche verschwunden.
const DROWN_SINK_DURATION: float = 1.1
## Wie tief die Figur beim Zappeln schon im Wasser steht (m unter SEA_LEVEL).
const DROWN_FLOAT_DEPTH: float = 0.9
## Absinktiefe (m) — Sprite-Höhe plus Reserve gegen den Tiefen-Bias des
## Billboard-Shaders, damit am Ende nichts mehr durch die Wasserfläche lugt.
const DROWN_SINK_DEPTH: float = 1.9
## Wasser ist allein über die Höhe definiert — es gibt keine modellierte Tiefe,
## alles Wasser ist gleich "tief". Der Uferzug ist deshalb eine rein waagerechte
## Frage: so weit muss der Körper HINTER der Wasserlinie liegen, damit er im
## Wasser und nicht auf der Kante versinkt.
const DROWN_SHORE_MARGIN: float = 0.9
## Obergrenze des Uferzugs (m). Wer weiter draußen ertrinkt, wird gar nicht
## gezogen; wer nichts Passendes in Reichweite hat, bleibt ebenfalls liegen.
const DROWN_DRAG_MAX: float = 2.5
## Tempo (m/s) des Uferzugs.
const DROWN_DRAG_SPEED: float = 2.5

# =============================================================================
# ROLLEN (Statuseffekt — Schubser, Wurf-Landungen, Stolpern)
# =============================================================================

## Bodengeschwindigkeit beim Rollen (Hangneigung addiert etwas Tempo).
const ROLL_SPEED: float = 5.5
## Dauer eines Mini-Rollers auf flachem Boden (Schubser / Feuerball-Umwerfer).
const MINI_ROLL_DURATION: float = 0.35
## Noch kürzerer Purzler für angrenzende, vom Feuerball umgeworfene Einheiten.
const NEIGHBOR_ROLL_DURATION: float = 0.25
## Rollschaden (HP/s); tödlicher Schaden wird bis zum Roll-Ende aufgeschoben.
const ROLL_DPS: float = 5.0
## Chance, dass ein Schubser das Ziel umwirft (Mini-Roller, auch auf flachem Boden).
const SHOVE_ROLL_CHANCE: float = 0.25
## Chance/s, beim Hinablaufen sehr steiler Hänge von selbst ins Stolpern zu geraten.
const STEEP_ROLL_CHANCE_PER_SEC: float = 0.5

# =============================================================================
# RÜCKSTOSS & ANHEBEN (Phase 10c — Unit.apply_lift)
# =============================================================================

## Feuerball-Zauber und jeder Feuerregen-Bolt: Schubradius etwas GRÖSSER als
## der Schadensradius (2,5) — Randtreffer werden nur geschoben, nicht verletzt.
const FIREBALL_PUSH_RADIUS: float = 3.2
const FIREBALL_PUSH_SPEED: float = 5.0
const FIREBALL_LIFT_SPEED: float = 6.5
## Blitz: stärker als der Feuerball.
const LIGHTNING_PUSH_RADIUS: float = 2.6
const LIGHTNING_PUSH_SPEED: float = 7.0
const LIGHTNING_LIFT_SPEED: float = 9.0
## Feuerkrieger-Feuerball: welche der DREI exklusiven Wirkungen ein Treffer am
## Hauptziel hat (Anheben > Umwerfen > Stossen, siehe Fireball.impact_outcome).
## Die _ROLLING-Werte gelten fuer ein Ziel, das bereits rollt.
##
## 2026-09-02 (Nutzerentscheidung): gegen ROLLENDE Ziele wurde das Umwerfen
## deutlich staerker (0,30 -> 0,50) und das Anheben schwaecher (0,10 -> 0,08) —
## ein Koerper am Boden wird eher weitergerollt als hochgerissen.
const FW_FIREBALL_ROLL_CHANCE: float = 0.06
const FW_FIREBALL_LIFT_CHANCE: float = 0.04
const FW_FIREBALL_ROLL_CHANCE_ROLLING: float = 0.50
const FW_FIREBALL_LIFT_CHANCE_ROLLING: float = 0.08
## Ein Lift ERSETZT den Bodenschub: weniger Horizontale, kleiner Hüpfer.
const FW_FIREBALL_LIFT_PUSH: float = 1.2
const FW_FIREBALL_LIFT_UP: float = 3.0
## Kämpft die FEINDLICHE Schamanin so nah an einem Prediger, bricht seine Predigt
## ab und er kann keine neue beginnen (Original-Populous-Regel, Phase 10i Teil 2).
## Gegenmittel gegen die im Balance-Labor belegte Prediger-Dominanz: 20 Prediger
## bekehren 20 zeitgleich ausgebildete Krieger verlustfrei (0:3 Siege, 19,7
## Bekehrte). Ohne kämpfende Schamanin bleibt diese Dominanz unangetastet — die
## Regel ist ein Gegenmittel, keine Nerfung.
const PREACHER_SHAMAN_DISTURB_RANGE: float = 6.0

## Anhebe-Chance bei fast totem Ziel als Vielfaches der Basis (1.0 = keine
## Skalierung), linear invers über die HP: je verletzter das Ziel, desto leichter
## fliegt es. Bei 2.0 also 4 % bei voller Gesundheit und **8 %** kurz vor dem Tod
## (rollendes Ziel 8 % → **16 %**). 2026-09-02 von 3.0 gesenkt
## (Nutzerentscheidung, im Zug mit dem staerkeren Umwerfen).
const FW_FIREBALL_LIFT_HP_MAX_MULT: float = 2.0
## Flächenschaden des Feuerkrieger-Feuerballs (Phase 10i Teil 3): Radius und
## Anteil am Hauptzielschaden. Trifft NUR Feinde und macht keinen Rückstoß —
## Feuerkrieger schießen in Massen, mit Friendly Fire würde die hintere Reihe die
## eigene Front zerlegen. Grund: sie teilen im Balance-Labor 100 % des
## Kriegerpools aus und töten trotzdem fast niemanden — ein Konzentrations-,
## kein Schadensproblem.
##
## Der Radius ist an der **Einheitengeometrie** ausgerichtet (Nutzerentscheidung
## 2026-08-05, in zwei Schritten von 2,0 m / 50 % auf 1,2 m / 20 %): ein 6er-Pack
## ist maximal 1,10 m breit (`TribeCommands.MEMBER_OFFSETS`) und eine
## Nahkampfgruppe 0,9 m (`Unit.MELEE_SLOT_RADIUS`), 1,2 m fasst also **genau einen
## Pack** — und lässt die Nachbargruppe (2,2 m Zentrumsabstand, `GROUP_SPACING`)
## sowie den nächsten Angreifer des Nachbarkampfs (2,8 − 0,9 = 1,9 m) draußen. Bei
## 2,0 m griff der Splash in die Nachbarschaft über und drehte im Labor die Paarung
## Luftschiff gegen Feuerkrieger. Achtung: die Radiusabfrage misst **flach in
## XZ**, der Bereich ist also ein senkrechter Zylinder — ein Bodeneinschlag
## trifft auch Fliegende darüber.
##
## **Die Wirkung skaliert mit der DICHTE, nicht mit der Truppenzahl** (gemessen
## 2026-08-05, `feuerkrieger_vs_krieger_200_anmarsch`): bei 20 gegen 20 stehen
## vier lose 6er-Packs, der Radius findet meist niemanden; in einem 200er-Klumpen
## liegen bei `UnitManager.SEPARATION_RADIUS` 0,44 m fast immer ~3 weitere Ziele
## drin, und der Splash **verdoppelt** den Schadensdurchsatz. Feuerkrieger sind
## damit bewusst eine **Masseneinheit** (Nutzerentscheidung: so gewollt, kein
## Opferdeckel je Ball). Wer die kleinen Gefechte beurteilt, unterschätzt diese
## Konstanten um etwa eine Größenordnung.
const FW_FIREBALL_BLAST_RADIUS: float = 1.3
const FW_FIREBALL_BLAST_FRAC: float = 0.3
## Rolldauer, die EIN Feuerball dem Ziel aufdrueckt. Trifft es ein bereits
## rollendes Ziel, verlaengert start_roll den Sturz um diese Zeit ab dem Treffer
## (Nutzerentscheidung 2026-09-02: 0,5 s statt der allgemeinen 0,35 s aus
## MINI_ROLL_DURATION — der Feuerball haelt ein Ziel damit sichtbar am Boden).
## Bewusst ein EIGENER Wert: MINI_ROLL_DURATION haengt an Wurflandungen,
## Klippenstuerzen, Nahkampf-Schubsern und Gebaeudetruemmern.
const FW_FIREBALL_ROLL_DURATION: float = 0.5
## Ein Treffer auf ein BEREITS rollendes Ziel stoesst es nicht mehr (der 0,35-m-
## Schubser war neben den ~2,75 m Rollstrecke bedeutungslos), sondern **lenkt**
## die Rolle und **beschleunigt** sie: je Treffer +GAIN auf die aktuelle
## Rollgeschwindigkeit, gedeckelt bei MAX (Nutzerentscheidung 2026-09-02:
## aufstapeln, nicht nur auffuellen).
##
## Der Deckel ist PFLICHT, nicht Kosmetik: `_tick_roll` uebergibt die
## Rollgeschwindigkeit am Scheibenrand direkt an `throw_airborne` und traegt sie
## in Klippenstuerze — ohne Deckel schiesst eine 200er-Feuerlinie Koerper quer
## ueber die Karte und ins All. 12 m/s entspricht dem Tornado-Auswurf, ist also
## das schnellste, was das Spiel sonst kennt.
const FW_FIREBALL_ROLL_BOOST_GAIN: float = 2.0
const FW_FIREBALL_ROLL_BOOST_MAX: float = 12.0
## Ein FRISCHES Umwerfen reisst Nachbarn mit: Radius um das Ziel und Chance je
## Nachbar (die dann NEIGHBOR_ROLL_DURATION rollen). Radius 2026-09-02 von 0,9
## auf 1,0 m erhoeht; standen vorher als lokale Konstanten in fireball.gd und
## damit ausserhalb dieser Datei — jetzt hier, wo die Feuerballwerte leben.
const FW_FIREBALL_NEIGHBOR_ROLL_RADIUS: float = 1.0
const FW_FIREBALL_NEIGHBOR_ROLL_CHANCE: float = 0.5
## Treffer auf bereits fliegende Ziele: der Lift wird IMMER verstärkt.
const LIFT_AIRBORNE_BONUS: float = 2.0
const LIFT_AIRBORNE_PUSH_FACTOR: float = 0.5
## Obergrenze der Flughöhe (m über dem Boden darunter) für JEDEN Wurf. Ohne
## sie stapeln sich Feuerball-Kombos zu Würfen aus dem Bild heraus. Es wird
## nur der AUFSTIEG gekappt — wer weiter oben startet (vom Zeppelindeck
## geschleudert), fällt von dort, statt nach unten versetzt zu werden.
const LIFT_MAX_HEIGHT: float = 8.0
## Was vom Hochschub nicht mehr unter den Deckel passt, wird stattdessen mit
## diesem Faktor auf den SEITLICHEN Schub gelegt (1,0 = eins zu eins).
const LIFT_SIDEWAYS_TRANSFER: float = 1.0
# --- Scheibenwelt: Sturz ins All (Phase 10j) ---
# Die unsichtbare Mauer an der Weltgrenze (WORLD_EDGE_MARGIN /
# WORLD_BOUNCE_RESTITUTION, Phase 10c) ist ENTFALLEN. Sie war die Behandlung eines
# Symptoms: die Schamanin landete ausserhalb der Karte, weil
# TerrainData.get_height() seine Eingaben clampt und draussen die Randhoehe
# fortsetzt — es gab also UEBERALL Boden. Seit 10j ist draussen der Void, und wer
# hinausgeschleudert wird, faellt.
## Tiefe unter dem Absprungpunkt, ab der eine ins All gestuerzte Einheit entsorgt
## wird (sie ist da langst ausser Sicht). Bei THROW_GRAVITY 18 sind das ~3,7 s
## freier Fall.
const VOID_FALL_DEPTH: float = 120.0
## Notausgang, falls ein Sturz ohne Vertikalgeschwindigkeit beginnt und die
## Tiefenschwelle nie erreicht.
const VOID_FALL_MAX_TIME: float = 15.0
## Gesamttiefe der Scheibe unter dem Meeresspiegel: kurze senkrechte Felskante am
## Rand, darunter ein umgedrehter Kegel mit abgerundeter Spitze (Nutzerentscheidung
## 2026-08-05, TerrainRim). Ohne diesen Koerper waere die Scheibe papierduenn und
## man sehe bei flachem Kamerawinkel hindurch.
const WORLD_RIM_SKIRT_DEPTH: float = 60.0
## Hoehe des Wasserfall-Bands unter dem Meeresspiegel. BEWUSST kuerzer als die
## Scheibe tief ist: das Wasser stuerzt senkrecht in den Abgrund, waehrend sich der
## Kegel nach innen verjuengt, und loest sich per Alpha-Gradient auf, bevor es die
## Spitze erreicht (Nutzervorgabe). Genau dieser Kontrast macht die Kegelform lesbar.
const WATERFALL_HEIGHT: float = 34.0
const WATERFALL_SCROLL_SPEED: float = 1.6

# =============================================================================
# BRAND / LAVA (Einheiten)
# =============================================================================

const LAVA_CONTACT_DAMAGE: int = 20
const BURN_DURATION: float = 4.0
## Gesamtschaden über die Brenndauer.
const BURN_TOTAL_DAMAGE: int = 60
## Gebäude in Lavakontakt: 1 Zerstörungsstufe je VOLLE Kontaktsekunden …
const LAVA_BUILDING_STAGE_TIME: float = 5.0
## … wobei der Kontaktzähler resettet, wenn so lange keine Lava anliegt.
const LAVA_BUILDING_CONTACT_GRACE: float = 1.0

# --- LAVA: Fluss, Lebensdauer, Kostendeckel (Phase 10c) ---
## Lebensdauer JEDER Lava-Instanz nach dem Spawn (Vulkan, Erdbeben, …).
const LAVA_LIFETIME: float = 5.0
## Katapult-Pfütze: eigener Wert, Verhalten sonst identisch.
const LAVA_CATAPULT_LIFETIME: float = 5.0
## Zähflüssig: Grundtempo der Front (m/s) — vorher 3,0-3,2.
const LAVA_FLOW_SPEED: float = 0.9
## Hangabhängigkeit: Tempo = FLOW_SPEED * (1 + BIAS * Gefälle), bergauf 0.
const LAVA_SLOPE_BIAS: float = 2.5
## Unter diesem Gefälle staut sich die Lava zur Pfütze.
const LAVA_MIN_SLOPE: float = 0.04
## Glühdauer einer frisch überströmten Stelle (Schadensfenster).
const LAVA_MOLTEN_TIME: float = 3.0
## Kostendeckel: Kontaktprüfung und Mesh-Neubau (Sekunden).
const LAVA_CONTACT_INTERVAL: float = 0.25
const LAVA_VISUAL_INTERVAL: float = 0.2

# =============================================================================
# ZAUBER — Ladungen (charge_cost = Mana pro Ladung) und Reichweite
# =============================================================================

const SPELL_FIREBALL_CHARGE_COST: float = 30.0
const SPELL_FIREBALL_MAX_CHARGES: int = 4
## 8 -> 9 m (Nutzervorgabe 2026-09-07: KEIN Zauber unter 9 m Reichweite — der
## Feuerball war der einzige, der die Schamanin naeher heranzwang).
const SPELL_FIREBALL_CAST_RANGE: float = 9.0

const SPELL_LIGHTNING_CHARGE_COST: float = 200.0
const SPELL_LIGHTNING_MAX_CHARGES: int = 4
const SPELL_LIGHTNING_CAST_RANGE: float = 12.0

const SPELL_SWARM_CHARGE_COST: float = 100.0
const SPELL_SWARM_MAX_CHARGES: int = 4
const SPELL_SWARM_CAST_RANGE: float = 10.0

const SPELL_LANDBRIDGE_CHARGE_COST: float = 150.0
const SPELL_LANDBRIDGE_MAX_CHARGES: int = 4
const SPELL_LANDBRIDGE_CAST_RANGE: float = 9.0

const SPELL_TORNADO_CHARGE_COST: float = 220.0
const SPELL_TORNADO_MAX_CHARGES: int = 3
const SPELL_TORNADO_CAST_RANGE: float = 11.0

const SPELL_SUPERTORNADO_CHARGE_COST: float = 1200.0   # teurer als Tornado, ~Vulkan
const SPELL_SUPERTORNADO_MAX_CHARGES: int = 1
const SPELL_SUPERTORNADO_CAST_RANGE: float = 12.0

const SPELL_EARTHQUAKE_CHARGE_COST: float = 400.0
const SPELL_EARTHQUAKE_MAX_CHARGES: int = 2
const SPELL_EARTHQUAKE_CAST_RANGE: float = 11.0

const SPELL_VOLCANO_CHARGE_COST: float = 1600.0
const SPELL_VOLCANO_MAX_CHARGES: int = 1
const SPELL_VOLCANO_CAST_RANGE: float = 12.0

const SPELL_FIRESTORM_CHARGE_COST: float = 775.0
const SPELL_FIRESTORM_MAX_CHARGES: int = 2
const SPELL_FIRESTORM_CAST_RANGE: float = 12.0

const SPELL_FLATTEN_CHARGE_COST: float = 300.0
const SPELL_FLATTEN_MAX_CHARGES: int = 3
const SPELL_FLATTEN_CAST_RANGE: float = 10.0

const SPELL_SINK_CHARGE_COST: float = 350.0
const SPELL_SINK_MAX_CHARGES: int = 3
const SPELL_SINK_CAST_RANGE: float = 10.0

## --- Hypnose (Zauber 12, Phase 10k) ---
## Bekehrt gegnerische Anhänger in einem kleinen Quadrat VORÜBERGEHEND zum
## eigenen Stamm; sie sind so lange normal steuerbar. Die Schamanin ist immun,
## Prediger sind es NICHT (anders als bei der Bekehrung).
const SPELL_HYPNOSIS_CHARGE_COST: float = 210.0
const SPELL_HYPNOSIS_MAX_CHARGES: int = 3
const SPELL_HYPNOSIS_CAST_RANGE: float = 10.0
## Kantenlänge des Wirkquadrats (m) und Dauer des Kontrollwechsels (s).
const HYPNOSIS_AREA_SIZE: float = 4.0
const HYPNOSIS_DURATION: float = 30.0

## --- Golem beschwören (Zauber 13, 2026-09-06) ---
## Beschwoert am Zielpunkt einen Golem (Werte GOLEM_* oben). Zwischen Feuerregen
## (775) und Supertornado (1200): 400 LP und drei Minuten Lebenszeit sind stark,
## aber der Golem ist beschiessbar und zeitlich begrenzt (Nutzerentscheidung).
const SPELL_GOLEM_CHARGE_COST: float = 900.0
const SPELL_GOLEM_MAX_CHARGES: int = 2
const SPELL_GOLEM_CAST_RANGE: float = 10.0
## Zauber 14 "Daemonengolem beschwoeren" (2026-11-16): Ladungen und Reichweite wie
## der Golem, die Ladung kostet ein Drittel weniger (Nutzervorgabe 2026-11-16:
## 900 -> 600). Vorerst nur beim menschlichen Spieler in der Leiste
## (Spell.create_player_set), Taste C.
const SPELL_DEMON_GOLEM_CHARGE_COST: float = SPELL_GOLEM_CHARGE_COST * 2.0 / 3.0
const SPELL_DEMON_GOLEM_MAX_CHARGES: int = SPELL_GOLEM_MAX_CHARGES
const SPELL_DEMON_GOLEM_CAST_RANGE: float = SPELL_GOLEM_CAST_RANGE
## Zauber 15 "Genesisgolem beschwoeren" (Nutzervorgabe 2026-11-17): Kosten wie der
## Daemonengolem. Nur beim menschlichen Spieler (Spell.create_player_set), Taste Y.
const SPELL_GENESIS_GOLEM_CHARGE_COST: float = SPELL_DEMON_GOLEM_CHARGE_COST
const SPELL_GENESIS_GOLEM_MAX_CHARGES: int = SPELL_DEMON_GOLEM_MAX_CHARGES
const SPELL_GENESIS_GOLEM_CAST_RANGE: float = SPELL_DEMON_GOLEM_CAST_RANGE

# =============================================================================
# ZAUBER — Effektwerte
# =============================================================================

# --- Feuerball (auch je Bolt des Feuerregens) ---
## Phase 10k: 60/30 -> 20/10. Der Feuerball toetet damit keinen Braves mehr
## direkt (60 war genau ein Brave-Leben) — er wird von der Toetungs- zur
## Stoerwaffe: er wirbelt eine ganze Traube durch die Luft und unterbricht
## Kaempfe, Bekehrungen und Arbeit. Bei 30 Mana und 4 Ladungen der Dauerzauber.
const FIREBALL_DIRECT_DAMAGE: int = 20
const FIREBALL_SPLASH_DAMAGE: int = 10
## Wirbelhoehen in Metern (Phase 10k): der Direkttreffer fliegt hoeher als die
## Splash-Opfer. Der Sturzschaden folgt daraus ueber CLIFF_FALL_DAMAGE_PER_M —
## 4 m ergeben 24 HP, 2 m ergeben 12 HP, es gibt also kein eigenes Schadensmodell
## fuer den Wirbel. Deckel bleibt LIFT_MAX_HEIGHT.
const FIREBALL_WHIRL_DIRECT: float = 4.0
const FIREBALL_WHIRL_SPLASH: float = 2.0
## Der Feuerball verfolgt das beim Ausloesen erfasste Ziel, solange es sich nicht
## weiter als das vom eigentlichen Zielpunkt entfernt (in der 1,0-s-Zauberzeit
## laeuft eine Einheit bis zu 4 m). Darueber schlaegt er auf dem Punkt ein.
const FIREBALL_CHASE_MAX_DRIFT: float = 6.0
## Umkreis um den Zielpunkt, in dem beim Ausloesen nach einem Verfolgungsziel
## gesucht wird.
const FIREBALL_ACQUIRE_RADIUS: float = 2.0
const FIREBALL_DIRECT_RADIUS: float = 0.8
const FIREBALL_SPLASH_RADIUS: float = 2.5
## Fluggeschwindigkeit (m/s) des Schamanen-Feuerballs bzw. jedes Feuerregen-Bolts.
const FIREBALL_BOLT_SPEED: float = 16.0

# --- Blitz ---
const LIGHTNING_UNIT_DAMAGE: int = 240     # 4 x Brave-Leben
const LIGHTNING_BUILDING_STAGES: int = 2

# --- Insektenschwarm ---
const SWARM_LIFETIME: float = 10.0
const SWARM_RADIUS: float = 3.0
const SWARM_DPS: int = 5
## Panik-Dauer (gilt auch für andere Panik-Quellen, z. B. Brand).
const PANIC_DURATION: float = 6.0

# --- Tornado ---
const TORNADO_LIFETIME: float = 10.0
const TORNADO_RADIUS: float = 2.2
## Alle X Sekunden +1 Zerstörungsstufe am überstrichenen Gebäude.
const TORNADO_STAGE_INTERVAL: float = 2.0
const TORNADO_FALL_DAMAGE: int = 30        # 1/2 Brave-Leben

# --- Supertornado (großer Haupt-Trichter; Satelliten = normaler Tornado) ---
const SUPERTORNADO_RADIUS: float = 4.4                 # doppelt so breit (2 x 2.2)
const SUPERTORNADO_TOP_HEIGHT: float = 12.0            # 12 m hoch
const SUPERTORNADO_LIFETIME: float = 16.0              # 16 s
const SUPERTORNADO_SATELLITE_COUNT: int = 2
const SUPERTORNADO_SATELLITE_DIST: float = 6.0         # Spawn-Abstand der kleinen

# --- Feuerregen (Phase 10k: Dauerbeschuss statt Salve) ---
## Streuung +30 % (5,5 -> 7,2), Dauer 3 -> 20 s, und die Baelle fallen in
## ZUFAELLIGEN Abstaenden mit Mittel 0,3 s — es koennen also auch zwei kurz
## nacheinander kommen. BOLT_COUNT ist nur noch die Obergrenze gegen
## Endlosschleifen (~67 Baelle sind zu erwarten).
const FIRESTORM_BOLT_COUNT: int = 120
const FIRESTORM_SPREAD_RADIUS: float = 7.2
const FIRESTORM_DURATION: float = 20.0
## Zufaelliger Abstand zwischen zwei Baellen, gleichverteilt in [MIN, MAX];
## das Mittel ist FIRESTORM_INTERVAL_MEAN.
const FIRESTORM_INTERVAL_MIN: float = 0.05
const FIRESTORM_INTERVAL_MAX: float = 0.55
## Schaden je Ball (Nutzervorgabe) — KEIN Hochwirbeln, dafuer Brand.
const FIRESTORM_DIRECT_DAMAGE: int = 20
const FIRESTORM_SPLASH_DAMAGE: int = 10
## Gebaeudeschaden je Ball. "Wie ein Nahkampfangriff von einem Krieger": ein
## Kriegerschlag ist MELEE_PUNCH/MELEE_KICK (6/8) x melee_strength() 3,0 = 18-24
## HP, die 20 liegen also genau in dieser Spanne. Ueber ~67 Baelle summiert das
## auf ~1340 HP im Zielgebiet — dass dabei Gebaeude fallen, ist gewollt.
const FIRESTORM_BUILDING_DAMAGE: int = 20
## Panik ausserhalb der Streuung: wer nah genug am Feuersturm steht, um ihn zu
## sehen, aber ausserhalb der Einschlaege ist, geraet in Panik. Die Schamanin ist
## global immun (Unit.is_panic_immune).
const FIRESTORM_PANIC_RADIUS: float = 11.5

# --- Erdbeben ---
const EARTHQUAKE_RADIUS: float = 7.0
const EARTHQUAKE_BUILDING_STAGES: int = 2
const EARTHQUAKE_UNIT_DAMAGE: int = 15     # 1/4 Brave-Leben

# --- Erdbeben-Lava (Phase 10c) ---
## EIN Lavateppich statt mehrerer Rinnsale: halbe Breite quer zur Fließrichtung,
## also entlang der Bruchkante (Nutzervorgabe — er soll auf ganzer Länge der
## Kante hinunterlaufen).
const EARTHQUAKE_LAVA_HALF_WIDTH: float = 5.0
## Versatz von der Bruchlinie auf die HEBUNGSSEITE (obere Kante).
const EARTHQUAKE_LAVA_EDGE_OFFSET: float = 0.8
## Wartezeit, bis der TerrainMorph die Kante geöffnet hat.
const EARTHQUAKE_LAVA_DELAY: float = 1.2
const EARTHQUAKE_LAVA_RANGE: float = 3.5

# --- Vulkan ---
## Phase 10k: breiter (5,0 -> 7,0) und mit echtem KRATER statt spitzem Kegel.
const VOLCANO_RADIUS: float = 7.0
## Lage des Kraterrands als Anteil des Radius — dort ist der hoechste Punkt, und
## der Kreis darin ist nach dem Ausbruch das kleine Gipfelplateau.
const VOLCANO_RIM_FRACTION: float = 0.55
## Tiefe der Mulde UNTER dem Rand. Die Lava quillt darin hoch, steigt ueber den
## Rand und laeuft dann aussen hinunter.
const VOLCANO_CRATER_DEPTH: float = 1.5
## Lebensdauer der Vulkanlava — laenger als LAVA_LIFETIME, weil es nur noch EINEN
## Schwall gibt (Nutzervorgabe) und der dafuer weiter kommen soll.
const VOLCANO_LAVA_LIFETIME: float = 8.0
## Lebensdauer der aktiven Vulkanzone (Lava/Stufenschaden).
const VOLCANO_ZONE_LIFETIME: float = 20.0
## Gezählte Lavastöße je Ausbruch (robust gegen spätere Lifetime-Änderungen).
## EIN grosser Schwall statt zwei kleiner (Nutzervorgabe Phase 10k).
const VOLCANO_SURGE_COUNT: int = 1
## ACHTUNG: > LAVA_MOLTEN_TIME + LAVA_BUILDING_CONTACT_GRACE schaltet den
## Gebäudeschaden des Vulkans still ab (Herleitung in plans/10c).
const VOLCANO_SURGE_INTERVAL: float = 3.5

# --- Ebene / Absinken / Landbrücke ---
const FLATTEN_HALF_EXTENT: float = 4.5     # halbe Kantenlänge des Quadrats
const SINK_RADIUS: float = 6.0
const SINK_DEPTH: float = 3.0
const LANDBRIDGE_HALF_WIDTH: float = 1.6

# --- Klippensturz (Kampf-Stoß / Rollen über eine Klippenkante) ---
## Mindest-Höhendifferenz (m) voraus, ab der ein Sturz statt eines Stopps an der
## Kante ausgelöst wird — knapp über MAX_SLOPE (1.5), damit begehbare Steilhänge
## nicht auslösen.
const CLIFF_FALL_MIN_DROP: float = 1.6
## Sample-Distanz voraus (m), um die tiefer liegende Fläche jenseits der Kante zu treffen.
const CLIFF_PROBE_DIST: float = 2.0
## Fallschaden pro gestürztem Meter, gedeckelt auf 1/2 Brave-Leben.
const CLIFF_FALL_DAMAGE_PER_M: float = 6.0
const CLIFF_FALL_MAX_DAMAGE: int = 30   # 30
## Rolldauer pro gestürztem Meter (s), geklemmt auf
## [MINI_ROLL_DURATION, CLIFF_ROLL_MAX_DURATION].
const CLIFF_ROLL_PER_M: float = 0.33
const CLIFF_ROLL_MAX_DURATION: float = 3.0
## Horizontale/vertikale Startgeschwindigkeit des Sturzes (m/s): der kleine
## Aufwärtsimpuls hebt die Einheit über die Kante, bevor sie hinabfällt.
const CLIFF_LAUNCH_SPEED: float = 4.0
const CLIFF_LAUNCH_UP: float = 3.5

# =============================================================================
# GEBÄUDE — Kosten, Leben, Ausbildung
# =============================================================================

## Schadensanteil pro Zerstörungsstufe (Stufen bei 30/60/90/100 %).
##
## ALLE Gebäude-HP wurden am 2026-09-08 um 50 % erhöht (Nutzervorgabe). Die
## Zerstörungsstufen sind bewusst RELATIV: apply_destruction_stages() rechnet
## ceil(BUILDING_STAGE_DAMAGE * max_health), also bleibt es bei jedem HP-Stand
## bei genau einer Stufe je Katapult-/Rammentreffer (vier Treffer = zerstört) —
## dieselbe Vorgabe. Schadensquellen mit FESTEM HP-Betrag wurden dabei bewusst
## NICHT nachgezogen und sind damit relativ ein Drittel schwächer:
## FIREWARRIOR_BUILDING_DAMAGE, FIRESTORM_BUILDING_DAMAGE (~67 -> ~100 Bälle je
## Gebäude) und RAID_DPS_PER_RAIDER (Nahkampf-Abriss 50 % länger).
const BUILDING_STAGE_DAMAGE: float = 0.3
## Schaden am Insassen beim Fernkampf-Rauswurf (Feuerkrieger-Stufe-1,
## Katapult-Treffer): 1 x Brave-Leben. Braves/Feuerkrieger sterben daran beim
## Ausrollen, zähere Einheiten (Krieger, Prediger, Schamanin) können den
## Rauswurf überleben; der normale Rollschaden kommt obendrauf.
const BUILDING_EJECT_RANGED_DAMAGE: int = 60
## Abriss-Schaden pro Nahkampf-Angreifer im Gebäude (HP/s).
const RAID_DPS_PER_RAIDER: float = 6.0
## Maximale gleichzeitige Nahkampf-Abreißer pro Gebäude.
const MAX_MELEE_RAIDERS: int = 15

# --- Abriss (Entf) & Bauverfall ---
## Erstattung beim Abriss OHNE erreichte Baustufe (build_progress == 0): das
## eingesetzte Holz kommt vollständig als Bodenstapel zurück.
const DEMOLISH_REFUND_UNBUILT: float = 1.0
## Erstattung ab Baustufe 1 und bei fertigen Gebäuden: drei Viertel.
const DEMOLISH_REFUND_BUILT: float = 0.75
## Abrissrate als Faktor auf Brave.BUILD_RATE (1.0 = gleich schnell wie Bauen).
## 0.5 = doppelt so lange wie Bauen: der Abriss lief mit 1.0 praktisch
## augenblicklich durch (Nutzerbefund 2026-08-04).
const DEMOLISH_RATE_FACTOR: float = 0.5
## Sekunden ohne jeden Baufortschritt (kein Holz, keine Planierung, kein
## Aufbau), nach denen eine Baustelle von selbst verfällt.
const CONSTRUCTION_STALL_TIMEOUT: float = 120.0
## Erstattung einer verfallenen Baustelle (Anteil des gelieferten Holzes).
const CONSTRUCTION_STALL_REFUND: float = 1.0

# --- Baustellen-Robustheit (Phase 10i) ---
## Eine Planierzelle, die so lange von keinem Arbeiter erreicht wurde, fällt aus
## der Pflichtliste — eine einzige unerreichbare Zelle darf keine Baustelle
## dauerhaft blockieren (sonst wird `foundation_done` nie true und damit ist
## `add_build_progress` für immer gesperrt).
const FLATTEN_CELL_TIMEOUT: float = 25.0
## Absolutes Limit für eine Baustelle, die NIE in die Bauphase kommt
## (build_progress == 0). Fängt den Fall, in dem Teilbuchungen den
## Signatur-Timer von CONSTRUCTION_STALL_TIMEOUT immer wieder zurückstellen.
const CONSTRUCTION_NO_START_TIMEOUT: float = 180.0

## Bauplan-Größen (Footprint in Zellen, Breite x Tiefe; 1 Zelle = 1 m).
## Der Eingang liegt auf der Südseite; nicht-quadratische Footprints werden
## beim Drehen automatisch getauscht.
const HUT_FOOTPRINT: Vector2i = Vector2i(4, 4)
const WARRIOR_CAMP_FOOTPRINT: Vector2i = Vector2i(5, 5)
const TEMPLE_FOOTPRINT: Vector2i = Vector2i(6, 6)
const FIREWARRIOR_CAMP_FOOTPRINT: Vector2i = Vector2i(8, 8)
const FORESTER_FOOTPRINT: Vector2i = Vector2i(2, 4)
const WORKSHOP_FOOTPRINT: Vector2i = Vector2i(7, 4)
## Schmale Front, tiefe Halle (2026-09-08, war 6 x 4): die Rammenwerkstatt
## ist damit keine breite Kopie der Katapultwerkstatt mehr.
const FIRERAM_WORKSHOP_FOOTPRINT: Vector2i = Vector2i(3, 6)
const AIRSHIP_WHARF_FOOTPRINT: Vector2i = Vector2i(8, 8)
const WATCHTOWER_FOOTPRINT: Vector2i = Vector2i(2, 2)
const WOOD_DEPOT_FOOTPRINT: Vector2i = Vector2i(1, 1)
const REINCARNATION_SITE_FOOTPRINT: Vector2i = Vector2i(3, 3)
## Freier Rand um jedes Gebaeude (Zellen = Meter, Nutzervorgabe 2026-11-16): ein neuer
## Bauplatz darf keiner Zelle eines anderen Gebaeudes (auch einer Baustelle) naeher
## kommen als so viele Zellen - zwischen zwei Gebaeuden bleibt also mindestens
## dieser Abstand frei. 0 = dicht an dicht wie bisher.
const BUILDING_MIN_GAP: int = 1

# --- Hütte (Phase 10f: klein und billig, in vier Stufen zum Wohnpalast) ---
const HUT_WOOD_COST: int = 7               # war 12, dann 8 (10h)
const HUT_HP: int = 450                    # == HUT_HP_PER_STAGE[0]
## Plätze/Arbeiter/Leben je Ausbaustufe (Index = Stufe 0..4). Stufe 4 bringt
## bewusst +11 statt +8 Plätze — der Wohnpalast ist der Lohn für den Vollausbau.
## Ein Platz kostet damit 0,8 Holz auf Stufe 0 (8/10) und 0,62 im Vollausbau
## (28/45) — vorher waren es 0,3 (12/40), Wohnraum ist also doppelt so teuer.
const HUT_CAPACITY_PER_STAGE: Array[int] = [10, 18, 26, 34, 45]
const HUT_CREW_PER_STAGE: Array[int] = [2, 3, 4, 5, 6]
const HUT_HP_PER_STAGE: Array[int] = [450, 510, 570, 630, 720]
const HUT_MAX_UPGRADE_STAGE: int = 4
## Sekunden je Brave und ARBEITER: die Rate ist linear in der Besatzung, es gibt
## keinen Voll-Besatzungs-Bonus mehr. Stufe 0 (2 Arbeiter) 15 s/Brave,
## Stufe 4 (6 Arbeiter) 5 s/Brave.
const HUT_SPAWN_SECONDS_PER_WORKER: float = 30.0
## Wartezeit nach Fertigstellung bzw. nach dem letzten Ausbau, bis das nächste
## Upgrade fällig wird.
const HUT_UPGRADE_DELAY: float = 90.0
const HUT_UPGRADE_WOOD_COST: int = 4       # war 5 (10h)
## Bauzeit-Faktor des Ausbaus auf Brave.BUILD_RATE.
const HUT_UPGRADE_RATE_FACTOR: float = 1.0
## Ein Ausbau STARTET nur, wenn in diesem Radius überhaupt Holz erreichbar ist
## (Bäume, Bodenstapel oder ein Holzlager mit Bestand) — sonst würde die Hütte
## ihre Besatzung in eine aussichtslose Holzsuche auswerfen.
const HUT_UPGRADE_WOOD_RADIUS: float = 40.0
## Kein Fortschritt so lange -> Ausbau abbrechen und das gelieferte Holz am
## Bauplatz zurückgeben (Muster CONSTRUCTION_STALL_TIMEOUT). Fängt den Fall,
## dass die ausgeworfene Besatzung unterwegs stirbt oder abgezogen wird.
const HUT_UPGRADE_STALL_TIMEOUT: float = 120.0

# --- Kaserne (Krieger) ---
const WARRIOR_CAMP_WOOD_COST: int = 10
const WARRIOR_CAMP_HP: int = 600
const WARRIOR_CAMP_TRAINING_TIME: float = 3.0

# --- Tempel (Prediger) ---
const TEMPLE_WOOD_COST: int = 15
const TEMPLE_HP: int = 660
const TEMPLE_TRAINING_TIME: float = 5.0

# --- Feuertempel (Feuerkrieger) ---
const FIREWARRIOR_CAMP_WOOD_COST: int = 18  # war 20 (10h)
const FIREWARRIOR_CAMP_HP: int = 900
const FIREWARRIOR_CAMP_TRAINING_TIME: float = 4.0

# --- Förster ---
const FORESTER_WOOD_COST: int = 18
const FORESTER_HP: int = 375
## Mana/s je aktivem Arbeiter im Gebäude (Phase 10k: 1,5 -> 0,6; eine volle
## Försterei kostet damit 2,4 Mana/s). Mit 1,5 hätten fünf Förstereien nach der
## gedämpften Manakurve das GESAMTE Einkommen aufgefressen.
const FORESTER_MANA_PER_WORKER: float = 0.6
## Arbeiter-Sekunden pro gepflanztem Baum (4 Arbeiter -> 15 s).
const FORESTER_PLANT_WORK_PER_TREE: float = 50.0

# --- Katapultwerkstatt ---
const WORKSHOP_WOOD_COST: int = 12          # war 13 (10h)
const WORKSHOP_HP: int = 525
## Arbeiter-Sekunden pro Katapult (3 Arbeiter -> 20 s).
## Regel: Produktionsaufwand = Holzkosten des Fahrzeugs x 10 Arbeiter-Sekunden.
const WORKSHOP_WORK_PER_CATAPULT: float = 60.0
const WORKSHOP_CATAPULT_WOOD: int = 6

# --- Feuerrammenwerkstatt ---
const FIRERAM_WORKSHOP_WOOD_COST: int = 10  # war 11 (10h)
const FIRERAM_WORKSHOP_HP: int = 525
## Arbeiter-Sekunden pro Feuerramme (3 Arbeiter -> ~13 s); 4 Holz x 10.
const FIRERAM_WORK_PER_RAM: float = 40.0
const FIRERAM_WOOD: int = 4

# --- Luftschiffwerft ---
const AIRSHIP_WHARF_WOOD_COST: int = 20
const AIRSHIP_WHARF_HP: int = 750
const WHARF_WORKER_SLOTS: int = 4
## Arbeiter-Sekunden pro Luftschiff (4 Arbeiter -> 20 s); 8 Holz x 10.
const WHARF_WORK_PER_AIRSHIP: float = 80.0
const WHARF_AIRSHIP_WOOD: int = 8

# --- Holzstation ---
const WOOD_DEPOT_WOOD_COST: int = 1
const WOOD_DEPOT_HP: int = 180
## Storage cap = 4 stock piles x WoodPile.MAX_AMOUNT.
const WOOD_DEPOT_CAPACITY: int = 20

# --- Wachturm ---
const WATCHTOWER_WOOD_COST: int = 4
const WATCHTOWER_HP: int = 300
## Reichweiten-Bonus für stationierte Fernkämpfer/Prediger.
const WATCHTOWER_RANGE_BONUS: float = 3.0
## Wachtürme sind klein: weniger gleichzeitige Abreißer als der Standard.
const WATCHTOWER_MAX_RAIDERS: int = 5

# --- Reinkarnationsplatz ---
const REINCARNATION_SITE_HP: int = 750

# =============================================================================
# STAMM / WIRTSCHAFT
# =============================================================================

## Mana/s je wirksamem Bevölkerungsmitglied (Phase 10k: 0,1 -> 0,11).
const MANA_BASE_RATE: float = 0.11

# --- Manakurve (Phase 10k) ----------------------------------------------------
# Die Erzeugung war linear und unbegrenzt: 1000 Anhänger lieferten das Zehnfache
# von 100. Ab MANA_SOFT_CAP dämpft eine logarithmische Kurve das auf ~1/4 je
# weiterem Kopf.
#
# WARUM GENAU DIESE ZAHLEN: sie sind nicht gefittet, sie fallen aus den
# Zielwerten heraus. 400/10000 = 0,04, also ist der Logarithmus bei 500
# Anhängern EXAKT ln(1,04) und der Bruch exakt 1 -> genau die doppelte
# Produktion. Bei 1000 ergibt ln(1,09)/ln(1,04) = 2,1972 -> 3,197-fach.
# Der Beitrag des 101. Anhängers ist 25,5 % eines Kopfes unterhalb der Grenze
# und fällt bis 1000 nur auf 23,4 % — die Kurve liegt also über ihre ganze Länge
# an der Vorgabe "ein Viertel je neuem Mitglied".
## Bis hierhin zählt jeder Anhänger voll (linear wie bisher).
const MANA_SOFT_CAP: int = 100
const MANA_LOG_SCALE: float = 10000.0
const MANA_LOG_BASE: float = 1.04

## Mana/s je Trainingsgebäude, das GERADE ausbildet (Phase 10k). Bewusst
## derselbe Wert wie FORESTER_MANA_PER_WORKER — Nutzervorgabe: "so viel wie ein
## Försterarbeiter". Wer nur in der Warteschlange steht, kostet nichts, und
## Fahrzeugbau wie Hütten-Bevölkerung kosten GAR kein Mana (die Buchung hängt
## an TrainingBuilding.trainee, nicht an Building).
const TRAINING_MANA_PER_BUILDING: float = 0.6

## Zeitbudget der KI-Zauberwahl (Phase 10k): aktiv bleibt, was in so vielen
## Sekunden ladbar ist — ungefaehr eine Angriffswelle. Reicht es fuer keinen
## einzigen Zauber, laedt sie trotzdem den billigsten, denn Einkommen ohne
## Abnehmer verfaellt (kein Mana-Banking).
const AI_SPELL_TIME_BUDGET: float = 120.0
## Hardcap Einheiten pro Stamm (zusätzlich zum Hütten-Bevölkerungslimit).
const TRIBE_MAX_UNITS: int = 1000

# --- Bäume ---
## Sekunden pro Wachstumsstufe (deterministisch; durch den Bodenfaktor des
## Baumtyps geteilt). Wachstum ist KONTINUIERLICH: `growth` (in Stufen) steigt
## mit Faktor / TREE_GROWTH_TIME pro Sekunde, die Holzstufe ist floor(growth),
## das Modell skaliert stufenlos (quantisiert, s. TreeResource.GROWTH_SCALE_QUANT).
const TREE_GROWTH_TIME: float = 75.0
## Holz-Ertrag je Wachstumsstufe (Index = Stufe 0..4).
const TREE_YIELDS: Array[int] = [0, 1, 2, 3, 4]

## Parameter je Baumtyp, indiziert per TreeResource.TreeType (STANDARD/LEAF/
## BAMBOO). growth_*/repro_* sind Multiplikatoren auf Wachstum/Vermehrung je
## nach Untergrund (Gras vs. Nicht-Gras, TerrainData.is_grass); Faktor 0 heißt
## Pause bzw. keine Sprossen. max_stage begrenzt Wachstum UND Ertrag (Bambus:
## Stufe 2 = max. 2 Holz über TREE_YIELDS). min_spacing/density_limit steuern,
## wie dicht der Typ stehen darf; grass_only-Typen sprießen nur auf Gras.
const TREE_TYPE_PARAMS: Array[Dictionary] = [
	{ "growth_grass": 1.0, "growth_off": 1.0,  "repro_grass": 1.0, "repro_off": 1.0,
	  "max_stage": 4, "min_spacing": 2, "density_limit": 6, "grass_only": false,
	  "model": "models/trees/tree.glb",
	  "stage_scales": [0.28, 0.35, 0.55, 0.8, 1.0] },
	{ "growth_grass": 1.5, "growth_off": 0.75, "repro_grass": 1.2, "repro_off": 0.6,
	  "max_stage": 4, "min_spacing": 2, "density_limit": 6, "grass_only": false,
	  "model": "models/trees/tree_leaf.glb",
	  "stage_scales": [0.28, 0.35, 0.55, 0.8, 1.0] },
	{ "growth_grass": 1.0, "growth_off": 0.0,  "repro_grass": 3.0, "repro_off": 0.0,
	  "max_stage": 2, "min_spacing": 1, "density_limit": 18, "grass_only": true,
	  "model": "models/trees/tree_bamboo.glb",
	  "stage_scales": [0.3, 0.65, 1.0] },
]
## Startbestand (Map-Gen): Typ-Anteile der Wildverteilung auf Gras-Zellen
## (Nicht-Gras bleibt immer Standard) plus reine Laub-/Bambus-Haine.
const TREE_LEAF_SHARE: float = 0.20
const TREE_BAMBOO_SHARE: float = 0.10
const TREE_GROVES_PER_STANDARD_MAP: int = 3   # Haine je Standardkarte (skaliert wie TREE_COUNT)
## Holz-Zuschlag beim Start auf KLEINEN Karten (10h, Nutzervorgabe): dort liegen die
## Basen eng zusammen, jeder Stamm hat also weniger Wald für sich. Der Zuschlag gilt
## für Bäume UND Haine, damit sich das Verhältnis der Baumarten nicht verschiebt.
const SMALL_MAP_WOOD_BONUS: float = 1.2
## Bis zu dieser Kantenlänge gilt eine Karte als klein (Insel und Plateau: 144;
## Seenland und Bergpass: 288). Folgt der Standardkarte, NICHT `TerrainData.SIZE`
## — das ist seit Phase 10j nur noch die Default-/Testgröße (128).
const SMALL_MAP_MAX_SIZE: int = MapGenerator.STANDARD_SIZE
const TREE_GROVE_TREES_MIN: int = 8
const TREE_GROVE_TREES_MAX: int = 14
const TREE_GROVE_RADIUS: int = 6

# --- Flächen-Holzernte (Taste B) ---
## Kleinere Ziehflächen gelten als Fehlklick; größere werden um ihren
## Mittelpunkt geklemmt (ein Ganzkarten-Zug darf keinen absurden Dauerauftrag
## erzeugen).
const HARVEST_AREA_MIN_SIDE: float = 2.0
const HARVEST_AREA_MAX_SIDE: float = 80.0
## Bestätigungs-Blinken um beauftragte Bäume: zweimal an/aus.
const TREE_MARK_BLINKS: int = 2
const TREE_MARK_BLINK_TIME: float = 0.18
## Innerhalb dieses Radius wird ein Holzlager dem nächsten Gebäude vorgezogen.
const HARVEST_DEPOT_PREFER_RADIUS: float = 40.0

# =============================================================================
# KI (Skirmish-Gegner, Phase 10e)
# =============================================================================
# Nur Balance-Werte. Rein mechanische Zahlen (Tickrate, Zauber-Heuristik,
# Cache-Lebensdauern) bleiben als lokale Konstanten im AIController.

# --- Wirtschaft / Holzlogistik ---
## Bodensatz an Braves, die nie ins Training gehen, plus ein Anteil des Stammes:
## ein 300-Seelen-Stamm braucht mehr als die alten fixen 8 Arbeiter.
const AI_MIN_ECONOMY_BRAVES: int = 8
const AI_ECONOMY_BRAVE_SHARE: float = 0.35
## Fäll-Trupps: Größe, Braves je Trupp und Deckel. Unter AI_BRAVES_PER_WOOD_CREW
## Braves gibt es GAR keinen Trupp — das Frühspiel bleibt damit unverändert.
const AI_WOOD_CREW_SIZE: int = 6
## 10h Teil 3: 12 -> 9 und 4 -> 6. Nutzerwunsch "am besten ist es, Leute direkt zum
## Holz holen zu schicken" — der erste Trupp faellt damit frueher und die Truppzahl
## skaliert schneller mit dem Stamm.
const AI_BRAVES_PER_WOOD_CREW: int = 9
const AI_MAX_WOOD_CREWS: int = 6
## Die Holzlogistik läuft nur auf jedem n-ten KI-Tick (Hain-Suche ist teuer).
const AI_WOOD_TICK_INTERVAL: int = 3
const AI_WOOD_GROVE_TTL_TICKS: int = 30
## Ab dieser Entfernung des Hains von der Basis lohnt ein vorgeschobenes Lager.
const AI_FORWARD_DEPOT_DISTANCE: float = 35.0
## Eskorten für blockierte Baustellen je Holz-Tick (jede kostet eine Hain-Suche).
const AI_STALLED_ESCORTS_PER_TICK: int = 2
const AI_BRAVES_PER_FORESTER: int = 25
const AI_MAX_FORESTERS: int = 4
## Ab so vielen Braves füllt die KI ihre Förstereien über die alten 2 hinaus auf.
const AI_FORESTER_WORKER_STEP: int = 30

# --- Bautrupps (10g Teil 1) ---
## Vor 10g wies die KI Baustellen NIE Arbeiter zu: sie verliess sich ganz auf
## BuildingManager._recruit_workers (nur idle Braves im 30-m-Umkreis), waehrend
## Bauplaetze bis AI_PLOT_SEARCH_RADIUS Zellen draussen liegen und Training,
## Faell-Trupps und Werkstaetten den Idle-Pool vorher leerten.
## Eine Hand je so vielen Planierzellen: Planieren ist Zellarbeit
## (Building.claim_flatten_cell), Aufbauen nicht (BUILD_RATE 0.2/s = 5 Arbeitersek.).
const AI_FLATTEN_CELLS_PER_WORKER: int = 6
## Trupp-Grenzen je Baustelle. AI_SITE_WORKERS_MAX liegt BEWUSST unter
## Building.MAX_WORKERS (10): die freien Plaetze bleiben dem passiven
## Rekrutierer, damit sich beide Systeme nicht verdraengen.
const AI_SITE_WORKERS_MIN: int = 2
const AI_SITE_WORKERS_MAX: int = 8
## Nach dem Fundament zaehlt nur Holznachschub: ein Traeger mehr je so vielen
## fehlenden Holz (Brave.CARRY_CAPACITY 3 je Fuhre).
const AI_WOOD_PER_EXTRA_BUILDER: int = 6
const AI_SITE_WORKERS_BUILD_MAX: int = 5
## Ab so vielen Arbeitern gilt eine Baustelle als versorgt (Tor fuer eine NEUE).
const AI_SITE_SUPPLIED_WORKERS: int = 2
## Anteil der Braves, der maximal ans Bauen gebunden wird, plus Bodensatz.
## Geklemmt auf AIState.min_economy_braves(population) — Bauen teilt die
## Wirtschaftsmannschaft auf, es frisst nicht den Armee-Anteil.
const AI_BUILDER_BRAVE_SHARE: float = 0.40
const AI_MIN_BUILDER_BRAVES: int = 4
## Baustellen, die pro Tick neu bestueckt werden (Befehls-Churn + take_idle_for).
const AI_SITES_STAFFED_PER_TICK: int = 3
## Braves werden nur aus diesem Umkreis einer Baustelle gezogen. AUSNAHME: eine
## Baustelle mit NULL Arbeitern bekommt ihre Mindestbesatzung aus beliebiger
## Entfernung — "gar niemand" ist der gemeldete Fehler.
const AI_BUILDER_WALK_RADIUS: float = 80.0
## Ticks, die eine unversorgte Baustelle das Tor blockieren darf
## (Verklemmungsschutz), und Sperrfrist nach einem order_build ohne Zuweisung.
const AI_SITE_SUPPLY_GRACE_TICKS: int = 30
const AI_SITE_RETRY_TICKS: int = 10

# --- Bau / Skalierung ---
## Eine parallele Baustelle je AI_BRAVES_PER_SITE Braves, gedeckelt.
## ACHTUNG: der Divisor ist in test_build_tick_places_construction_site
## festgenagelt (10 Braves = 1 Baustelle, 20 = 2).
const AI_BRAVES_PER_SITE: int = 8
const AI_MAX_PARALLEL_SITES: int = 8
## Ringsuche für Bauplätze: Mindestabstand zum Anker (Gebäude kleben nicht mehr
## am Anker) bis Suchradius, plus Freihaltung um jeden Grundriss.
const AI_PLOT_MIN_RADIUS: int = 3
const AI_PLOT_SEARCH_RADIUS: int = 40
const AI_PLOT_SPACING: int = 2
## Gemeinsames Zellbudget für EINEN _find_plot-Aufruf (alle Anker + Relax-Pass).
## Vor 10e galten 800 Zellen PRO Sweep bei zwei Sweeps (theoretisch 1600); jetzt
## sind 800 die harte Obergrenze für die ganze Suche. Auf Seekarten laufen die
## Sweeps durch viele Wasserzellen, die `can_place_at` verwerfen ohne den
## Aufgabe-Zähler zu erhöhen — dort ist dieses Budget das einzige, was greift.
const AI_MAX_PLOT_SCAN_CELLS: int = 800
## 10f: Hütten sind viel kleiner (10 statt 40 Plätze), der alte Deckel von 30
## hätte den Stamm bei 300 Plätzen abgeschnürt. 60 Hütten sind im Vollausbau
## 2700 Plätze, ohne jeden Ausbau immer noch 600.
const AI_MAX_HUTS: int = 60
## Der Wohnraumdruck-Zweig darf nicht alle Baustellen-Slots mit Hütten füllen.
## 10f: eine Baustelle mehr, weil die kleinen Hütten schneller nachwachsen müssen.
const AI_MAX_HUT_SITES: int = 3
const AI_BRAVES_PER_WORKSHOP: int = 30
const AI_MAX_SHOPS_PER_KIND: int = 4
## Zusätzlicher Fahrzeug-Slot je so vielen Braves.
const AI_BRAVES_PER_VEHICLE_SLOT: int = 40
## Siedlungsanker (Basis + Hüttencluster + vorgeschobene Lager).
const AI_SETTLEMENT_TTL_TICKS: int = 60
const AI_SETTLEMENT_CLUSTER_RADIUS: int = 16
const AI_MAX_SETTLEMENT_ANCHORS: int = 4
## Trainingsschub: skaliert mit der Bravezahl.
const AI_TRAIN_BATCH_MIN: int = 3
const AI_TRAIN_BATCH_MAX: int = 12
const AI_BRAVES_PER_TRAIN_BATCH: int = 20
## Bauordnung (in AIState.next_building_kind gebraucht, deshalb hier statt im
## Controller — AIState darf nicht auf den Controller zurückgreifen).
## 10g: 0,8 -> 0,7, plus der ABSOLUTE Zweitauslöser darunter. Eine reine
## Prozentschwelle versagt bei den kleinen 10f-Hütten (80 % von 10 Plätzen = 8),
## und die Ausbaustufen lassen die Kapazität der Bevölkerung vorauslaufen — dann
## feuerte der Zweig gar nicht und die KI baute Werkstätten statt Hütten.
const AI_HOUSING_PRESSURE: float = 0.7
## Freie Wohnplätze, unter denen die KI unabhängig vom Prozentdruck eine Hütte
## plant.
const AI_MIN_HOUSING_HEADROOM: int = 12
const AI_TARGET_WATCHTOWERS: int = 2
## AI_HUTS_PER_EXTRA_CAMP ist in 10g entfallen: die Lagerzahl kommt jetzt aus dem
## BRAVESTROM (AIState.camp_targets), nicht aus der Hüttenzahl — ein Lager bildet
## eine Einheit auf einmal aus, der Durchsatz ist also das Maß.
const AI_MAX_CAMPS_PER_KIND: int = 4

# --- Ausbildungs-Routing über Hütten-Rally-Points (10g) ---
## Anteil der Hütten, deren Rally Point auf einem Ausbildungszentrum liegt: deren
## frische Braves gehen direkt in die Warteschlange, ohne Idle-Umweg und ohne
## Kommando pro Brave. MUSS unter 1,0 bleiben — zeigen ALLE Hütten auf Lager, hat
## der Stamm keine freien Braves mehr (keine Bauarbeiter, keine Holztrupps, keine
## Werkstattbesatzung) und die Wirtschaft stirbt ohne Fehlermeldung.
const AI_TRAINING_HUT_SHARE_BUILD: float = 0.25
const AI_TRAINING_HUT_SHARE_ARMY: float = 0.60
## Die Zuordnung ist träge: ein wandernder Rally Point schickt den Bravestrom
## zwischen den Lagern hin und her.
const AI_HUT_RALLY_TICK_INTERVAL: int = 10

# --- Armee-Mix ---
## Mehr Prediger (0,20 -> 0,30); die gleichzeitige Anhebung der Feuerkrieger ist
## beabsichtigt — sie sind der Konter gegen eine gegnerische Prediger-Masse.
const AI_ARMY_SHARE_WARRIOR: float = 0.40
const AI_ARMY_SHARE_FIREWARRIOR: float = 0.30
const AI_ARMY_SHARE_PREACHER: float = 0.30

# --- KI: Arena-Enge und zwei Baumuster (10g Teil 5) ---
## Neuberechnung des Basisabstands (ein Durchlauf ueber ALLE Gebaeude).
const AI_ARENA_TTL_TICKS: int = 60
## Unter diesem Abstand zur naechsten FEINDLICHEN Basis (Zellen = Meter) gilt die
## Arena als ENG. MapGenerator._circle_anchors setzt die Anker auf einen Kreis mit
## Radius 0,2 * size: Insel 144 mit 4 Staemmen 40,7 · mit 3 Staemmen 49,9 · mit 2
## Staemmen 57,6 · Plateau 144 (Eckanker, benachbart) 80 · Seenland/Bergpass 288
## deutlich mehr (162 bzw. 104).
## In Phase 10j mit den Kartenkanten mitskaliert (60 → 68 = 60 · 1,128), damit
## JEDE Karte ihre heutige Einstufung behaelt — das ist eine Kante, kein Regler:
## ein Umschlag aendert Suchradius (18↔40), Siedlungsanker (2↔4), Waechtertuerme
## (3↔2), Wellengroesse (8↔12) und Trainingsschwelle (12↔16) auf einen Schlag.
const AI_CRAMPED_ARENA: float = 68.0
## Verteidigungsradius relativ zum Basisabstand statt fixer 32 m: auf der Insel
## lagen die Nachbarbasen IM alten Radius, wodurch _detect_threat dauerhaft feuerte
## — Holzwirtschaft aus, nie ein echter Angriff, alle Braves als Miliz.
const AI_DEFEND_RADIUS_FACTOR: float = 0.35
const AI_DEFEND_RADIUS_MIN: float = 14.0
const AI_DEFEND_RADIUS_MAX: float = 32.0
## So viele Gegner braucht es, damit die Wirtschaft aussetzt bzw. eine laufende
## Angriffswelle zurueckgerufen wird. Ein einzelner Spaeher darf beides nicht.
const AI_ECONOMY_HALT_ENEMIES: int = 3
const AI_ATTACK_ABORT_ENEMIES: int = 5
## Miliz: Anteil des Idle-Pools (mindestens aber einer, solange einer idle ist —
## ein Raeuber IM Dorf muss auch von einem Fuenf-Brave-Stamm beantwortet werden).
const AI_MILITIA_MAX_SHARE: float = 0.5
## Kompaktes Baumuster (enge Arena) gegen die offenen Werte weiter oben.
const AI_PLOT_SEARCH_RADIUS_CRAMPED: int = 18
const AI_MAX_SETTLEMENT_ANCHORS_CRAMPED: int = 2
const AI_TARGET_WATCHTOWERS_CRAMPED: int = 3
const AI_ARMY_ATTACK_SIZE_CRAMPED: int = 8
const AI_POP_FOR_TRAIN_CRAMPED: int = 12

# --- KI: Bauplatz-Absicherung (10g Teil 2) ---
## Ticks, die eine als unerreichbar erkannte Zelle gesperrt bleibt. NICHT ewig wie
## vor 10g: eine Landbruecke kann sie spaeter anschliessen, und ein Sitzungs-Bann
## machte die KI dafuer blind.
const AI_PLOT_BAN_TICKS: int = 300
## Abstand im Anti-Aushunger-Durchgang: EIN Ring Luft statt gar keiner. Der
## Unterschied zwischen "eng gebaut" und "Eingang zugemauert".
const AI_PLOT_SPACING_RELAXED: int = 1
## Intervall (Ticks) der Nachkontrolle bestehender Baustellen und Strikes, bis eine
## als abgeschnitten gilt: Insel-Labels duerfen bis NavGrid.ISLAND_REFRESH_MS
## veralten, und eine wachsende Landbruecke braucht mehrere Ticks.
const AI_SITE_GUARD_INTERVAL: int = 5
const AI_SITE_GUARD_STRIKES: int = 2

# --- KI: Fahrzeug-Besatzung (10g Teil 3) ---
## Zielbesatzung = min_fire_crew + dieser Bonus (die Nachladezeit skaliert mit der
## Besatzung), geklemmt auf min_move_crew..max_crew.
const AI_VEHICLE_EXTRA_CREW: int = 1
## Hoechstens dieser Anteil der Armee darf gleichzeitig in Fahrzeugen sitzen.
const AI_VEHICLE_ARMY_CREW_SHARE: float = 0.25
## Braves bemannen Fahrzeuge nur bei echtem Ueberschuss ueber die
## Wirtschaftsreserve oder wenn es kaum Militaer gibt (Nutzerregel).
const AI_VEHICLE_BRAVE_SURPLUS: int = 12
const AI_VEHICLE_MILITARY_SCARCE: int = 6
## Fahrzeuge, die pro Tick aufgefuellt werden (Blockierer haben immer Vorrang).
const AI_VEHICLES_PER_TICK: int = 3
## Sammelpunkt-Abstand vor der Werkstatt; MUSS ueber Workshop.EXIT_CLEAR_RADIUS + 0.5
## liegen, sonst verwirft _dispatch_point ihn.
const AI_VEHICLE_MUSTER_DISTANCE: float = 12.0

# --- KI: Holznachschub und Werkstatt-Regal (10g Teil 4) ---
const AI_SUPPLY_BRAVES_PER_TARGET: int = 3
const AI_MAX_SUPPLY_CREWS: int = 3
## Werkstaetten, die pro Holz-Tick die EXAKTE Pruefung bezahlen (ein Stapel-Scan) —
## Round-Robin ueber die Ticks. Workshop.wants_more_stock_wood kostet
## O(Stapel x Gebaeude) und darf von der KI NIE aufgerufen werden.
const AI_SHOP_SUPPLY_PER_TICK: int = 2
## So viele Holz-Ticks bleibt eine Werkstatt sich selbst ueberlassen, bevor die KI
## Braves schickt: sonst kaempft der Nachschub gegen ihre eigenen Holzholer.
const AI_SHOP_SUPPLY_PATIENCE_TICKS: int = 3
## Holzregal an der Werkstatt. Die Obergrenze MUSS unter Building.ABSORB_RADIUS
## (5,0) bleiben, sonst zaehlt das Regal nicht als Bestand der Werkstatt.
const AI_SHOP_RACK_MIN_DIST: float = 2.0
const AI_SHOP_RACK_MAX_DIST: float = 4.5
## Seitlicher Mindestabstand zur Eingangsnormalen: ein 1x1-Regal direkt vor dem Tor
## wuerde das fertige Fahrzeug einsperren und exit_blocked dauerhaft machen — es
## wuerde also den Teil-3-Fehler VERURSACHEN.
const AI_SHOP_RACK_SIDE_CLEAR: float = 2.5
const AI_SHOP_RACK_SCAN_RINGS: int = 3
const AI_MAX_SHOP_RACKS: int = 3

# --- Trageverhalten (10h) ---
## Haelt ein Brave Holz OHNE Ablege-Befehl so lange, laesst er es an Ort und Stelle
## fallen (Nutzerentscheidung). Bei Nahkampf und Tod faellt es sofort.
const BRAVE_CARRY_HOLD_TIMEOUT: float = 30.0

# --- KI: Regale an den Huetten (10h Teil 2) ---
## Ein Regal im Absorptionsradius einer Huette finanziert ihre Ausbaustufen mit NULL
## KI-Befehlen: Building._tick_upgrade_absorb holt das Holz selbst.
const AI_MAX_HUT_RACKS: int = 4
## Mindestbestand eines Huetten-Regals: genau ein Ausbau.
const AI_HUT_RACK_STOCK: int = HUT_UPGRADE_WOOD_COST

# =============================================================================
# BUFFS (generisches Effektsystem)
# =============================================================================

## Feuerresistenz: der Brand macht hoechstens so viel Schaden je Sekunde
## (statt der ueblichen 15) und loest KEINE Panik aus. Gleicher Wert wie beim
## Golem, der dieselbe Kappe fest verdrahtet hat (GOLEM_BURN_DPS).
const BUFF_FIRE_RESIST_DPS_CAP: float = 5.0
## Bekehrungsresistenz: so lange muss ein Prediger auf das Ziel einreden, BEVOR
## es sich ueberhaupt hinsetzt. Danach laeuft die Bekehrung normal.
const BUFF_CONVERT_RESIST_DELAY: float = 3.0
## Der Vorlauf verfaellt, wenn so lange kein Bekehrungsversuch mehr kam — der
## Prediger hat aufgehoert. Muss ueber dem Scan-Takt (0,25 s) liegen.
const BUFF_CONVERT_RESIST_GRACE: float = 0.6
## Staerke: Angriffsmultiplikator je Stapel, multiplikativ (2 Stapel = 2,25x).
## Wirkt auf Nahkampf UND die Feuerbaelle des Feuerkriegers.
const BUFF_STRENGTH_MULT: float = 1.5
## Auren (z. B. die Fahrzeugboni des Technikers) werden jeden Tick mit dieser
## Restdauer aufgefrischt: faellt die Quelle weg, erlischt der Buff von selbst.
const BUFF_AURA_REFRESH: float = 0.5

# =============================================================================
# TECHNIKER
# =============================================================================

## Werte wie ein Brave — eigene Konstanten, damit sie getrennt justierbar sind.
const TECHNICIAN_HP: int = 65   # 60 -> 65 (Nutzervorgabe 2026-11-17; vorher = BRAVE_HP)
const TECHNICIAN_SPEED: float = BRAVE_SPEED
## Nahkampf: halb Tritt, halb Faustschlag, kein Schubser.
const TECHNICIAN_SHOVE_CHANCE: float = 0.0
const TECHNICIAN_KICK_CHANCE: float = 0.5
## Fahrzeugboni ab dem ersten Techniker in der Besatzung.
## Tempo: einmalig, stapelt NICHT.
const TECHNICIAN_VEHICLE_SPEED_BONUS: float = 0.33
## Feuerrate: additive Aufschlaege. Das Katapult bekommt den Grundbonus schon
## vom ersten Techniker, die Feuerramme nicht (dort zahlt der erste in
## Resistenzen fuer die Techniker an Bord).
const TECHNICIAN_SIEGE_FIRERATE_BASE: float = 0.33
const TECHNICIAN_FIRERAM_FIRERATE_BASE: float = 0.0
const TECHNICIAN_FIRERATE_PER_EXTRA: float = 0.10
## Zeppelin: Huellenreparatur wie die Feuerramme, Sekunden je Trefferpunkt.
const AIRSHIP_HULL_REGEN_TIME: float = 30.0

# =============================================================================
# RITUALKAMMER (experimentell, Nutzervorgabe 2026-11-16)
# =============================================================================
# Wie ein Ausbildungsgebaeude, aber heraus kommt niemand: der Brave ist weg. Je
# RITUAL_CHAMBER_BRAVES_PER_REWARD Opfer (je Stamm gezaehlt) bekommt ein zufaelliger
# eigener Golem einen Kill - ohne lebenden Golem gehen RITUAL_CHAMBER_MANA_REWARD
# Mana in einen der beiden Golemzauber. Nur mit dem Optionsschalter baubar.

const RITUAL_CHAMBER_FOOTPRINT: Vector2i = Vector2i(3, 3)
const RITUAL_CHAMBER_WOOD_COST: int = 20
## Annahme (nicht vorgegeben): so viel Leben wie die Ausbildungshalle.
const RITUAL_CHAMBER_HP: int = 450
const RITUAL_CHAMBER_TRAINING_TIME: float = 1.0
const RITUAL_CHAMBER_BRAVES_PER_REWARD: int = 2
const RITUAL_CHAMBER_MANA_REWARD: float = 10.0

# =============================================================================
# AUSBILDUNGSHALLE
# =============================================================================

const TRAINING_HALL_FOOTPRINT: Vector2i = Vector2i(4, 4)
const TRAINING_HALL_WOOD_COST: int = 10
const TRAINING_HALL_HP: int = 450
const TRAINING_HALL_TRAINING_TIME: float = 10.0

# =============================================================================
# ÜBERLEBEN (Spielmodus: 20 Wellen gegen eine kleine Basis, SurvivalMode)
# =============================================================================
# Testgelaende fuer Zauber und Golem: der Wellenstamm hat weder Gebaeude noch
# Schamanin noch KI. Alle Wellenwerte sind GANZZAHLIG gerechnet (Prozente statt
# Kommazahlen), damit Groesse und Mischung exakt aus der Wellennummer folgen.

## Anzahl der Wellen; danach gewinnt, wer den letzten Wellengegner toetet.
const SURVIVAL_WAVE_COUNT: int = 20
## Vorbereitungszeit bis zur ersten Welle.
const SURVIVAL_FIRST_WAVE_DELAY: float = 30.0
## Pause zwischen zwei Wellen, gemessen ab dem ERSCHEINEN der vorigen — nicht ab
## ihrem Tod. Das ergibt den steten Strom: wer langsam aufraeumt, hat zwei
## Wellen gleichzeitig am Hals.
const SURVIVAL_WAVE_INTERVAL: float = 45.0
## Wellengroesse: BASE + GROWTH * k + (GROWTH_SQ_PERCENT * k * k) / 100 mit
## k = Welle - 1. Ergibt 8 (Welle 1), 37 (Welle 10), 96 (Welle 20); alle 20
## Wellen zusammen 877 Einheiten — unter TRIBE_MAX_UNITS, der Hardcap kann eine
## Welle also selbst dann nicht kuerzen, wenn der Spieler keinen Gegner toetet.
const SURVIVAL_WAVE_BASE_SIZE: int = 8
const SURVIVAL_WAVE_GROWTH: int = 2
const SURVIVAL_WAVE_GROWTH_SQ_PERCENT: int = 14
## Mischung je Welle (abgerundet), der Rest sind Krieger: Krieger stellen die
## Mehrheit, Prediger bleiben wenige (Welle 1 hat noch keinen).
const SURVIVAL_FIREWARRIOR_PERCENT: int = 30
const SURVIVAL_PREACHER_PERCENT: int = 10
## Moegliche Spawnpunkte, gleichmaessig als Himmelsrichtungen um die Basis
## verteilt, jeweils am aeussersten begehbaren Punkt (Ufer bzw. Scheibenrand).
const SURVIVAL_SPAWN_POINTS: int = 8
## Aus so vielen Richtungen kommt eine Welle gleichzeitig: frueh aus zwei
## (gegenueber), ab SURVIVAL_LATE_FRONT_WAVE aus drei.
const SURVIVAL_FRONTS_EARLY: int = 2
const SURVIVAL_FRONTS_LATE: int = 3
const SURVIVAL_LATE_FRONT_WAVE: int = 8
## Um so viele Spawnpunkte dreht jede Welle weiter. Teilerfremd zu
## SURVIVAL_SPAWN_POINTS, damit nacheinander alle Richtungen drankommen.
const SURVIVAL_FRONT_ROTATION: int = 3
## Der Spawnpunkt liegt so viele Zellen innerhalb des aeussersten begehbaren
## Punkts (Platz fuer die Gruppe), aber nie naeher als MIN_DISTANCE an der Basis.
const SURVIVAL_SPAWN_INSET: int = 4
const SURVIVAL_SPAWN_MIN_DISTANCE: int = 30
## So oft bekommen untaetig herumstehende Wellengegner ein neues Angriffsziel
## (naechste Spielereinheit, sonst naechstes angreifbares Spielergebaeude).
const SURVIVAL_REGROUP_INTERVAL: float = 6.0
## Startbasis des Spielers: voll bemannte Huetten und freie Braves.
const SURVIVAL_START_HUTS: int = 3
const SURVIVAL_START_BRAVES: int = 12
## Zaubertestgelaende: mit JEDER neuen Welle sind alle Zauber des Spielers wieder
## voll geladen. Das normale Einkommen der kleinen Basis (~2 Mana/s) braechte
## sonst nach den Startladungen kaum einen Zauber nach (ein Golem kostet 900).
const SURVIVAL_REFILL_SPELLS_EACH_WAVE: bool = true
