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
## Wind-up vor dem Zauber-Release.
const SHAMAN_CAST_TIME: float = 0.6
## Mana-Bonus (Anteil der Ladungskapazität) für den Stamm, der sie tötet.
const SHAMAN_KILL_BONUS_SHARE: float = 0.15
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

# --- Vulkan ---
const VOLCANO_RADIUS: float = 5.0
## Lebensdauer der aktiven Vulkanzone (Lava/Stufenschaden).
const VOLCANO_ZONE_LIFETIME: float = 20.0

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
## Zusätzliches Mana/s je betendem Brave.
const MANA_PRAY_BONUS: float = 0.3
## Hardcap Einheiten pro Stamm (zusätzlich zum Hütten-Bevölkerungslimit).
const TRIBE_MAX_UNITS: int = 1000

# --- Bäume ---
## Mittlere Zeit pro Wachstumsstufe (real +-50 % gestreut).
const TREE_GROWTH_TIME: float = 75.0
## Holz-Ertrag je Wachstumsstufe (Index = Stufe 0..4).
const TREE_YIELDS: Array[int] = [0, 1, 2, 3, 4]
