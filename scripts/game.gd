extends Node2D
## Core gameplay: squad movement, auto-fire, enemy waves, bonus crates, boss.
## Everything is drawn with _draw(), so no art assets are needed.

signal run_finished(result: Dictionary)

const W := 480.0
const H := 854.0
const TRACK_L := 30.0
const TRACK_R := 450.0
const PLAYER_Y := 690.0
const LEVEL_TIME := 50.0        # seconds of waves before the boss arrives
const MAX_UNITS := 30
const SHOOTERS := 10            # soldiers beyond this add damage instead of extra bullets
const BULLET_SPEED := 760.0
const MOVE_SPEED := 460.0       # keyboard speed (px/s)
const SUPER_DURATION := 4.0     # seconds of spiral bullet storm after grabbing the super orb
const ORB_DROP_CHANCE := 0.05   # chance a kill drops a super orb (brutes: 5x)
const ORB_COOLDOWN := 14.0      # minimum seconds between orb drops

const ENEMY_TYPES := {
	"grunt":  {"hp": 3.0,  "speed": 75.0,  "r": 13.0, "dmg": 1, "score": 10, "color": Color(0.9, 0.25, 0.3)},
	"runner": {"hp": 1.6,  "speed": 140.0, "r": 10.0, "dmg": 1, "score": 15, "color": Color(1.0, 0.55, 0.15)},
	"brute":  {"hp": 16.0, "speed": 45.0,  "r": 22.0, "dmg": 3, "score": 50, "color": Color(0.6, 0.15, 0.5)},
}

const BONUS_INFO := {
	"rapid":  {"label": "RAPID",    "sub": "+25% fire rate",        "color": Color(1.0, 0.8, 0.2)},
	"squad":  {"label": "+2 SQUAD", "sub": "Reinforcements!",       "color": Color(0.3, 0.9, 0.5)},
	"power":  {"label": "POWER",    "sub": "+35% damage",           "color": Color(1.0, 0.35, 0.35)},
	"spread": {"label": "SPREAD",   "sub": "+2 angled shots",       "color": Color(0.7, 0.5, 1.0)},
	"pierce": {"label": "PIERCE",   "sub": "Bullets pass through",  "color": Color(0.3, 0.8, 1.0)},
	"shield": {"label": "SHIELD",   "sub": "Blocks one hit",        "color": Color(0.6, 0.95, 1.0)},
}
const BONUS_WEIGHTS := {"squad": 25, "rapid": 20, "power": 20, "spread": 12, "pierce": 10, "shield": 13}

var running := false
var paused := false
var ended := false
var victory := false
var end_timer := 0.0

var level := 1
var t := 0.0
var progress := 0.0
var scroll := 0.0
var shake := 0.0

var px := W * 0.5
var target_x := W * 0.5
var units := 3
var shield := 0
var damage := 1.0
var fire_interval := 0.3
var spread := 0
var pierce := 0
var fire_timer := 0.0

var bullets: Array = []
var enemies: Array = []
var crates: Array = []
var particles: Array = []
var texts: Array = []
var boss = null
var boss_spawned := false
var spawn_timer := 1.0
var crate_timer := 2.0
var next_id := 0

var orbs: Array = []
var rings: Array = []
var orb_cooldown := 8.0
var super_time := 0.0
var super_fire_timer := 0.0
var super_angle := 0.0
var flash := 0.0
var slowmo := 0.0

var kills := 0
var kill_points := 0
var crates_opened := 0
var score := 0

var skin: Dictionary = {}
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	skin = Save.SKINS[Save.skin]


# ---------------------------------------------------------------- run control

func start_run() -> void:
	level = Save.level
	skin = Save.SKINS[Save.skin]
	t = 0.0
	progress = 0.0
	shake = 0.0
	px = W * 0.5
	target_x = px
	units = 3 + int(Save.upgrades["squad"])
	shield = int(Save.upgrades["shield"])
	damage = 1.0 + 0.2 * Save.upgrades["damage"]
	fire_interval = 0.3 / (1.0 + 0.1 * Save.upgrades["fire_rate"])
	spread = 0
	pierce = 0
	fire_timer = 0.0
	_clear()
	spawn_timer = 1.2
	crate_timer = 2.5
	kills = 0
	kill_points = 0
	crates_opened = 0
	score = 0
	ended = false
	victory = false
	paused = false
	running = true
	_text(Vector2(W * 0.5, 360), "LEVEL %d" % level, Color.WHITE, 1.6, 40)
	Sfx.play("level_start")
	Music.set_duck(0.0)
	Music.play(Music.level_track(level), 0.8)


func stop() -> void:
	running = false
	paused = false
	ended = false
	_clear()


