extends Node
## Builds all menus/HUD in code and switches between screens:
## menu -> hud (playing) -> results, plus upgrades, skins and pause.

const GameScript := preload("res://scripts/game.gd")

const GOLD := Color(1.0, 0.82, 0.3)
const DIM := Color(0.65, 0.7, 0.8)

var game
var ui: CanvasLayer
var theme_main: Theme
var screens := {}

var menu_level: Label
var menu_coins: Label
var menu_best: Label
var menu_skin_preview: ColorRect

var up_coins: Label
var up_list: VBoxContainer

var skin_coins: Label
var skin_list: VBoxContainer

var hud_level: Label
var hud_score: Label
var hud_progress: ProgressBar
var hud_squad: Label
var hud_stats: Label

var res_title: Label
var res_list: VBoxContainer
var res_buttons: HBoxContainer
var res_next: Button
var res_tween: Tween

var reset_armed := false
var sound_button: Button
var music_button: Button
var reset_button: Button


func _ready() -> void:
	randomize()
	Sfx.enabled = Save.sound_on
	Music.enabled = Save.music_on
	game = GameScript.new()
	add_child(game)
	game.run_finished.connect(_on_run_finished)
	ui = CanvasLayer.new()
	add_child(ui)
	theme_main = _make_theme()
	_build_menu()
	_build_upgrades()
	_build_skins()
	_build_hud()
	_build_pause()
	_build_results()
	show_screen("menu")


func _process(_delta: float) -> void:
	if screens["hud"].visible:
		_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if event.is_action_pressed("ui_cancel") or (key != null and key.pressed and not key.echo and key.physical_keycode == KEY_P):
		_toggle_pause()


# ---------------------------------------------------------------- flow

func show_screen(id: String) -> void:
	for k in screens:
		screens[k].visible = (k == id)
	if id == "pause":
		screens["hud"].visible = true
	if id in ["menu", "upgrades", "skins"]:
		Music.set_duck(0.0)
		Music.play("menu", 1.2)
	match id:
		"menu":
			_refresh_menu()
		"upgrades":
			_refresh_upgrades()
		"skins":
			_refresh_skins()


func _start() -> void:
	if res_tween and res_tween.is_valid():
		res_tween.kill()
	show_screen("hud")
	game.start_run()


func _to_menu() -> void:
	game.stop()
	show_screen("menu")


func _toggle_pause() -> void:
	if not game.running or game.ended:
		return
	game.paused = not game.paused
	Music.set_duck(-12.0 if game.paused else 0.0)
	show_screen("pause" if game.paused else "hud")


func _on_run_finished(r: Dictionary) -> void:
	var lines: Array = []
	lines.append(["Distance", int(r.progress * 500.0)])
	lines.append(["Enemies defeated (%d)" % r.kills, int(r.kill_points)])
	lines.append(["Bonuses unlocked (%d)" % r.crates, int(r.crates) * 50])
	if r.victory:
		lines.append(["Survivors (%d)" % r.units, int(r.units) * 100])
		lines.append(["Boss defeated", 1000 * int(r.level)])
	var total := 0
	for l in lines:
		total += int(l[1])
	var mult: float = 1.0 + 0.15 * Save.upgrades["coins"]
	var earned := int(round(total / 10.0 * mult))
	var new_best: bool = total > Save.best_score
	Save.coins += earned
	Save.best_score = maxi(Save.best_score, total)
	if r.victory:
		Save.level += 1
	Save.save_game()

	res_title.text = ("LEVEL %d CLEAR!" % r.level) if r.victory else "SQUAD DOWN"
	res_title.add_theme_color_override("font_color", GOLD if r.victory else Color(1, 0.4, 0.4))
	res_next.text = "NEXT LEVEL" if r.victory else "RETRY"
	for c in res_list.get_children():
		c.queue_free()
	res_buttons.visible = false
	show_screen("results")
	Music.set_duck(-6.0, 0.0)
	Music.play("menu", 3.0)

	res_tween = create_tween()
	for l in lines:
		var row := _result_row(str(l[0]), Color.WHITE, 20)
		res_tween.tween_property(row[0], "modulate:a", 1.0, 0.15)
		res_tween.tween_method(_set_num.bind(row[1], "", float(l[1])), 0.0, float(l[1]), 0.45)
		res_tween.tween_callback(Sfx.play.bind("tally_row"))
	var sep := HSeparator.new()
	res_list.add_child(sep)
	var total_row := _result_row("TOTAL POINTS", GOLD, 26)
	res_tween.tween_property(total_row[0], "modulate:a", 1.0, 0.15)
	res_tween.tween_method(_set_num.bind(total_row[1], "", float(total)), 0.0, float(total), 0.7)
	res_tween.tween_callback(Sfx.play.bind("tally_total"))
	var coin_label := "Coins earned"
	if Save.upgrades["coins"] > 0:
		coin_label += " (Bounty +%d%%)" % (15 * int(Save.upgrades["coins"]))
	var coin_row := _result_row(coin_label, Color(0.5, 1.0, 0.6), 22)
	res_tween.tween_property(coin_row[0], "modulate:a", 1.0, 0.15)
	res_tween.tween_method(_set_num.bind(coin_row[1], "+", float(earned)), 0.0, float(earned), 0.6)
	res_tween.tween_callback(Sfx.play.bind("coins"))
	if new_best:
		var best := _label("NEW BEST SCORE!", 20, GOLD)
		best.modulate.a = 0.0
		res_list.add_child(best)
		res_tween.tween_callback(Sfx.play.bind("new_best"))
		res_tween.tween_property(best, "modulate:a", 1.0, 0.25)
	var bank := _label("Coins in bank: %d" % Save.coins, 18, DIM)
	bank.modulate.a = 0.0
	res_list.add_child(bank)
	res_tween.tween_property(bank, "modulate:a", 1.0, 0.2)
	res_tween.tween_callback(func(): res_buttons.visible = true)


