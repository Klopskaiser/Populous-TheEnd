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

# --- Brave (Gefolgsmann) ---
const BRAVE_HP: int = 60
const BRAVE_SPEED: float = 4.0
## Aggro-Radius unbeschäftigter Braves (kleine Dorfwache).
const BRAVE_IDLE_AGGRO_RADIUS: float = 3.0

# --- Krieger ---
const WARRIOR_HP: int = 120
const WARRIOR_SPEED: float = 4.0
## Nahkampf-Multiplikator auf die Basis-Schlagwerte (Punch/Kick/Shove).
const WARRIOR_MELEE_STRENGTH: float = 3.0
## Krieger schubsen fast nie (sie hauen lieber zu).
const WARRIOR_SHOVE_CHANCE: float = 0.04

# --- Feuerkrieger ---
const FIREWARRIOR_HP: int = 65
const FIREWARRIOR_SPEED: float = 4.0
const FIREWARRIOR_FIRE_RANGE: float = 8.0
const FIREWARRIOR_FIRE_COOLDOWN: float = 1.5
const FIREWARRIOR_AGGRO_RADIUS: float = 13.0
## Schaden eines Feuerballs an Einheiten.
const FIREWARRIOR_FIREBALL_DAMAGE: int = 9
## Fluggeschwindigkeit (m/s) des Feuerkrieger-Feuerballs (zielsuchend).
const FIREWARRIOR_FIREBALL_SPEED: float = 12.0
## Verfolgt der Ball ein LUFTZIEL (geschleuderte Einheit, Zeppelin), gewinnt er
## kontinuierlich Tempo (m/s²) — mit dem Grundtempo holte er hochgeschleuderte
## Ziele kaum ein. Gedeckelt, damit er nicht durch das Ziel hindurchschießt.
const FIREWARRIOR_FIREBALL_AIR_ACCEL: float = 22.0
const FIREWARRIOR_FIREBALL_AIR_MAX_SPEED: float = 34.0
## Schaden eines Feuerballs an Gebäuden.
const FIREWARRIOR_BUILDING_DAMAGE: int = 5

# --- Prediger ---
const PREACHER_HP: int = 90
const PREACHER_SPEED: float = 4.0
const PREACHER_CONVERT_RANGE: float = 5.0
## Bekehrdauer: pro Ziel zufällig aus [MIN, MAX] gewürfelt.
const PREACHER_CONVERT_TIME_MIN: float = 4.0
const PREACHER_CONVERT_TIME_MAX: float = 9.0
## Nahkampf-Attackenchancen (Rest = Punch): schubst viel häufiger als der
## Standard, kickt seltener.
const PREACHER_SHOVE_CHANCE: float = 0.5
const PREACHER_KICK_CHANCE: float = 0.1

# --- Schamanin ---
const SHAMAN_HP: int = 240              # 4 x Brave
const SHAMAN_SPEED: float = 4.0
const SHAMAN_MELEE_STRENGTH: float = 2.0   # 2 x Brave-Schaden
## Wind-up vor dem Zauber-Release: die Zeit, in der die Schamanin die
## Zauberformel spricht (Phase 10b). Für alle Zauber gleich.
const SHAMAN_CAST_TIME: float = 1.0
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
## Brenndauer des Fahrzeugs nach Feuerzauber-Treffer, dann versinkt das Wrack.
const SIEGE_VEHICLE_BURN_TIME: float = 3.0
const SIEGE_FIRE_RANGE: float = 15.0
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
const FIRERAM_TURN_RATE: float = 1.6
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
const FIRERAM_DEATH_BLAST_DAMAGE: int = 20
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
## hochgeschleuderte Einheiten — `Unit.is_airborne()`). Seit Phase 10c nur noch
## **+20 %** statt doppelt: mit dem Lift ist die Kombo „hochwerfen und
## abschießen" zuverlässig geworden, der Verdoppler war damit zu stark.
const FIREWARRIOR_AIRBORNE_MULT: float = 1.2

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
## Feuerkrieger: Teil der Umwerf-Chance wird zu "Anheben" — Summe unverändert.
const FW_FIREBALL_ROLL_CHANCE: float = 0.06
const FW_FIREBALL_LIFT_CHANCE: float = 0.04
const FW_FIREBALL_ROLL_CHANCE_ROLLING: float = 0.30
const FW_FIREBALL_LIFT_CHANCE_ROLLING: float = 0.10
## Ein Lift ERSETZT den Bodenschub: weniger Horizontale, kleiner Hüpfer.
const FW_FIREBALL_LIFT_PUSH: float = 1.2
const FW_FIREBALL_LIFT_UP: float = 3.0
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
## Unsichtbare Mauer an der Weltgrenze: so weit INNERHALB des Kartenrandes
## steht sie, damit eine geschleuderte Einheit nicht auf der Kante landet.
const WORLD_EDGE_MARGIN: float = 1.0
## Rückprall-Anteil der Geschwindigkeit beim Anprall (0 = klebt, 1 = perfekt
## elastisch). Bewusst klein: ein "leichter Bounce" zurück ins Spielfeld.
const WORLD_BOUNCE_RESTITUTION: float = 0.45

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
const SPELL_FIREBALL_CAST_RANGE: float = 8.0