func _clear() -> void:
	bullets.clear()
	enemies.clear()
	crates.clear()
	particles.clear()
	texts.clear()
	boss = null
	boss_spawned = false
	orbs.clear()
	rings.clear()
	orb_cooldown = 8.0
	super_time = 0.0
	super_fire_timer = 0.0
	flash = 0.0
	slowmo = 0.0


func _result() -> Dictionary:
	return {
		"victory": victory,
		"level": level,
		"kills": kills,
		"kill_points": kill_points,
		"crates": crates_opened,
		"units": units,
		"progress": 1.0 if victory else progress,
	}


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not running or paused or ended:
		return
	# Drag anywhere (mouse or touch, since touch emulates mouse by default).
	var motion := event as InputEventMouseMotion
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
		target_x += motion.relative.x * 1.2


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	if not paused:
		var spd := 220.0 if running else 60.0
		scroll = fmod(scroll + spd * delta, 80.0)
	if running and not paused:
		_update(delta)
	queue_redraw()


func _update(d: float) -> void:
	if ended:
		_update_fx(d)
		end_timer -= d
		if end_timer <= 0.0:
			running = false
			run_finished.emit(_result())
		return

	if slowmo > 0.0:
		slowmo -= d
		d *= 0.25
	t += d
	progress = minf(t / LEVEL_TIME, 1.0)

	# Movement
	var dir := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		dir += 1.0
	target_x += dir * MOVE_SPEED * d
	var hw := squad_half_width()
	target_x = clampf(target_x, TRACK_L + hw, TRACK_R - hw)
	px = lerpf(px, target_x, minf(1.0, d * 18.0))

	# Shooting
	fire_timer -= d
	if fire_timer <= 0.0:
		fire_timer = maxf(fire_timer + fire_interval, 0.0)
		_fire()

	# Spawning
	if progress < 1.0:
		spawn_timer -= d
		if spawn_timer <= 0.0:
			_spawn_row()
			spawn_timer = maxf(0.5, 1.8 - progress * 0.9 - (level - 1) * 0.06)
	elif not boss_spawned:
		_spawn_boss()

	crate_timer -= d
	if crate_timer <= 0.0:
		_spawn_crate()
		crate_timer = randf_range(3.5, 5.0) if boss == null else randf_range(5.0, 7.0)

	orb_cooldown -= d
	if super_time > 0.0:
		super_time -= d
		super_angle += d * 2.4
		super_fire_timer -= d
		if super_fire_timer <= 0.0:
			super_fire_timer = 0.03
			_fire_super()

	_update_bullets(d)
	if ended:
		return
	_update_orbs(d)
	_update_enemies(d)
	_update_crates(d)
	_update_boss(d)
	_update_fx(d)


func unit_offsets() -> Array:
	var arr: Array = []
	var per_row := 5
	for i in units:
		var row := int(i / float(per_row))
		var in_row := mini(per_row, units - row * per_row)
		var col := i % per_row
		arr.append(Vector2((col - (in_row - 1) / 2.0) * 17.0, row * 15.0))
	return arr


func squad_half_width() -> float:
	return (mini(units, 5) - 1) * 8.5 + 10.0


func _squad_rows() -> int:
	return int((units - 1) / 5.0)


func _fire() -> void:
	Sfx.play("shoot")
	var offs := unit_offsets()
	var n := mini(offs.size(), SHOOTERS)
	for i in n:
		var o: Vector2 = offs[i]
		_add_bullet(Vector2(px + o.x + 4.5, PLAYER_Y + o.y - 16.0), Vector2(0, -BULLET_SPEED))
	for s in range(1, spread + 1):
		for sd in [-1.0, 1.0]:
			var ang: float = sd * 0.12 * s
			_add_bullet(Vector2(px, PLAYER_Y - 16.0), Vector2(sin(ang), -cos(ang)) * BULLET_SPEED)


func _add_bullet(pos: Vector2, vel: Vector2) -> void:
	bullets.append({"p": pos, "v": vel, "pierce": pierce, "hit": []})