func _set_num(v: float, lbl: Label, prefix := "", target := 0.0) -> void:
	var txt := prefix + str(int(round(v)))
	if txt != lbl.text and v > 0.0:
		# Tick sound that rises in pitch as the number counts up.
		var frac := clampf(v / maxf(target, 1.0), 0.0, 1.0)
		Sfx.play("tally_tick", 0.0, 1.0 + frac * 0.6)
	lbl.text = txt


# ---------------------------------------------------------------- shop actions

func _buy_upgrade(id: String) -> void:
	if Save.buy_upgrade(id):
		Sfx.play("coins")
		_refresh_upgrades()


func _skin_action(id: String) -> void:
	if Save.owned_skins.has(id):
		Save.equip_skin(id)
	elif Save.buy_skin(id):
		Sfx.play("coins")
	_refresh_skins()


func _toggle_sound() -> void:
	Save.sound_on = not Save.sound_on
	Sfx.enabled = Save.sound_on
	Save.save_game()
	_refresh_menu()
	Sfx.play("click")


func _toggle_music() -> void:
	Save.music_on = not Save.music_on
	Music.set_enabled(Save.music_on)
	Save.save_game()
	_refresh_menu()


func _on_reset_pressed() -> void:
	if not reset_armed:
		reset_armed = true
		reset_button.text = "TAP AGAIN TO CONFIRM"
		return
	reset_armed = false
	Save.reset_progress()
	_refresh_menu()


# ---------------------------------------------------------------- screens

func _build_menu() -> void:
	var vb := _new_screen("menu")
	vb.add_child(_label("SQUAD", 50, Color(0.4, 0.75, 1.0)))
	var t2 := _label("SURGE", 50, GOLD)
	vb.add_child(t2)
	vb.add_child(_spacer(8))
	menu_skin_preview = ColorRect.new()
	menu_skin_preview.custom_minimum_size = Vector2(60, 8)
	menu_skin_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(menu_skin_preview)
	vb.add_child(_spacer(6))
	menu_level = _label("", 26)
	vb.add_child(menu_level)
	menu_coins = _label("", 24, GOLD)
	vb.add_child(menu_coins)
	menu_best = _label("", 17, DIM)
	vb.add_child(menu_best)
	vb.add_child(_spacer(10))
	vb.add_child(_button("PLAY", _start, 30, 280, 66))
	vb.add_child(_button("UPGRADES", func(): show_screen("upgrades")))
	vb.add_child(_button("SKINS", func(): show_screen("skins")))
	vb.add_child(_spacer(10))
	var help := _label("Drag, or use Left/Right (A/D), to move.\nYour squad fires automatically.\nShoot bonus crates to unlock power-ups.\nSurvive the waves and defeat the boss!", 15, DIM)
	help.custom_minimum_size = Vector2(400, 0)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(help)
	vb.add_child(_spacer(6))
	var toggles := HBoxContainer.new()
	toggles.alignment = BoxContainer.ALIGNMENT_CENTER
	toggles.add_theme_constant_override("separation", 10)
	sound_button = _button("", _toggle_sound, 16, 150, 40)
	music_button = _button("", _toggle_music, 16, 150, 40)
	toggles.add_child(sound_button)
	toggles.add_child(music_button)
	vb.add_child(toggles)
	reset_button = _button("Reset progress", _on_reset_pressed, 14, 200, 36)
	reset_button.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	vb.add_child(reset_button)


