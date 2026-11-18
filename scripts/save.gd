extends Node
## Persistent player progress: coins, level, permanent upgrades and skins.
## Registered as the "Save" autoload in project.godot.

const PATH := "user://squad_surge_save.json"

const UPGRADE_ORDER := ["damage", "fire_rate", "squad", "shield", "coins"]
const UPGRADE_INFO := {
	"damage":    {"name": "Firepower",      "desc": "+20% bullet damage",       "base": 60,  "max": 10},
	"fire_rate": {"name": "Trigger Speed",  "desc": "+10% fire rate",           "base": 60,  "max": 10},
	"squad":     {"name": "Reinforcements", "desc": "+1 starting soldier",      "base": 150, "max": 5},
	"shield":    {"name": "Shield",         "desc": "Start with 1 more shield", "base": 100, "max": 5},
	"coins":     {"name": "Bounty",         "desc": "+15% coins earned",        "base": 80,  "max": 10},
}

const SKIN_ORDER := ["classic", "crimson", "toxic", "royal", "gold", "shadow"]
const SKINS := {
	"classic": {"name": "Classic", "price": 0,    "body": Color(0.25, 0.6, 1.0),  "accent": Color(0.9, 0.95, 1.0), "bullet": Color(1.0, 0.95, 0.4)},
	"crimson": {"name": "Crimson", "price": 300,  "body": Color(0.85, 0.2, 0.25), "accent": Color(1.0, 0.8, 0.7),  "bullet": Color(1.0, 0.5, 0.3)},
	"toxic":   {"name": "Toxic",   "price": 600,  "body": Color(0.3, 0.85, 0.3),  "accent": Color(0.85, 1.0, 0.6), "bullet": Color(0.6, 1.0, 0.2)},
	"royal":   {"name": "Royal",   "price": 1000, "body": Color(0.55, 0.3, 0.9),  "accent": Color(1.0, 0.85, 0.3), "bullet": Color(0.9, 0.6, 1.0)},
	"gold":    {"name": "Gold",    "price": 1800, "body": Color(1.0, 0.78, 0.2),  "accent": Color(1.0, 1.0, 0.85), "bullet": Color(1.0, 1.0, 1.0)},
	"shadow":  {"name": "Shadow",  "price": 3000, "body": Color(0.15, 0.15, 0.2), "accent": Color(0.6, 0.9, 1.0),  "bullet": Color(0.4, 0.9, 1.0)},
}

var coins: int = 0
var level: int = 1
var best_score: int = 0
var upgrades := {"damage": 0, "fire_rate": 0, "squad": 0, "shield": 0, "coins": 0}
var owned_skins: Array = ["classic"]
var skin: String = "classic"
var sound_on: bool = true
var music_on: bool = true


func _ready() -> void:
	load_game()


func upgrade_cost(id: String) -> int:
	var info = UPGRADE_INFO[id]
	return int(info["base"] * pow(1.6, upgrades[id]))


func is_maxed(id: String) -> bool:
	return upgrades[id] >= UPGRADE_INFO[id]["max"]


func buy_upgrade(id: String) -> bool:
	if is_maxed(id):
		return false
	var cost := upgrade_cost(id)
	if coins < cost:
		return false
	coins -= cost
	upgrades[id] += 1
	save_game()
	return true


func buy_skin(id: String) -> bool:
	if owned_skins.has(id):
		return false
	var price: int = SKINS[id]["price"]
	if coins < price:
		return false
	coins -= price
	owned_skins.append(id)
	skin = id
	save_game()
	return true


func equip_skin(id: String) -> void:
	if owned_skins.has(id):
		skin = id
		save_game()


func reset_progress() -> void:
	coins = 0
	level = 1
	best_score = 0
	for k in upgrades.keys():
		upgrades[k] = 0
	owned_skins = ["classic"]
	skin = "classic"
	save_game()


func save_game() -> void:
	var data := {
		"coins": coins,
		"level": level,
		"best_score": best_score,
		"upgrades": upgrades,
		"owned_skins": owned_skins,
		"skin": skin,
		"sound_on": sound_on,
		"music_on": music_on,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	coins = int(data.get("coins", 0))
	level = maxi(1, int(data.get("level", 1)))
	best_score = int(data.get("best_score", 0))
	var up = data.get("upgrades", {})
	if typeof(up) == TYPE_DICTIONARY:
		for k in upgrades.keys():
			upgrades[k] = clampi(int(up.get(k, 0)), 0, int(UPGRADE_INFO[k]["max"]))
	var sk = data.get("owned_skins", [])
	owned_skins = ["classic"]
	if typeof(sk) == TYPE_ARRAY:
		for s in sk:
			if SKINS.has(s) and not owned_skins.has(s):
				owned_skins.append(s)
	var cur := str(data.get("skin", "classic"))
	skin = cur if owned_skins.has(cur) else "classic"
	sound_on = bool(data.get("sound_on", true))
	music_on = bool(data.get("music_on", true))