func _update_bullets(d: float) -> void:
	var dmg := damage * maxf(1.0, float(units) / SHOOTERS)
	var keep: Array = []
	for b in bullets:
		b.p += b.v * d
		var bp: Vector2 = b.p
		if bp.y < -30.0 or bp.y > H + 30.0 or bp.x < -10.0 or bp.x > W + 10.0:
			continue
		var is_super: bool = b.get("super", false)
		var bd := dmg * (3.0 if is_super else 1.0)
		var alive := true
		# Crates soak up bullets
		for c in crates:
			if c.dead:
				continue
			if absf(bp.x - c.p.x) < c.w * 0.5 and absf(bp.y - c.p.y) < c.h * 0.5:
				c.hp -= bd
				c.flash = 0.06
				Sfx.play("crate_hit")
				if c.hp <= 0.0:
					_open_crate(c)
				alive = false
				break
		if alive:
			for e in enemies:
				if e.dead or b.hit.has(e.id):
					continue
				var rr: float = e.r + 4.0
				if bp.distance_squared_to(e.p) < rr * rr:
					_damage_enemy(e, bd)
					if is_super and rings.size() < 160:
						_ring(bp, 3.0, 22.0, 0.22, b.col, 3.0)
					if b.pierce > 0:
						b.pierce -= 1
						b.hit.append(e.id)
					else:
						alive = false
						break
		if alive and boss != null:
			var br: float = boss.r + 4.0
			if bp.distance_squared_to(boss.p) < br * br:
				_damage_boss(bd)
				if is_super and boss != null and rings.size() < 160:
					_ring(bp, 4.0, 30.0, 0.25, b.col, 3.0)
				alive = false
		if alive:
			keep.append(b)
	bullets = keep


func _update_enemies(d: float) -> void:
	var top := PLAYER_Y - 12.0
	var bottom := PLAYER_Y + _squad_rows() * 15.0 + 10.0
	var hw := squad_half_width()
	for e in enemies:
		if e.dead:
			continue
		if e.doom > -0.5:
			e.doom -= d
			if e.doom <= 0.0:
				e.doom = -1.0
				_damage_enemy(e, e.hp + 1.0, true)
				continue
		e.p += Vector2(0, e.speed * d)
		e.flash = maxf(0.0, e.flash - d)
		e.wob += d * 6.0
		var ep: Vector2 = e.p
		var r: float = e.r
		if ep.y + r >= top and ep.y - r <= bottom and absf(ep.x - px) <= hw + r:
			e.dead = true
			_hit_squad(e.dmg, ep)
			if ended:
				break
		elif ep.y > H + 40.0:
			e.dead = true
	enemies = enemies.filter(func(e): return not e.dead)


func _update_crates(d: float) -> void:
	for c in crates:
		c.p += Vector2(0, 75.0 * d)
		c.flash = maxf(0.0, c.flash - d)
		if c.p.y > H + 60.0:
			c.dead = true
	crates = crates.filter(func(c): return not c.dead)


func _update_boss(d: float) -> void:
	if boss == null:
		return
	boss.t += d
	boss.flash = maxf(0.0, boss.flash - d)
	if boss.doom > -0.5:
		boss.doom -= d
		if boss.doom <= 0.0:
			boss.doom = -1.0
			var bpos: Vector2 = boss.p
			for i in 6:
				_explode(bpos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * boss.r, randf_range(30.0, 50.0), Color(1, 0.6, 0.2))
			Sfx.play("super_blast", -4.0, 0.8)
			_damage_boss(boss.max_hp * 0.3)
			if boss == null:
				return
	var bp: Vector2 = boss.p
	var vy := 60.0 if bp.y < 150.0 else 14.0 + level * 0.8
	boss.p = Vector2(W * 0.5 + sin(boss.t * 0.7) * 130.0, bp.y + vy * d)
	boss.spawn -= d
	if boss.spawn <= 0.0:
		boss.spawn = maxf(1.0, 2.4 - level * 0.1)
		_spawn_enemy("grunt", boss.p + Vector2(-45, 30))
		_spawn_enemy("grunt", boss.p + Vector2(45, 30))
	if boss.p.y + boss.r >= PLAYER_Y - 12.0:
		units = 0
		shake = 14.0
		_end(false)


func _update_fx(d: float) -> void:
	var damp := pow(0.05, d)
	for p in particles:
		p.p += p.v * d
		p.v *= damp
		p.life -= d
	particles = particles.filter(func(p): return p.life > 0.0)
	for tx in texts:
		tx.p += Vector2(0, -35.0 * d)
		tx.life -= d
	texts = texts.filter(func(tx): return tx.life > 0.0)
	for rg in rings:
		rg.life -= d
	rings = rings.filter(func(rg): return rg.life > 0.0)
	shake = maxf(0.0, shake - 40.0 * d)
	flash = maxf(0.0, flash - d * 2.2)


# ---------------------------------------------------------------- spawning

func _hp_scale() -> float:
	return (1.0 + 0.45 * (level - 1)) * (1.0 + progress * 1.6)