func _refresh_menu() -> void:
	reset_armed = false
	if reset_button:
		reset_button.text = "Reset progress"
	menu_level.text = "LEVEL %d" % Save.level
	sound_button.text = "SOUND: ON" if Save.sound_on else "SOUND: OFF"
	music_button.text = "MUSIC: ON" if Save.music_on else "MUSIC: OFF"
	menu_coins.text = "Coins: %d" % Save.coins
	menu_best.text = "Best score: %d" % Save.best_score
	menu_skin_preview.color = Save.SKINS[Save.skin]["body"]


func _build_upgrades() -> void:
	var vb := _new_screen("upgrades")
	vb.add_child(_label("UPGRADES", 44, GOLD))
	up_coins = _label("", 22, GOLD)
	vb.add_child(up_coins)
	up_list = VBoxContainer.new()
	up_list.add_theme_constant_override("separation", 10)
	vb.add_child(up_list)
	vb.add_child(_spacer(6))
	vb.add_child(_button("BACK", func(): show_screen("menu")))


func _refresh_upgrades() -> void:
	up_coins.text = "Coins: %d" % Save.coins
	for c in up_list.get_children():
		c.queue_free()
	for id in Save.UPGRADE_ORDER:
		var info = Save.UPGRADE_INFO[id]
		var lvl: int = Save.upgrades[id]
		var mx: int = info["max"]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(440, 0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		panel.add_child(hb)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		hb.add_child(col)
		col.add_child(_left(_label("%s   Lv %d/%d" % [info["name"], lvl, mx], 21)))
		col.add_child(_left(_label(info["desc"], 15, DIM)))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = mx
		bar.value = lvl
		bar.custom_minimum_size = Vector2(0, 8)
		col.add_child(bar)
		var btn: Button
		if lvl >= mx:
			btn = _button("MAX", func(): pass, 18, 120, 50)
			btn.disabled = true
		else:
			var cost := Save.upgrade_cost(id)
			btn = _button("BUY\n%d" % cost, _buy_upgrade.bind(id), 17, 120, 56)
			btn.disabled = Save.coins < cost
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(btn)
		up_list.add_child(panel)


func _build_skins() -> void:
	var vb := _new_screen("skins")
	vb.add_child(_label("SKINS", 44, GOLD))
	skin_coins = _label("", 22, GOLD)
	vb.add_child(skin_coins)
	skin_list = VBoxContainer.new()
	skin_list.add_theme_constant_override("separation", 8)
	vb.add_child(skin_list)
	vb.add_child(_spacer(6))
	vb.add_child(_button("BACK", func(): show_screen("menu")))


func _refresh_skins() -> void:
	skin_coins.text = "Coins: %d" % Save.coins
	for c in skin_list.get_children():
		c.queue_free()
	for id in Save.SKIN_ORDER:
		var s = Save.SKINS[id]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(440, 0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		panel.add_child(hb)
		# Swatch: body + accent + bullet colors
		var sw := HBoxContainer.new()
		sw.add_theme_constant_override("separation", 3)
		for key in ["body", "accent", "bullet"]:
			var r := ColorRect.new()
			r.color = s[key]
			r.custom_minimum_size = Vector2(16 if key != "body" else 30, 36)
			r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sw.add_child(r)
		hb.add_child(sw)
		var name_lbl := _left(_label(s["name"], 22))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_lbl)
		var btn: Button
		if Save.skin == id:
			btn = _button("EQUIPPED", func(): pass, 16, 130, 46)
			btn.disabled = true
		elif Save.owned_skins.has(id):
			btn = _button("EQUIP", _skin_action.bind(id), 16, 130, 46)
		else:
			var price: int = s["price"]
			btn = _button("BUY %d" % price, _skin_action.bind(id), 16, 130, 46)
			btn.disabled = Save.coins < price
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(btn)
		skin_list.add_child(panel)


func _build_hud() -> void:
	var root := Control.new()
	ui.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_main
	screens["hud"] = root

	hud_level = _left(_label("LEVEL 1", 20))
	hud_level.position = Vector2(16, 12)
	root.add_child(hud_level)

	hud_score = _label("0", 30, GOLD)
	hud_score.position = Vector2(0, 6)
	hud_score.size = Vector2(480, 40)
	root.add_child(hud_score)

	var pause := _button("II", _toggle_pause, 20, 52, 44)
	pause.position = Vector2(418, 8)
	root.add_child(pause)

	hud_progress = ProgressBar.new()
	hud_progress.show_percentage = false
	hud_progress.max_value = 1.0
	hud_progress.step = 0.0
	hud_progress.position = Vector2(16, 58)
	hud_progress.size = Vector2(448, 12)
	hud_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_progress)

	hud_squad = _left(_label("", 20))
	hud_squad.position = Vector2(16, 796)
	root.add_child(hud_squad)

	hud_stats = _left(_label("", 14, DIM))
	hud_stats.position = Vector2(16, 824)
	root.add_child(hud_stats)


