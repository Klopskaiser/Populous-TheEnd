class_name SaveGame extends RefCounted

## Save-game files (2026-11-23). One file per slot under user://saves/<slot>.sav,
## Zstandard-compressed, holding two Godot variants written with store_var:
##   1. the HEADER — format id, format version and the slot's metadata (title,
##      date, mode, map, game time, tribes), readable on its own for a slot list;
##   2. the BODY — the GameSnapshot of the match.
## Objects are never decoded (get_var without allow_objects), so a crafted file
## cannot smuggle code in.
##
## Today the game uses ONE slot (QUICKSAVE_SLOT, F5/F8 and the pause menu); the
## schema already takes any number of named slots (slot_path, list_slots), so a
## slot picker only needs UI.

const FORMAT_ID: String = "populous-the-end-save"
## Version of the file format. A newer file than this build knows is refused; an
## older one would be migrated in read() (none so far).
const FORMAT_VERSION: int = 1
const SAVE_DIR: String = "user://saves"
const EXTENSION: String = "sav"
const QUICKSAVE_SLOT: String = "quicksave"
const QUICKSAVE_TITLE: String = "Schnellspeicher"


## File name stem of a slot: lower case a–z, 0–9, '-' and '_' only.
static func sanitize_slot(slot: String) -> String:
	var out: String = ""
	for ch in slot.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_":
			out += ch
		elif ch == " ":
			out += "_"
	return out if out != "" else QUICKSAVE_SLOT


static func slot_path(slot: String) -> String:
	return "%s/%s.%s" % [SAVE_DIR, sanitize_slot(slot), EXTENSION]


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Metadata of a snapshot for the slot list.
static func make_header(body: Dictionary, slot: String, title: String) -> Dictionary:
	var config: MatchConfig = MatchConfig.from_dict(body.get("match_config", {}))
	var tracking: Dictionary = body.get("tracking", {})
	return {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"data_version": int(body.get("data_version", GameSnapshot.DATA_VERSION)),
		"slot": sanitize_slot(slot),
		"title": title,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_unix": Time.get_unix_time_from_system(),
		"mode": int(config.mode),
		"mode_label": config.mode_label(),
		"map_id": String(body.get("map_id", config.map_id)),
		"match_time": float(tracking.get("match_time", 0.0)),
		"tribes": (body.get("tribes", []) as Array).size(),
	}


## Writes `body` (a GameSnapshot) into `slot`. Returns OK or the error.
static func write(slot: String, body: Dictionary, title: String = "") -> Error:
	var dir_err: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if dir_err != OK and not DirAccess.dir_exists_absolute(SAVE_DIR):
		return dir_err
	var path: String = slot_path(slot)
	# Write to a temporary file first and move it over the slot: a crash mid-write
	# must not destroy the previous save.
	var tmp: String = path + ".tmp"
	var file: FileAccess = FileAccess.open_compressed(tmp, FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(make_header(body, slot, title if title != "" else slot))
	file.store_var(body)
	var err: Error = file.get_error()
	file.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return err
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Header of a slot, {} when missing or not a save of this game.
static func read_header(slot: String) -> Dictionary:
	var file: FileAccess = _open(slot)
	if file == null:
		return {}
	var header = file.get_var()
	file.close()
	if not (header is Dictionary) or header.get("format", "") != FORMAT_ID:
		return {}
	return header


## Reads a slot: {"header": ..., "body": ...} or {"error": "<German message>"}.
static func read(slot: String) -> Dictionary:
	var file: FileAccess = _open(slot)
	if file == null:
		return {"error": "Kein Spielstand vorhanden."}
	var header = file.get_var()
	if not (header is Dictionary) or header.get("format", "") != FORMAT_ID:
		file.close()
		return {"error": "Die Datei ist kein Spielstand."}
	var version: int = int(header.get("version", 0))
	if version > FORMAT_VERSION:
		file.close()
		return {"error": "Der Spielstand stammt aus einer neueren Version (%d)." % version}
	var body = file.get_var()
	file.close()
	if not (body is Dictionary) or (body as Dictionary).is_empty():
		return {"error": "Der Spielstand ist beschädigt."}
	if int(body.get("data_version", 0)) > GameSnapshot.DATA_VERSION:
		return {"error": "Der Spielstand stammt aus einer neueren Version."}
	return {"header": header, "body": body}


## Reads `slot` and switches to the game scene, which restores it (Main._ready
## takes GameState.pending_load). Returns "" on success, else the German error.
## Works from the main menu and from a running match alike.
static func load_into_game(tree: SceneTree, slot: String) -> String:
	var result: Dictionary = read(slot)
	if result.has("error"):
		return String(result["error"])
	var game_state: Node = tree.root.get_node_or_null("GameState")
	if game_state == null:
		return "Spielzustand nicht verfügbar."
	game_state.pending_load = result["body"]
	tree.paused = false
	tree.change_scene_to_file(GAME_SCENE_PATH)
	return ""


const GAME_SCENE_PATH: String = "res://scenes/main.tscn"


static func _open(slot: String) -> FileAccess:
	var path: String = slot_path(slot)
	if not FileAccess.file_exists(path):
		return null
	return FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)


## Headers of every slot, newest first.
static func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.get_extension() != EXTENSION:
			continue
		var header: Dictionary = read_header(file_name.get_basename())
		if not header.is_empty():
			out.append(header)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("saved_unix", 0.0)) > float(b.get("saved_unix", 0.0)))
	return out


static func delete_slot(slot: String) -> Error:
	var path: String = slot_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


## One line for a slot list: "Schnellspeicher — Skirmish (2 KI), insel, 12:34 — 2026-11-23 14:05".
static func describe(header: Dictionary) -> String:
	return "%s — %s, %s, %s — %s" % [
		header.get("title", header.get("slot", "?")),
		header.get("mode_label", "?"),
		header.get("map_id", "?"),
		TribeStats.format_time(float(header.get("match_time", 0.0))),
		String(header.get("saved_at", "")).replace("T", " ").left(16)]