func _spawn_row() -> void:
	var lo := 1 + int(progress * 2.0)
	var hi := mini(2 + int(level / 2.0) + int(progress * 3.0), 7)
	var count := randi_range(lo, maxi(lo, hi))
	var xs: Array = []
	var tries := 0
	while xs.size() < count and tries < 40:
		tries += 1
		var x := randf_range(TRACK_L + 22.0, TRACK_R - 22.0)
		var ok := true
		for o in xs:
			if absf(o - x) < 46.0:
				ok = false
				break
		if ok:
			xs.append(x)
	for x in xs:
		_spawn_enemy(_pick_enemy_type(), Vector2(x, -30.0 - randf() * 40.0))


func _pick_enemy_type() -> String:
	var r := randf()
	var brute := 0.04 + progress * 0.12 + level * 0.01
	var runner := 0.1 + progress * 0.15
	if r < brute:
		return "brute"
	if r < brute + runner:
		return "runner"
	return "grunt"


func _spawn_enemy(type: String, pos: Vector2) -> void:
	var def = ENEMY_TYPES[type]
	var hp: float = def.hp * _hp_scale()
	enemies.append({
		"id": next_id, "type": type, "p": pos, "hp": hp, "max_hp": hp,
		"speed": def.speed * (1.0 + 0.03 * (level - 1)), "r": def.r,
		"dmg": def.dmg, "score": def.score, "color": def.color,
		"dead": false, "flash": 0.0, "wob": randf() * 6.0, "doom": -1.0,
	})
	next_id += 1


func _pick_bonus() -> String:
	var pool := {}
	for k in BONUS_WEIGHTS:
		pool[k] = BONUS_WEIGHTS[k]
	if spread >= 4:
		pool.erase("spread")
	if pierce >= 3:
		pool.erase("pierce")
	if units >= MAX_UNITS:
		pool.erase("squad")
	if fire_interval <= 0.07:
		pool.erase("rapid")
	var total := 0
	for k in pool:
		total += int(pool[k])
	var r := randi() % total
	for k in pool:
		r -= int(pool[k])
		if r < 0:
			return k
	return "power"


func _spawn_crate() -> void:
	var hp := (6.0 + level * 3.0) * (1.0 + progress * 2.0)
	crates.append({
		"type": _pick_bonus(),
		"p": Vector2(randf_range(TRACK_L + 50.0, TRACK_R - 50.0), -40.0),
		"w": 92.0, "h": 58.0, "hp": hp, "max_hp": hp, "dead": false, "flash": 0.0,
	})


func _spawn_boss() -> void:
	boss_spawned = true
	var hp := 400.0 * (1.0 + 0.6 * (level - 1))
	boss = {"p": Vector2(W * 0.5, -70.0), "hp": hp, "max_hp": hp, "r": 50.0, "flash": 0.0, "t": 0.0, "spawn": 2.5, "doom": -1.0}
	_text(Vector2(W * 0.5, 320), "BOSS INCOMING!", Color(1, 0.3, 0.3), 2.0, 34)
	Sfx.play("boss_alarm")
	Music.play("boss", 1.5)


# ---------------------------------------------------------------- events

func _damage_enemy(e: Dictionary, dmg: float, nuked := false) -> void:
	e.hp -= dmg
	e.flash = 0.06
	if e.hp <= 0.0 and not e.dead:
		e.dead = true
		kills += 1
		kill_points += e.score
		score += e.score
		if nuked:
			_explode(e.p, e.r * 2.2, e.color)
			Sfx.play("explosion")
		elif super_time > 0.0 or e.type == "brute":
			_explode(e.p, e.r * 1.5, e.color)
			Sfx.play("brute_die" if e.type == "brute" else "explosion", -3.0)
		else:
			_burst(e.p, e.color, 8 + int(e.r / 2.0))
			Sfx.play("enemy_die")
		if not nuked:
			_maybe_drop_orb(e)
	else:
		Sfx.play("hit")


func _damage_boss(dmg: float) -> void:
	boss.hp -= dmg
	boss.flash = 0.05
	Sfx.play("boss_hit")
	if boss.hp <= 0.0:
		Sfx.play("boss_die")
		var bp: Vector2 = boss.p
		_burst(bp, Color(1, 0.5, 0.3), 80, 420.0)
		_burst(bp, Color(1, 0.9, 0.4), 50, 300.0)
		score += 1000 * level
		boss = null
		shake = 16.0
		_end(true)


func _open_crate(c: Dictionary) -> void:
	c.dead = true
	crates_opened += 1
	score += 50
	var info = BONUS_INFO[c.type]
	match c.type:
		"rapid":
			fire_interval = maxf(0.06, fire_interval / 1.25)
		"squad":
			units = mini(MAX_UNITS, units + 2)
		"power":
			damage *= 1.35
		"spread":
			spread += 1
		"pierce":
			pierce += 1
		"shield":
			shield += 1
	_burst(c.p, info.color, 24, 260.0)
	Sfx.play("powerup")
	_text(c.p, info.label + "!", info.color, 1.2, 26)
	_text(Vector2(px, PLAYER_Y - 55.0), info.sub, Color.WHITE, 1.0, 16)