func _update_hud() -> void:
	hud_level.text = "LEVEL %d" % game.level
	hud_score.text = str(game.score)
	hud_progress.value = game.progress
	hud_progress.visible = not game.boss_spawned
	hud_squad.text = "SQUAD %d   SHIELD %d" % [game.units, game.shield]
	var rate: float = 1.0 / game.fire_interval
	hud_stats.text = "DMG x%.2f   RATE %.1f/s   SPREAD %d   PIERCE %d" % [game.damage, rate, game.spread, game.pierce]


func _build_pause() -> void:
	var vb := _new_screen("pause")
	vb.add_child(_label("PAUSED", 48))
	vb.add_child(_spacer(10))
	vb.add_child(_button("RESUME", _toggle_pause))
	vb.add_child(_button("QUIT TO MENU", _to_menu))
	vb.add_child(_label("Quitting forfeits this run's points.", 14, DIM))


func _build_results() -> void:
	var vb := _new_screen("results")
	res_title = _label("", 44, GOLD)
	vb.add_child(res_title)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 0)
	res_list = VBoxContainer.new()
	res_list.add_theme_constant_override("separation", 8)
	panel.add_child(res_list)
	vb.add_child(panel)
	vb.add_child(_spacer(6))
	res_buttons = HBoxContainer.new()
	res_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	res_buttons.add_theme_constant_override("separation", 12)
	res_next = _button("NEXT LEVEL", _start, 22, 200)
	res_buttons.add_child(res_next)
	res_buttons.add_child(_button("MENU", _to_menu, 22, 200))
	vb.add_child(res_buttons)


func _result_row(text: String, col: Color, size: int) -> Array:
	var hb := HBoxContainer.new()
	var l := _left(_label(text, size, col))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := _label("0", size, col)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(l)
	hb.add_child(v)
	hb.modulate.a = 0.0
	res_list.add_child(hb)
	return [hb, v]


# ---------------------------------------------------------------- UI helpers

func _new_screen(id: String, dim := true) -> VBoxContainer:
	var root := Control.new()
	ui.add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme_main
	screens[id] = root
	if dim:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.03, 0.07, 0.75)
		root.add_child(bg)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	return vb


func _label(text: String, size := 20, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4 if size >= 24 else 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _left(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _button(text: String, cb: Callable, size := 24, min_w := 260, min_h := 56) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sfx.play("click"))
	b.pressed.connect(cb)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _make_theme() -> Theme:
	var th := Theme.new()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.45, 0.95)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(8)
	normal.border_width_bottom = 4
	normal.border_color = Color(0.1, 0.25, 0.6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.3, 0.55, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.15, 0.35, 0.8)
	pressed.border_width_bottom = 1
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.25, 0.27, 0.33)
	disabled.border_color = Color(0.15, 0.16, 0.2)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(0.9, 0.9, 1.0))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.45))

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.12, 0.19, 0.95)
	panel.set_corner_radius_all(12)
	panel.set_content_margin_all(11)
	panel.border_color = Color(0.25, 0.3, 0.45)
	panel.set_border_width_all(2)
	th.set_stylebox("panel", "PanelContainer", panel)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.5)
	bar_bg.set_corner_radius_all(6)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = GOLD
	bar_fill.set_corner_radius_all(6)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fill)
	return th
