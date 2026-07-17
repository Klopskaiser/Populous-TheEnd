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
const FIREWARRIOR_HP: int = 60
const FIREWARRIOR_SPEED: float = 4.0
const FIREWARRIOR_FIRE_RANGE: float = 7.0
const FIREWARRIOR_FIRE_COOLDOWN: float = 1.5
const FIREWARRIOR_AGGRO_RADIUS: float = 13.0
## Schaden eines Feuerballs an Einheiten.
const FIREWARRIOR_FIREBALL_DAMAGE: int = 7
## Schaden eines Feuerballs an Gebäuden.
const FIREWARRIOR_BUILDING_DAMAGE: int = 5

# --- Prediger ---
const PREACHER_HP: int = 75
const PREACHER_SPEED: float = 4.0
const PREACHER_CONVERT_RANGE: float = 5.0
## Bekehrdauer: pro Ziel zufällig aus [MIN, MAX] gewürfelt.
const PREACHER_CONVERT_TIME_MIN: float = 4.0
const PREACHER_CONVERT_TIME_MAX: float = 9.0

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
const REGEN_RATE: float = 2.0

# =============================================================================
# LEICHEN
# =============================================================================

## Liegezeit der Leiche, danach versinkt sie im Boden.
const CORPSE_DURATION: float = 5.0
## Dauer der Versink-Animation. ACHTUNG: verlängert die Gesamt-Lebenszeit von
## Leichen in der Welt — der Zentroid-Drift-Test (test_combat_groups) misst
## über alle Einheiten inkl. Leichen und reagiert auf große Änderungen.
const CORPSE_SINK_DURATION: float = 1.0
## Wie tief das Leichen-Sprite versinkt (Sprite-Höhe + Rand).
const CORPSE_SINK_DEPTH: float = 1.6

# =============================================================================
# BRAND / LAVA (Einheiten)
# =============================================================================

const LAVA_CONTACT_DAMAGE: int = 30
const BURN_DURATION: float = 4.0
## Gesamtschaden über die Brenndauer (2 x Brave-Leben).
const BURN_TOTAL_DAMAGE: int = 120

# =============================================================================
# ZAUBER — Ladungen (charge_cost = Mana pro Ladung) und Reichweite
# =============================================================================

const SPELL_FIREBALL_CHARGE_COST: float = 40.0
const SPELL_FIREBALL_MAX_CHARGES: int = 4
const SPELL_FIREBALL_CAST_RANGE: float = 8.0

const SPELL_LIGHTNING_CHARGE_COST: float = 60.0
const SPELL_LIGHTNING_MAX_CHARGES: int = 4
const SPELL_LIGHTNING_CAST_RANGE: float = 10.0

const SPELL_SWARM_CHARGE_COST: float = 50.0
const SPELL_SWARM_MAX_CHARGES: int = 4
const SPELL_SWARM_CAST_RANGE: float = 8.0

const SPELL_LANDBRIDGE_CHARGE_COST: float = 60.0
const SPELL_LANDBRIDGE_MAX_CHARGES: int = 4
const SPELL_LANDBRIDGE_CAST_RANGE: float = 9.0

const SPELL_TORNADO_CHARGE_COST: float = 110.0
const SPELL_TORNADO_MAX_CHARGES: int = 3
const SPELL_TORNADO_CAST_RANGE: float = 8.0

const SPELL_EARTHQUAKE_CHARGE_COST: float = 110.0
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
const SWARM_DPS: int = 3
## Panik-Dauer (gilt auch für andere Panik-Quellen, z. B. Brand).
const PANIC_DURATION: float = 6.0

# --- Tornado ---
const TORNADO_LIFETIME: float = 8.0
const TORNADO_RADIUS: float = 2.2
## Alle X Sekunden +1 Zerstörungsstufe am überstrichenen Gebäude.
const TORNADO_STAGE_INTERVAL: float = 2.0
const TORNADO_FALL_DAMAGE: int = 30        # 1/2 Brave-Leben

# --- Feuerregen ---
const FIRESTORM_BOLT_COUNT: int = 8
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
const VOLCANO_ZONE_STAGE_INTERVAL: float = 4.0

# --- Ebene / Absinken / Landbrücke ---
const FLATTEN_HALF_EXTENT: float = 4.5     # halbe Kantenlänge des Quadrats
const SINK_RADIUS: float = 6.0
const SINK_DEPTH: float = 3.0
const LANDBRIDGE_HALF_WIDTH: float = 1.6

# =============================================================================
# GEBÄUDE — Kosten, Leben, Ausbildung
# =============================================================================

## Schadensanteil pro Zerstörungsstufe (Stufen bei 30/60/90/100 %).
const BUILDING_STAGE_DAMAGE: float = 0.3
## Abriss-Schaden pro Nahkampf-Angreifer im Gebäude (HP/s).
const RAID_DPS_PER_RAIDER: float = 6.0
## Maximale gleichzeitige Nahkampf-Abreißer pro Gebäude.
const MAX_MELEE_RAIDERS: int = 15

# --- Hütte ---
const HUT_WOOD_COST: int = 12
const HUT_HP: int = 300
const HUT_CAPACITY: int = 40               # Bevölkerungsplatz
const HUT_SPAWN_INTERVAL: float = 10.0     # s pro Brave bei voller Besatzung
const HUT_CREW_CAPACITY: int = 4
const HUT_FULL_CREW_BONUS: float = 1.1     # volle Hütte ~10 % schneller

# --- Kaserne (Krieger) ---
const WARRIOR_CAMP_WOOD_COST: int = 5
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
const FORESTER_WOOD_COST: int = 20
const FORESTER_HP: int = 250
## Mana/s je aktivem Arbeiter im Gebäude.
const FORESTER_MANA_PER_WORKER: float = 2.0
## Arbeiter-Sekunden pro gepflanztem Baum (4 Arbeiter -> 15 s).
const FORESTER_PLANT_WORK_PER_TREE: float = 60.0

# --- Werkstatt ---
const WORKSHOP_WOOD_COST: int = 15
const WORKSHOP_HP: int = 350
## Arbeiter-Sekunden pro Katapult (3 Arbeiter -> 30 s).
const WORKSHOP_WORK_PER_CATAPULT: float = 90.0
const WORKSHOP_CATAPULT_WOOD: int = 5

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
const MANA_PRAY_BONUS: float = 0.5
## Hardcap Einheiten pro Stamm (zusätzlich zum Hütten-Bevölkerungslimit).
const TRIBE_MAX_UNITS: int = 1500

# --- Bäume ---
## Mittlere Zeit pro Wachstumsstufe (real +-50 % gestreut).
const TREE_GROWTH_TIME: float = 75.0
## Holz-Ertrag je Wachstumsstufe (Index = Stufe 0..4).
const TREE_YIELDS: Array[int] = [0, 1, 2, 3, 4]