func _hit_squad(amount: int, pos: Vector2) -> void:
	shake = 9.0
	if shield > 0:
		shield -= 1
		_text(Vector2(px, PLAYER_Y - 45.0), "BLOCKED!", Color(0.6, 0.95, 1.0), 0.8, 20)
		_burst(pos, Color(0.6, 0.95, 1.0), 16)
		Sfx.play("shield_block")
		return
	units -= amount
	_text(Vector2(px, PLAYER_Y - 45.0), "-%d" % amount, Color(1, 0.3, 0.3), 0.8, 24)
	_burst(pos, skin.body, 18)
	Sfx.play("squad_hurt", 0.0, 1.0 if amount == 1 else 0.8)
	if units <= 0:
		units = 0
		_end(false)


func _end(win: bool) -> void:
	if ended:
		return
	ended = true
	victory = win
	end_timer = 1.8
	Music.stop(0.4)
	super_time = 0.0
	orbs.clear()
	if win:
		for e in enemies:
			_burst(e.p, e.color, 8)
		enemies.clear()
		crates.clear()
		_text(Vector2(W * 0.5, 360), "VICTORY!", Color(1, 0.85, 0.3), 1.8, 46)
		Sfx.play("victory")
	else:
		_burst(Vector2(px, PLAYER_Y), skin.body, 40, 260.0)
		_text(Vector2(W * 0.5, 360), "SQUAD DOWN", Color(1, 0.35, 0.35), 1.8, 42)
		Sfx.play("defeat")


func _burst(pos: Vector2, col: Color, n: int, spd := 180.0) -> void:
	for i in n:
		var a := randf() * TAU
		var s := randf_range(0.3, 1.0) * spd
		var life := randf_range(0.3, 0.7)
		particles.append({"p": pos, "v": Vector2(cos(a), sin(a)) * s, "life": life, "ml": life, "c": col, "s": randf_range(2.0, 4.5)})
	if particles.size() > 1400:
		particles = particles.slice(particles.size() - 1400)


func _text(pos: Vector2, text: String, col: Color, life := 1.0, size := 22) -> void:
	texts.append({"p": pos, "text": text, "c": col, "life": life, "ml": life, "s": size})


# ---------------------------------------------------------------- super weapon

func _maybe_drop_orb(e: Dictionary) -> void:
	if not orbs.is_empty() or super_time > 0.0 or orb_cooldown > 0.0:
		return
	if e.p.y > PLAYER_Y - 180.0:
		return
	var chance := ORB_DROP_CHANCE * (5.0 if e.type == "brute" else 1.0)
	if randf() < chance:
		_spawn_orb(e.p)


func _spawn_orb(pos: Vector2) -> void:
	orbs.append({"p": pos, "v": Vector2(randf_range(-1.0, 1.0) * 130.0, 62.0), "t": 0.0, "dead": false})
	orb_cooldown = ORB_COOLDOWN
	Sfx.play("super_spawn")
	_ring(pos, 6.0, 60.0, 0.5, Color(1, 0.95, 0.5), 4.0)
	_text(pos + Vector2(0, -24), "SUPER!", Color(1, 0.9, 0.3), 1.0, 18)


func _update_orbs(d: float) -> void:
	var squad_c := Vector2(px, PLAYER_Y + _squad_rows() * 7.5)
	var reach := squad_half_width() + 20.0
	for o in orbs:
		o.t += d
		var p: Vector2 = o.p
		var v: Vector2 = o.v
		# wander: drift down, zig-zag, random direction changes, bounce off the rails
		if randf() < d * 1.3:
			v.x = randf_range(-1.0, 1.0) * 160.0
		p += Vector2(v.x + sin(o.t * 5.0) * 90.0, v.y) * d
		if p.x < TRACK_L + 18.0:
			p.x = TRACK_L + 18.0
			v.x = absf(v.x)
		elif p.x > TRACK_R - 18.0:
			p.x = TRACK_R - 18.0
			v.x = -absf(v.x)
		o.p = p
		o.v = v
		if randf() < 0.6:
			var hue := fmod(o.t * 0.6 + randf() * 0.2, 1.0)
			particles.append({"p": p + Vector2(randf_range(-8, 8), randf_range(-8, 8)), "v": Vector2(randf_range(-30, 30), randf_range(-60, -10)),
				"life": 0.5, "ml": 0.5, "c": Color.from_hsv(hue, 0.6, 1.0), "s": randf_range(1.5, 3.0)})
		if p.distance_to(squad_c) < reach:
			o.dead = true
			_activate_super(p)
		elif p.y > H + 30.0:
			o.dead = true
	orbs = orbs.filter(func(o): return not o.dead)