const SPELL_LIGHTNING_CHARGE_COST: float = 70.0
const SPELL_LIGHTNING_MAX_CHARGES: int = 4
const SPELL_LIGHTNING_CAST_RANGE: float = 12.0

const SPELL_SWARM_CHARGE_COST: float = 50.0
const SPELL_SWARM_MAX_CHARGES: int = 4
const SPELL_SWARM_CAST_RANGE: float = 8.0

const SPELL_LANDBRIDGE_CHARGE_COST: float = 60.0
const SPELL_LANDBRIDGE_MAX_CHARGES: int = 4
const SPELL_LANDBRIDGE_CAST_RANGE: float = 9.0

const SPELL_TORNADO_CHARGE_COST: float = 110.0
const SPELL_TORNADO_MAX_CHARGES: int = 3
const SPELL_TORNADO_CAST_RANGE: float = 10.0

const SPELL_SUPERTORNADO_CHARGE_COST: float = 200.0   # teurer als Tornado, ~Vulkan
const SPELL_SUPERTORNADO_MAX_CHARGES: int = 1
const SPELL_SUPERTORNADO_CAST_RANGE: float = 10.0

const SPELL_EARTHQUAKE_CHARGE_COST: float = 130.0
const SPELL_EARTHQUAKE_MAX_CHARGES: int = 2
const SPELL_EARTHQUAKE_CAST_RANGE: float = 10.0

const SPELL_VOLCANO_CHARGE_COST: float = 180.0
const SPELL_VOLCANO_MAX_CHARGES: int = 1
const SPELL_VOLCANO_CAST_RANGE: float = 12.0

const SPELL_FIRESTORM_CHARGE_COST: float = 100.0
const SPELL_FIRESTORM_MAX_CHARGES: int = 2
const SPELL_FIRESTORM_CAST_RANGE: float = 10.0

const SPELL_FLATTEN_CHARGE_COST: float = 90.0
const SPELL_FLATTEN_MAX_CHARGES: int = 3
const SPELL_FLATTEN_CAST_RANGE: float = 10.0

const SPELL_SINK_CHARGE_COST: float = 60.0
const SPELL_SINK_MAX_CHARGES: int = 3
const SPELL_SINK_CAST_RANGE: float = 10.0

# =============================================================================
# ZAUBER — Effektwerte
# =============================================================================

# --- Feuerball (auch je Bolt des Feuerregens) ---
const FIREBALL_DIRECT_DAMAGE: int = 60     # 1 x Brave-Leben
const FIREBALL_SPLASH_DAMAGE: int = 30     # 1/2 Brave-Leben
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

# --- Feuerregen ---
const FIRESTORM_BOLT_COUNT: int = 12
const FIRESTORM_SPREAD_RADIUS: float = 5.5
const FIRESTORM_DURATION: float = 3.0

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
const VOLCANO_RADIUS: float = 5.0
## Lebensdauer der aktiven Vulkanzone (Lava/Stufenschaden).
const VOLCANO_ZONE_LIFETIME: float = 20.0
## Gezählte Lavastöße je Ausbruch (robust gegen spätere Lifetime-Änderungen).
const VOLCANO_SURGE_COUNT: int = 2
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

## Bauplan-Größen (Footprint in Zellen, Breite x Tiefe; 1 Zelle = 1 m).
## Der Eingang liegt auf der Südseite; nicht-quadratische Footprints werden
## beim Drehen automatisch getauscht.
const HUT_FOOTPRINT: Vector2i = Vector2i(4, 4)
const WARRIOR_CAMP_FOOTPRINT: Vector2i = Vector2i(5, 5)
const TEMPLE_FOOTPRINT: Vector2i = Vector2i(6, 6)
const FIREWARRIOR_CAMP_FOOTPRINT: Vector2i = Vector2i(8, 8)
const FORESTER_FOOTPRINT: Vector2i = Vector2i(2, 4)
const WORKSHOP_FOOTPRINT: Vector2i = Vector2i(7, 4)
const FIRERAM_WORKSHOP_FOOTPRINT: Vector2i = Vector2i(6, 4)
const AIRSHIP_WHARF_FOOTPRINT: Vector2i = Vector2i(8, 8)
const WATCHTOWER_FOOTPRINT: Vector2i = Vector2i(2, 2)
const WOOD_DEPOT_FOOTPRINT: Vector2i = Vector2i(1, 1)
const REINCARNATION_SITE_FOOTPRINT: Vector2i = Vector2i(3, 3)

