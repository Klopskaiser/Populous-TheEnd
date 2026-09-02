extends SceneTree

## AUDIO-SELBSTTEST — beantwortet "warum ist es still?" mit Daten statt Raten.
##
## Prueft fuer JEDEN dokumentierten Soundnamen (assets/README.md), was die Engine
## tatsaechlich sieht: liegt eine Datei da, ist sie importiert, laesst sie sich
## dekodieren, und wie lang ist sie. Dazu die Verdrahtung zur Laufzeit (Busse,
## Pools), denn ein stummer Sound kann an drei Stellen haengen.
##
## Aufruf:
##   godot --headless -s res://tests/diag_audio_assets.gd
##   godot --headless -s res://tests/diag_audio_assets.gd -- nur=fehlt
##
## WICHTIG: der _ready des AudioManager-Autoloads laeuft ERST, wenn der Baum
## verarbeitet — in _initialize() sind Busse und Pools noch leer. Deshalb
## messen wir ab Frame 3 (_process), nicht in _initialize.

const GROUPS: Array = [
	["Kampf (audio/sfx/combat/, Fallback = Synthese)", "audio/sfx/combat/",
		["punch", "kick", "shove", "fireball", "throw", "preach", "preach_enemy"]],
	["Einheiten (audio/sfx/)", "audio/sfx/",
		["unit_panic", "unit_injured", "unit_death", "unit_burning", "unit_land",
		"unit_air_death", "water_splash", "water_sink", "shaman_hurt", "shaman_death"]],
	["Status-Loops (audio/sfx/)", "audio/sfx/",
		["unit_panic_loop", "unit_burning_loop", "unit_injured_loop"]],
	["Fahrzeuge (audio/sfx/)", "audio/sfx/",
		["siege_fire", "fireram_burst", "siege_impact", "siege_burning",
		"siege_death_burn", "siege_death_burst", "airship_death"]],
	["Gebaeude & Ereignisse (audio/sfx/)", "audio/sfx/",
		["build_place", "building_complete", "building_attack_melee",
		"building_attack_ranged", "building_damaged", "building_destroyed",
		"training_done"]],
	["Umwelt (audio/sfx/)", "audio/sfx/",
		["tree_burning", "wood_chop", "wood_chop_loop"]],
	["Zauber-Zusatz (audio/sfx/)", "audio/sfx/",
		["spell_tornado_loop", "spell_supertornado_loop", "spell_swarm_loop",
		"spell_volcano_erupt", "lava_start"]],
	["UI (audio/ui/)", "audio/ui/",
		["select_unit", "select_shaman", "select_building", "move_unit",
		"move_shaman", "move_blocked", "click"]],
]

var _frames: int = 0


## Zaubersounds sind zwei je Id — aus den Spell-Klassen erzeugt, nicht getippt.
func _spell_names() -> Array:
	var out: Array = []
	for spell in Spell.create_default_set():
		out.append(String(SpellAudio.voice_name(spell.id)))
		out.append(String(SpellAudio.effect_name(spell.id)))
	return out


## Ein Name, drei Fragen: Datei da? importiert? dekodierbar?
func _report(dir: String, name: String) -> Dictionary:
	var found: Array = []          # [pfad, importiert, stream]
	for suffix in _suffixes(dir, name):
		var rel: String = dir + name + suffix
		var path: String = "res://assets/" + rel
		if not FileAccess.file_exists(path):
			continue
		found.append([rel, ResourceLoader.exists(path), AssetLibrary.stream(rel)])
	return {"name": name, "files": found}


## Basisdatei plus nummerierte Varianten (_0 .. _7) in beiden Formaten.
func _suffixes(dir: String, name: String) -> Array:
	var out: Array = []
	for ext in [".ogg", ".wav", ".mp3"]:
		out.append(ext)
		for i in range(8):
			out.append("_%d%s" % [i, ext])
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only_missing: bool = false
	for a in args:
		if a == "nur=fehlt":
			only_missing = true

	print("=== AUDIO-SELBSTTEST ===")
	var am: Node = get_root().get_node_or_null("AudioManager")
	print("-- Verdrahtung --")
	print("AudioManager: %s" % ("da" if am != null else "FEHLT (Autoload?)"))
	var bus_names: Array = []
	for i in range(AudioServer.bus_count):
		bus_names.append("%s%s" % [AudioServer.get_bus_name(i),
			" (STUMM!)" if AudioServer.is_bus_mute(i) else ""])
	print("Busse: %s" % ", ".join(bus_names))
	if am != null:
		print("Pools: %d Welt-Slots, %d UI-Slots" % [
			(am._sfx_pool as Array).size(), (am._ui_pool as Array).size()])
	print("")

	var groups: Array = GROUPS.duplicate()
	groups.append(["Zauber (audio/sfx/)", "audio/sfx/", _spell_names()])
	var total: int = 0
	var ok: int = 0
	var broken: int = 0
	var unimported: int = 0
	for g in groups:
		var lines: Array = []
		for name in g[2]:
			total += 1
			var r: Dictionary = _report(String(g[1]), String(name))
			if (r["files"] as Array).is_empty():
				if not only_missing:
					lines.append("  %-26s —  keine Datei" % name)
				continue
			for f in r["files"]:
				var stream: AudioStream = f[2]
				if stream == null:
					broken += 1
					lines.append("  %-26s !! %s liegt da, ist aber NICHT LESBAR (Format?)"
						% [name, f[0]])
					continue
				ok += 1
				var note: String = ""
				if not bool(f[1]):
					unimported += 1
					note = "  (nicht importiert — direkt von der Platte gelesen)"
				lines.append("  %-26s OK %s  %.2f s%s" % [name, f[0],
					stream.get_length(), note])
		if lines.is_empty():
			continue
		print("-- %s --" % g[0])
		for l in lines:
			print(l)
		print("")
	print("=== %d Namen geprueft: %d spielbare Dateien, %d unlesbar, %d ohne Import ==="
		% [total, ok, broken, unimported])
	if broken > 0:
		print("Unlesbar heisst: die Datei existiert, aber weder Import noch")
		print("Laufzeit-Dekoder kommen damit klar. Godot liest WAV nur als PCM")
		print("(8/16/24 Bit), IMA-ADPCM oder QOA — und .ogg nur als Vorbis.")
	return true