func _activate_super(pos: Vector2) -> void:
	super_time = SUPER_DURATION
	super_fire_timer = 0.0
	flash = 1.0
	shake = 20.0
	slowmo = 0.35
	Sfx.play("super_pickup")
	Sfx.play("super_blast")
	_text(Vector2(W * 0.5, 330), "SUPER SURGE!", Color(1, 0.9, 0.3), 1.8, 44)
	_explode(pos, 50.0, Color(1, 0.95, 0.6))
	# giant shockwaves rolling out from the squad across the whole screen
	var origin := Vector2(px, PLAYER_Y)
	_ring(origin, 10.0, 950.0, 0.9, Color(1, 1, 1), 14.0)
	_ring(origin, 10.0, 750.0, 0.75, Color(1, 0.85, 0.3), 8.0)
	_ring(origin, 10.0, 550.0, 0.6, Color(0.6, 0.9, 1.0), 6.0)
	# every enemy on screen explodes as the shockwave reaches it
	for e in enemies:
		if not e.dead and e.p.y > -20.0:
			e.doom = 0.05 + e.p.distance_to(origin) / 1100.0
	if boss != null:
		boss.doom = 0.05 + boss.p.distance_to(origin) / 1100.0


func _fire_super() -> void:
	# Two counter-rotating 5-arm spirals: they draw curved rainbow arms that cross into a flower.
	var arms := 5
	var c := Vector2(px, PLAYER_Y - 12.0)
	for k in arms:
		var base := k * TAU / arms
		var hue := fmod(t * 0.7 + k / float(arms), 1.0)
		var spin := [super_angle + base, -super_angle + base + PI / arms]
		for j in 2:
			var ang: float = spin[j]
			var dir := Vector2(cos(ang), sin(ang))
			var col := Color.from_hsv(fmod(hue + j * 0.5, 1.0), 0.65, 1.0)
			bullets.append({"p": c + dir * 16.0, "v": dir * 470.0, "pierce": 3, "hit": [],
				"super": true, "col": col})
	Sfx.play("super_zap")


func _explode(pos: Vector2, size: float, col: Color) -> void:
	_ring(pos, size * 0.25, size * 2.0, 0.42, col.lightened(0.3), 5.0)
	_ring(pos, size * 0.1, size * 1.2, 0.3, Color(1, 1, 0.85), 3.0)
	# hot white core
	particles.append({"p": pos, "v": Vector2.ZERO, "life": 0.14, "ml": 0.14, "c": Color(1, 1, 0.9), "s": size * 0.9})
	particles.append({"p": pos, "v": Vector2.ZERO, "life": 0.22, "ml": 0.22, "c": Color(1, 0.6, 0.2), "s": size * 0.65})
	_burst(pos, col, 10 + int(size / 3.0), 150.0 + size * 6.0)
	_burst(pos, Color(1, 0.85, 0.4), 6 + int(size / 6.0), 320.0 + size * 4.0)


