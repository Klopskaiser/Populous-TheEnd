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
## Feuerkrieger-Schadensfaktor gegen Ziele in der Luft (Deck-Crew, Geschleuderte).
const FIREWARRIOR_AIRBORNE_MULT: int = 2

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
const LIFT_MAX_HEIGHT: float = 6.0
## Was vom Hochschub nicht mehr unter den Deckel passt, wird stattdessen mit
## diesem Faktor auf den SEITLICHEN Schub gelegt (1,0 = eins zu eins).
const LIFT_SIDEWAYS_TRANSFER: float = 1.0

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
## Rolldauer pro gestürztem Meter (s), geklemmt auf [MINI_ROLL_DURATION, 2.0].
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

# --- Hütte ---
const HUT_WOOD_COST: int = 12
const HUT_HP: int = 300
const HUT_CAPACITY: int = 40               # Bevölkerungsplatz
const HUT_SPAWN_INTERVAL: float = 10.0     # s pro Brave bei voller Besatzung
const HUT_CREW_CAPACITY: int = 4
const HUT_FULL_CREW_BONUS: float = 1.1     # volle Hütte ~10 % schneller

# --- Kaserne (Krieger) ---
const WARRIOR_CAMP_WOOD_COST: int = 10
const WARRIOR_CAMP_HP: int = 400
const WARRIOR_CAMP_TRAINING_TIME: float = 3.0

# --- Tempel (Prediger) ---
const TEMPLE_WOOD_COST: int = 15
const TEMPLE_HP: int = 440
const TEMPLE_TRAINING_TIME: float = 5.0

# --- Feuertempel (Feuerkrieger) ---
const FIREWARRIOR_CAMP_WOOD_COST: int = 20
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
const WORKSHOP_WOOD_COST: int = 13
const WORKSHOP_HP: int = 350
## Arbeiter-Sekunden pro Katapult (3 Arbeiter -> 20 s).
## Regel: Produktionsaufwand = Holzkosten des Fahrzeugs x 10 Arbeiter-Sekunden.
const WORKSHOP_WORK_PER_CATAPULT: float = 60.0
const WORKSHOP_CATAPULT_WOOD: int = 6

# --- Feuerrammenwerkstatt ---
const FIRERAM_WORKSHOP_WOOD_COST: int = 11
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