# --- Hütte (Phase 10f: klein und billig, in vier Stufen zum Wohnpalast) ---
const HUT_WOOD_COST: int = 7               # war 12, dann 8 (10h)
const HUT_HP: int = 300                    # == HUT_HP_PER_STAGE[0]
## Plätze/Arbeiter/Leben je Ausbaustufe (Index = Stufe 0..4). Stufe 4 bringt
## bewusst +11 statt +8 Plätze — der Wohnpalast ist der Lohn für den Vollausbau.
## Ein Platz kostet damit 0,8 Holz auf Stufe 0 (8/10) und 0,62 im Vollausbau
## (28/45) — vorher waren es 0,3 (12/40), Wohnraum ist also doppelt so teuer.
const HUT_CAPACITY_PER_STAGE: Array[int] = [10, 18, 26, 34, 45]
const HUT_CREW_PER_STAGE: Array[int] = [2, 3, 4, 5, 6]
const HUT_HP_PER_STAGE: Array[int] = [300, 340, 380, 420, 480]
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
const WARRIOR_CAMP_HP: int = 400
const WARRIOR_CAMP_TRAINING_TIME: float = 3.0

# --- Tempel (Prediger) ---
const TEMPLE_WOOD_COST: int = 15
const TEMPLE_HP: int = 440
const TEMPLE_TRAINING_TIME: float = 5.0

# --- Feuertempel (Feuerkrieger) ---
const FIREWARRIOR_CAMP_WOOD_COST: int = 18  # war 20 (10h)
const FIREWARRIOR_CAMP_HP: int = 600
const FIREWARRIOR_CAMP_TRAINING_TIME: float = 4.0

# --- Förster ---
const FORESTER_WOOD_COST: int = 18
const FORESTER_HP: int = 250
## Mana/s je aktivem Arbeiter im Gebäude.
const FORESTER_MANA_PER_WORKER: float = 1.5
## Arbeiter-Sekunden pro gepflanztem Baum (4 Arbeiter -> 15 s).
const FORESTER_PLANT_WORK_PER_TREE: float = 50.0

# --- Katapultwerkstatt ---
const WORKSHOP_WOOD_COST: int = 12          # war 13 (10h)
const WORKSHOP_HP: int = 350
## Arbeiter-Sekunden pro Katapult (3 Arbeiter -> 20 s).
## Regel: Produktionsaufwand = Holzkosten des Fahrzeugs x 10 Arbeiter-Sekunden.
const WORKSHOP_WORK_PER_CATAPULT: float = 60.0
const WORKSHOP_CATAPULT_WOOD: int = 6

# --- Feuerrammenwerkstatt ---
const FIRERAM_WORKSHOP_WOOD_COST: int = 10  # war 11 (10h)
const FIRERAM_WORKSHOP_HP: int = 350
## Arbeiter-Sekunden pro Feuerramme (3 Arbeiter -> ~13 s); 4 Holz x 10.
const FIRERAM_WORK_PER_RAM: float = 40.0
const FIRERAM_WOOD: int = 4

# --- Luftschiffwerft ---
const AIRSHIP_WHARF_WOOD_COST: int = 20
const AIRSHIP_WHARF_HP: int = 500
const WHARF_WORKER_SLOTS: int = 4
## Arbeiter-Sekunden pro Luftschiff (4 Arbeiter -> 20 s); 8 Holz x 10.
const WHARF_WORK_PER_AIRSHIP: float = 80.0
const WHARF_AIRSHIP_WOOD: int = 8

# --- Holzstation ---
const WOOD_DEPOT_WOOD_COST: int = 1
const WOOD_DEPOT_HP: int = 120
## Storage cap = 4 stock piles x WoodPile.MAX_AMOUNT.
const WOOD_DEPOT_CAPACITY: int = 20

# --- Wachturm ---
const WATCHTOWER_WOOD_COST: int = 4
const WATCHTOWER_HP: int = 200
## Reichweiten-Bonus für stationierte Fernkämpfer/Prediger.
const WATCHTOWER_RANGE_BONUS: float = 3.0
## Wachtürme sind klein: weniger gleichzeitige Abreißer als der Standard.
const WATCHTOWER_MAX_RAIDERS: int = 5

# --- Reinkarnationsplatz ---
const REINCARNATION_SITE_HP: int = 500

# =============================================================================
# STAMM / WIRTSCHAFT
# =============================================================================

## Mana/s je Bevölkerungsmitglied.
const MANA_BASE_RATE: float = 0.1
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
const TREE_GROVES_PER_STANDARD_MAP: int = 3   # Haine je 128er-Fläche (skaliert wie TREE_COUNT)
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
## Radius 0,2 * size: Insel 128 mit 4 Staemmen 36,2 · mit 3 Staemmen 44,3 · mit 2
## Staemmen 51,2 · Plateau 128 (Eckanker) 82 · Seenland/Bergpass 256 deutlich mehr.
const AI_CRAMPED_ARENA: float = 60.0
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