func _ring(pos: Vector2, r0: float, r1: float, life: float, col: Color, width: float) -> void:
	rings.append({"p": pos, "r0": r0, "r1": r1, "life": life, "ml": life, "c": col, "w": width})


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.6
	draw_set_transform(off)

	# Ground + track
	draw_rect(Rect2(-30, -30, W + 60, H + 60), Color(0.05, 0.06, 0.1))
	var y := -80.0 + scroll
	while y < H + 80.0:
		draw_rect(Rect2(-30, y, TRACK_L + 30, 40), Color(0.08, 0.09, 0.14))
		draw_rect(Rect2(TRACK_R, y, W - TRACK_R + 30, 40), Color(0.08, 0.09, 0.14))
		y += 80.0
	draw_rect(Rect2(TRACK_L, -30, TRACK_R - TRACK_L, H + 60), Color(0.13, 0.15, 0.22))
	y = -80.0 + scroll
	var i := 0
	while y < H + 80.0:
		var rail := Color(0.95, 0.3, 0.35) if i % 2 == 0 else Color(0.92, 0.92, 0.95)
		draw_rect(Rect2(TRACK_L - 6, y, 6, 40), rail)
		draw_rect(Rect2(TRACK_R, y, 6, 40), rail)
		if i % 2 == 0:
			draw_rect(Rect2(W * 0.5 - 2, y + 8, 4, 24), Color(1, 1, 1, 0.07))
		y += 40.0
		i += 1

	for c in crates:
		_draw_crate(c)
	for e in enemies:
		_draw_enemy(e)
	if boss != null:
		_draw_boss()

	var bc: Color = skin.get("bullet", Color.YELLOW)
	var trail := Color(bc.r, bc.g, bc.b, 0.35)
	for b in bullets:
		var bp: Vector2 = b.p
		var bv: Vector2 = b.v
		if b.get("super", false):
			var sc: Color = b.col
			draw_line(bp, bp - bv.normalized() * 16.0, Color(sc.r, sc.g, sc.b, 0.45), 5.0)
			draw_circle(bp, 5.5, Color(sc.r, sc.g, sc.b, 0.35))
			draw_circle(bp, 3.5, sc.lightened(0.4))
		else:
			draw_line(bp, bp - bv.normalized() * 12.0, trail, 3.0)
			draw_circle(bp, 3.5, bc)

	for o in orbs:
		_draw_orb(o)

	if running and units > 0:
		_draw_squad()

	for rg in rings:
		var k: float = 1.0 - rg.life / rg.ml          # 0 -> 1 over the ring's life
		var ez := 1.0 - pow(1.0 - k, 3.0)
		var r: float = lerpf(rg.r0, rg.r1, ez)
		var rc: Color = rg.c
		var a := 1.0 - k
		draw_arc(rg.p, r, 0.0, TAU, 56, Color(rc.r, rc.g, rc.b, a), maxf(1.0, rg.w * (0.3 + 0.7 * a)))
		if k < 0.3:
			draw_circle(rg.p, r * 0.55, Color(rc.r, rc.g, rc.b, (0.3 - k) * 1.2))

	for p in particles:
		var col: Color = p.c
		var k: float = p.life / p.ml
		draw_circle(p.p, p.s * (0.4 + 0.6 * k), Color(col.r, col.g, col.b, k))

	for tx in texts:
		var col: Color = tx.c
		var a := clampf(tx.life / 0.35, 0.0, 1.0)
		_ctext(tx.p, tx.text, tx.s, Color(col.r, col.g, col.b, a), 5)

	draw_set_transform(Vector2.ZERO)

	# rainbow border while the super weapon is active
	if super_time > 0.0 and running:
		var hc := Color.from_hsv(fmod(t * 1.5, 1.0), 0.7, 1.0)
		var pulse := 0.25 + 0.15 * sin(t * 18.0)
		draw_rect(Rect2(0, 0, W, H), Color(hc.r, hc.g, hc.b, pulse), false, 10.0)
	# full-screen flash
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 0.95, minf(flash, 1.0) * 0.85))


func _draw_orb(o: Dictionary) -> void:
	var p: Vector2 = o.p
	var tt: float = o.t
	var col := Color.from_hsv(fmod(tt * 0.6, 1.0), 0.55, 1.0)
	var pulse := 1.0 + 0.18 * sin(tt * 10.0)
	draw_circle(p, 30.0 * pulse, Color(col.r, col.g, col.b, 0.12))
	draw_circle(p, 21.0 * pulse, Color(col.r, col.g, col.b, 0.28))
	var pts := PackedVector2Array()
	for i in 10:
		var ang := tt * 3.0 + i * TAU / 10.0 - PI / 2.0
		var rad := 15.0 if i % 2 == 0 else 6.5
		pts.append(p + Vector2(cos(ang), sin(ang)) * rad * pulse)
	draw_colored_polygon(pts, Color(1, 1, 0.85))
	draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.0)
	draw_circle(p, 4.0, Color.WHITE)


func _draw_squad() -> void:
	var offs := unit_offsets()
	var body: Color = skin.body
	var accent: Color = skin.accent
	for idx in offs.size():
		var o: Vector2 = offs[idx]
		var p := Vector2(px, PLAYER_Y) + o + Vector2(0, sin(t * 14.0 + idx) * 1.5)
		draw_circle(p + Vector2(0, 5), 9.0, Color(0, 0, 0, 0.3))
		draw_circle(p, 8.5, body)
		draw_rect(Rect2(p.x + 3.0, p.y - 16.0, 3.5, 12.0), Color(0.15, 0.15, 0.18))
		draw_circle(p + Vector2(0, -1), 4.5, accent)
	var rows := _squad_rows()
	var center := Vector2(px, PLAYER_Y + rows * 7.5)
	if super_time > 0.0:
		var hc := Color.from_hsv(fmod(t * 2.0, 1.0), 0.6, 1.0)
		var rad2 := squad_half_width() + 26.0 + rows * 7.5
		draw_circle(center, rad2, Color(hc.r, hc.g, hc.b, 0.12))
		draw_arc(center, rad2, -PI / 2.0, -PI / 2.0 + TAU * (super_time / SUPER_DURATION), 48, Color(hc.r, hc.g, hc.b, 0.9), 4.0)
	if shield > 0:
		var rad := squad_half_width() + 14.0 + rows * 7.5
		draw_arc(center, rad, 0.0, TAU, 40, Color(0.5, 0.9, 1.0, 0.5 + 0.2 * sin(t * 6.0)), 3.0)
	var label := str(units)
	if shield > 0:
		label += "  +%d" % shield
	_ctext(Vector2(px, PLAYER_Y - 34.0), label, 18, Color.WHITE, 5)


func _draw_enemy(e: Dictionary) -> void:
	var r: float = e.r
	var p: Vector2 = e.p + Vector2(sin(e.wob) * 1.5, 0)
	var col: Color = Color.WHITE if e.flash > 0.0 else e.color
	draw_circle(p + Vector2(0, 5), r, Color(0, 0, 0, 0.3))
	draw_circle(p, r, col)
	draw_circle(p + Vector2(0, -r * 0.15), r * 0.75, col.lightened(0.1))
	var er := r * 0.26
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = p + Vector2(sx * r * 0.36, -r * 0.12)
		draw_circle(eye, er, Color.WHITE)
		draw_circle(eye + Vector2(0, er * 0.3), er * 0.5, Color(0.1, 0, 0.05))
		draw_line(eye + Vector2(-sx * er * 1.3, -er * 1.6), eye + Vector2(sx * er * 1.1, -er * 0.9), Color(0.1, 0, 0.05), 2.0)
	if e.type == "brute" and e.hp < e.max_hp:
		var frac: float = clampf(e.hp / e.max_hp, 0.0, 1.0)
		draw_rect(Rect2(p.x - r, p.y - r - 10, r * 2, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p.x - r, p.y - r - 10, r * 2 * frac, 5), Color(1, 0.3, 0.3))


func _draw_crate(c: Dictionary) -> void:
	var info = BONUS_INFO[c.type]
	var col: Color = info.color
	var size := Vector2(c.w, c.h)
	var rect := Rect2(c.p - size * 0.5, size)
	draw_rect(Rect2(rect.position + Vector2(0, 5), size), Color(0, 0, 0, 0.3))
	draw_rect(rect, col.lightened(0.35) if c.flash > 0.0 else col.darkened(0.65))
	var frac: float = 1.0 - clampf(c.hp / c.max_hp, 0.0, 1.0)
	draw_rect(Rect2(rect.position.x, rect.end.y - 7.0, size.x * frac, 7.0), col)
	draw_rect(rect, col, false, 3.0)
	_ctext(c.p + Vector2(0, -12), info.label, 15, Color.WHITE, 3)
	_ctext(c.p + Vector2(0, 10), str(ceili(c.hp)), 22, col.lightened(0.4), 4)


func _draw_boss() -> void:
	var p: Vector2 = boss.p
	var r: float = boss.r
	var base := Color(0.55, 0.1, 0.2)
	var col: Color = Color.WHITE if boss.flash > 0.0 else base
	var horn := Color(0.9, 0.85, 0.7)
	draw_circle(p + Vector2(0, 8), r, Color(0, 0, 0, 0.35))
	for sx in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(sx * r * 0.75, -r * 0.45),
			p + Vector2(sx * r * 1.0, -r * 1.35),
			p + Vector2(sx * r * 0.25, -r * 0.85),
		]), horn)
	draw_circle(p, r, col)
	draw_circle(p + Vector2(0, -r * 0.1), r * 0.78, col.lightened(0.12))
	for sx in [-1.0, 1.0]:
		var eye: Vector2 = p + Vector2(sx * r * 0.35, -r * 0.12)
		draw_circle(eye, r * 0.18, Color(1, 0.9, 0.2))
		draw_circle(eye + Vector2(0, r * 0.04), r * 0.08, Color(0.1, 0, 0.05))
		draw_line(eye + Vector2(-sx * r * 0.28, -r * 0.3), eye + Vector2(sx * r * 0.2, -r * 0.15), Color(0.1, 0, 0.05), 4.0)
	draw_rect(Rect2(p.x - r * 0.4, p.y + r * 0.3, r * 0.8, r * 0.16), Color(0.1, 0, 0.05))
	# Health bar
	var frac: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
	draw_rect(Rect2(40, 78, 400, 14), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(40, 78, 400 * frac, 14), Color(0.95, 0.25, 0.3))
	draw_rect(Rect2(40, 78, 400, 14), Color(1, 1, 1, 0.5), false, 2.0)
	_ctext(Vector2(W * 0.5, 104), "BOSS", 14, Color.WHITE, 3)


func _ctext(center: Vector2, text: String, size: int, col: Color, outline := 0) -> void:
	var pos := Vector2(center.x - 200.0, center.y + size * 0.35)
	if outline > 0:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, size, outline, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, size, col)
