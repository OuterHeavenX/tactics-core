# ============================================================================
# Game flow: title -> briefing -> battle -> results, plus camera and input.
#
# The rules live in Battle.gd and never touch a node; this script asks the
# rules for an outcome and then animates whatever came back on the event queue.
# ============================================================================
extends Node2D

const SAVE_PATH := "user://tactics_core_save.json"

@onready var world: Node2D = $World
@onready var board: BoardView = $World/Board
@onready var hud: HUD = $HUD
@onready var audio: AudioSynth = $Audio

var battle: Battle
var progress: Dictionary = {}
var mode := "title"                     # title | deploy | idle | move | target | enemy | busy | over
var deploy_sel: Unit = null
var turn_snap: Dictionary = {}
var pending: Dictionary = {}            # {"ability": ...} or {"item": id}
var inspecting: Unit = null
var busy := false

var cam_offset := Vector2.ZERO
var cam_target = null                   # Vector2 or null
var zoom := 1.0
var zoom_target := 1.0
var fits_board := true
var sky: TextureRect

# Developer harness flags, read from the command line after a bare `--`:
#   --autoplay          the AI plays the player side too (soak test / demo)
#   --chapter=N         start on chapter N (1-4)
#   --shots=DIR         save a PNG every --shot-every frames
#   --shot-every=N      frames between screenshots (default 120)
#   --quit-frames=N     exit after N frames
var autoplay := false
var shot_dir := ""
var shot_every := 120
var quit_frames := 0
var _frames := 0
var _shot_index := 0

var _dragging := false
var _drag_moved := false
var _last_drag := Vector2.ZERO
var _pinch := 0.0
var _touches: Dictionary = {}

func _ready() -> void:
	_build_sky()
	hud.action_chosen.connect(_on_action)
	hud.tool_pressed.connect(_on_tool)
	hud.sheet_action.connect(_on_sheet)
	board.walk_finished.connect(func(_u): pass)
	_read_dev_flags()
	progress = _load_progress()
	if autoplay:
		progress = _new_progress()
		var start_chapter := 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--chapter="):
				start_chapter = clampi(int(a.split("=")[1]) - 1, 0, GameData.CAMPAIGN.size() - 1)
		progress["chapter"] = start_chapter
		for p in progress["party"]:
			p["level"] = 1 + start_chapter * 2
		hud.hide_sheet()
		start_battle(GameData.CAMPAIGN[start_chapter])
	else:
		show_title()

func _read_dev_flags() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--shots="):
			shot_dir = a.split("=")[1]
		elif a.begins_with("--shot-every="):
			shot_every = maxi(1, int(a.split("=")[1]))
		elif a.begins_with("--quit-frames="):
			quit_frames = int(a.split("=")[1])

# ------------------------------------------------------------------ saving --
func _load_progress() -> Dictionary:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("party"):
				return parsed
	return {}

func _save_progress() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(progress))

func _new_progress(difficulty: String = "normal") -> Dictionary:
	var party: Array = []
	for p in GameData.PARTY:
		party.append({"name": p["name"], "job": p["job"], "level": 1, "xp": 0, "jp": 0, "learned": []})
	return {"chapter": 0, "party": party, "wins": 0, "difficulty": difficulty}

func difficulty() -> Dictionary:
	return GameData.DIFFICULTY.get(String(progress.get("difficulty", "normal")), GameData.DIFFICULTY["normal"])

# ------------------------------------------------------------------ screens --
func show_title() -> void:
	mode = "title"
	var body := "Isometric 2.5D tactics. Charge-time turns, real terrain height,\nfacing-based damage and a four-chapter campaign.\n\n"
	for p in GameData.PARTY:
		var j: Dictionary = GameData.job(p["job"])
		body += "[color=%s][b]%s[/b][/color] — [color=#e8c66a]%s[/color]\n[color=#98a0c4]%s[/color]\n\n" % [
			j["color"], p["name"], p["job"], j["blurb"]]
	var buttons: Array = []
	var has := progress.has("chapter") and int(progress.get("chapter", 0)) > 0
	if has:
		buttons.append({"id": "continue", "label": "Continue — Chapter %d (%s)" % [int(progress["chapter"]) + 1, difficulty()["name"]], "accent": "primary"})
	for id in ["story", "normal", "hard"]:
		var d: Dictionary = GameData.DIFFICULTY[id]
		buttons.append({"id": "new_" + id, "label": "New: %s" % d["name"], "accent": "primary" if (id == "normal" and not has) else ""})
	buttons.append({"id": "help", "label": "How to Play"})
	body += "\n[color=#98a0c4]"
	for id in ["story", "normal", "hard"]:
		body += "[b]%s[/b] — %s   " % [GameData.DIFFICULTY[id]["name"], GameData.DIFFICULTY[id]["blurb"]]
	body += "[/color]"
	hud.show_sheet("TACTICS CORE", body, buttons)

func show_help(return_to: String) -> void:
	hud.set_meta("help_return", return_to)
	var body := """
[b]Turn order[/b] is charge time. Each unit builds CT from its Speed; at 100 it acts.
Doing less leaves you more CT, so waiting gets you back sooner than moving [i]and[/i] attacking.

[b]Height is real.[/b] Attacking from above adds accuracy and damage. Your Jump stat caps how
big a step you can climb, so terraces and cliffs are walls until you find the ramp.

[b]Facing matters.[/b] The wedge under each unit is where it is looking. Strike from the side
for +25% damage, from behind for [b]+50%[/b] and a much better hit chance.

[b]Move and act[/b] — one of each per turn, in either order. Move first and you can undo it
right up until you act.

[b]Terrain[/b] — forest grants evasion, rock grants defence, lava burns anything that stops
on it, and water is impassable.

[b]Controls[/b] — click or tap a tile to move or target. Q/E rotate the camera, +/- zoom,
Space waits, U undoes a move, Esc cancels, F recentres. Drag to pan, pinch to zoom.
"""
	hud.show_sheet("How to Play", body, [{"id": "help_back", "label": "Back", "accent": "primary"}])

func show_briefing() -> void:
	mode = "over"
	var idx: int = mini(int(progress.get("chapter", 0)), GameData.CAMPAIGN.size() - 1)
	var chapter: Dictionary = GameData.CAMPAIGN[idx]
	var body := "[color=#98a0c4]%s[/color]\n\n" % chapter["brief"]
	for p in progress["party"]:
		var j: Dictionary = GameData.job(p["job"])
		body += "[color=%s]%s[/color] — [color=#e8c66a]%s Lv %d[/color]\n" % [j["color"], p["name"], p["job"], int(p["level"])]
	body += "\n[color=#6fd08c]Tip: %s[/color]" % chapter["tip"]
	hud.show_sheet(String(chapter["title"]), body, [
		{"id": "begin", "label": "Begin Battle", "accent": "primary"},
		{"id": "learn", "label": "Learn Abilities"},
		{"id": "help", "label": "How to Play"},
		{"id": "title", "label": "Main Menu"}])

## Spend JP between chapters. Works on the saved party.
func show_learn() -> void:
	mode = "over"
	var body := "[color=#98a0c4]JP is earned alongside XP. Anything you don't buy now is still there next time.[/color]\n\n"
	var buttons: Array = []
	var party: Array = progress["party"]
	for i in party.size():
		var p: Dictionary = party[i]
		var job: Dictionary = GameData.job(p["job"])
		var known: Array = (job.get("starting", job["abilities"]) as Array).duplicate()
		for l in p.get("learned", []):
			known.append(l)
		var names: Array[String] = []
		for id in known:
			names.append(String(GameData.ability(id)["name"]))
		body += "[color=%s][b]%s[/b][/color] [color=#e8c66a]%s Lv %d[/color] · [color=#5b8def]%d JP[/color]\n[color=#98a0c4]Knows: %s[/color]\n" % [
			job["color"], p["name"], p["job"], int(p["level"]), int(p.get("jp", 0)), ", ".join(names)]
		for id in job["abilities"]:
			if known.has(id):
				continue
			var a: Dictionary = GameData.ability(id)
			if not a.has("jp"):
				continue
			var can: bool = int(p.get("jp", 0)) >= int(a["jp"])
			body += "   %s — %d JP%s: [color=#98a0c4]%s[/color]\n" % [a["name"], int(a["jp"]),
				" [color=#6fd08c](affordable)[/color]" if can else "", a["desc"]]
			if can:
				buttons.append({"id": "buy:%d:%s" % [i, id], "label": "%s: learn %s" % [p["name"], a["name"]]})
		body += "\n"
	buttons.append({"id": "next", "label": "Next Chapter", "accent": "primary"})
	buttons.append({"id": "title", "label": "Main Menu"})
	hud.show_sheet("Learn Abilities", body, buttons)

func show_pause() -> void:
	hud.show_sheet("Paused", "", [
		{"id": "resume", "label": "Resume", "accent": "primary"},
		{"id": "sound", "label": "Sound: %s" % ("on" if audio.sound_on else "off")},
		{"id": "music", "label": "Music: %s" % ("on" if audio.music_on else "off")},
		{"id": "help", "label": "How to Play"},
		{"id": "restart", "label": "Restart Battle", "accent": "danger"},
		{"id": "title", "label": "Main Menu", "accent": "danger"}],
		battle.chapter["title"] if battle != null else "")

func _on_sheet(id: String) -> void:
	audio.play("select")
	if id.begins_with("buy:"):
		var parts := id.split(":")
		var p: Dictionary = progress["party"][int(parts[1])]
		var a: Dictionary = GameData.ability(parts[2])
		if int(p.get("jp", 0)) >= int(a["jp"]):
			p["jp"] = int(p["jp"]) - int(a["jp"])
			var learned: Array = p.get("learned", [])
			learned.append(parts[2])
			p["learned"] = learned
			_save_progress()
			audio.play("levelup")
		show_learn()
		return
	match id:
		"help":
			show_help(mode)
		"help_back":
			if battle != null and battle.over == "":
				hud.hide_sheet()
			elif progress.has("party"):
				show_briefing()
			else:
				show_title()
		"new_story", "new_normal", "new_hard":
			progress = _new_progress(id.trim_prefix("new_"))
			_save_progress()
			show_briefing()
		"learn":
			show_learn()
		"start_battle":
			begin_battle()
		"continue":
			show_briefing()
		"begin":
			hud.hide_sheet()
			start_battle(GameData.CAMPAIGN[mini(int(progress["chapter"]), GameData.CAMPAIGN.size() - 1)])
		"title":
			show_title()
		"resume":
			hud.hide_sheet()
		"sound":
			audio.set_sound(not audio.sound_on)
			show_pause()
		"music":
			audio.set_music(not audio.music_on)
			show_pause()
		"restart":
			hud.hide_sheet()
			start_battle(battle.chapter)
		"next":
			show_briefing()
		"retry":
			hud.hide_sheet()
			start_battle(battle.chapter)

# ------------------------------------------------------------------ battle --
func start_battle(chapter: Dictionary) -> void:
	# A battle can start from the middle of targeting, so clear transient state.
	mode = "idle"
	pending = {}
	busy = false
	inspecting = null
	battle = Battle.new(chapter, progress["party"], {"levelOffset": int(difficulty()["levelOffset"])})
	board.setup(battle)
	turn_snap = {}
	deploy_sel = null
	_apply_sky(battle.grid.weather)
	hud.clear_log()
	hud.set_inspect(null)
	hud.set_preview("")
	hud.set_hint("")
	var objective := "Defeat all enemies"
	match String(chapter.get("objective", "rout")):
		"boss": objective = "Slay the boss"
		"protect": objective = "Keep %s alive" % chapter["npc"][0]
	hud.set_chapter(String(chapter["title"]).replace("Chapter ", "Ch."), objective)
	hud.log_line("[color=#e8c66a]%s[/color]" % chapter["title"])
	fit_camera()
	if chapter.get("boss", false):
		audio.play("boss")
	enter_deploy()

## Before turn one the player may shuffle the party around the deploy zone.
func enter_deploy() -> void:
	mode = "deploy"
	deploy_sel = null
	clear_overlays()
	for t in battle.deploy_zone():
		board.overlay_move[t] = true
	hud.set_hint("Deployment: tap a unit, then a highlighted tile. Start when ready.")
	refresh()
	if autoplay:
		begin_battle()

func deploy_click(tile: Vector2i, clicked: Unit) -> void:
	if deploy_sel != null:
		if battle.place_unit(deploy_sel, tile):
			audio.play("move")
			deploy_sel = null
		elif clicked != null and clicked.team == "P" and not clicked.npc:
			deploy_sel = clicked
		else:
			audio.play("cancel")
			deploy_sel = null
	elif clicked != null and clicked.team == "P" and not clicked.npc:
		deploy_sel = clicked
		audio.play("select")
	hud.set_inspect(clicked)
	hud.set_hint("Moving %s: tap a highlighted tile (or another unit to swap)." % deploy_sel.unit_name if deploy_sel != null
		else "Deployment: tap a unit, then a highlighted tile. Start when ready.")
	refresh()

func begin_battle() -> void:
	if mode != "deploy":
		return
	deploy_sel = null
	clear_overlays()
	mode = "idle"
	advance()

## Story mode: put the whole turn back the way it was.
func rewind_turn() -> void:
	if busy or turn_snap.is_empty() or battle == null or mode == "enemy":
		return
	battle.restore(turn_snap)
	for u in battle.units:
		board.snap(u)
	mode = "idle"
	pending = {}
	clear_overlays()
	audio.play("cancel")
	hud.log_line("[color=#e8c66a]Turn rewound.[/color]")
	battle.drain()
	sync_threat()
	refresh()

## Tiles a charging enemy spell will hit are shown in orange.
func sync_threat() -> void:
	board.overlay_threat.clear()
	board.casters.clear()
	for p in battle.pending:
		var cid := int(p["casterId"])
		if cid >= battle.units.size():
			continue
		var caster: Unit = battle.units[cid]
		board.casters[caster.id] = true
		for t in battle.grid.footprint(caster, GameData.ability(String(p["abilityId"])), Vector2i(int(p["tx"]), int(p["ty"]))):
			board.overlay_threat[t] = true

func advance() -> void:
	if battle == null:
		return
	if battle.check_end():
		await play_events(battle.drain())
		finish()
		return
	var u := battle.begin_turn()
	var evts := battle.drain()
	await play_events(evts)
	if u == null or battle.over != "":
		finish()
		return
	board.cursor = u.pos
	inspecting = u
	if not fits_board:
		focus_on(u.pos)
	sync_threat()
	if u.team == "P" and not u.npc:
		mode = "idle"
		turn_snap = battle.snapshot() if bool(difficulty()["undoTurn"]) else {}
		audio.play("turn")
		hud.log_line("[color=#9dc0ff]%s[/color]'s turn." % u.unit_name)
		refresh()
	else:
		mode = "enemy"
		refresh()
		await get_tree().create_timer(0.3).timeout
		await enemy_turn(u)

func enemy_turn(u: Unit) -> void:
	var plan := EnemyAI.plan_turn(battle, u)
	if plan["move"] != null:
		if not fits_board:
			focus_on(plan["move"])
		battle.move_unit(u, plan["move"])
		await play_events(battle.drain())
		await get_tree().create_timer(0.2).timeout
	var ability: Dictionary = plan["ability"]
	if not ability.is_empty() and battle.valid_target(u, ability, plan["target"]):
		battle.use_ability(u, ability, plan["target"])
		await play_events(battle.drain())
	else:
		u.facing = battle.face_nearest_foe(u)
	await get_tree().create_timer(0.35).timeout
	battle.end_turn(u)
	await play_events(battle.drain())
	advance()

func end_turn() -> void:
	if busy or battle == null or battle.active == null or mode == "enemy":
		return
	battle.end_turn(battle.active)
	clear_overlays()
	await play_events(battle.drain())
	advance()

func finish() -> void:
	mode = "over"
	clear_overlays()
	var win := battle.over == "victory"
	audio.play("victory" if win else "defeat")
	var chapter := battle.chapter
	var levelups: Array[String] = []
	if win:
		var fighters := 0
		for u in battle.living("P"):
			if not u.npc:
				fighters += 1
		var share: int = int(chapter["xp"]) / maxi(1, fighters)
		var party: Array = []
		for u in battle.units:
			if u.team != "P" or u.npc:
				continue
			var before := u.level
			u.gain_xp(share if u.alive() else int(share * 0.4))
			if u.level > before:
				levelups.append("%s -> Lv %d" % [u.unit_name, u.level])
			party.append({"name": u.unit_name, "job": u.job, "level": u.level, "xp": u.xp, "jp": u.jp, "learned": u.learned.duplicate()})
		progress["party"] = party
		progress["chapter"] = mini(GameData.CAMPAIGN.size(), GameData.CAMPAIGN.find(chapter) + 1)
		progress["wins"] = int(progress.get("wins", 0)) + 1
		_save_progress()

	var done: bool = win and int(progress.get("chapter", 0)) >= GameData.CAMPAIGN.size()
	var body := ""
	if done:
		body = "[color=#98a0c4]The Necrohol is silent. Your company walks out of it alive.[/color]\n\n"
	elif win:
		body = "[color=#98a0c4]The field is yours. %d XP shared across the company.[/color]\n\n" % int(chapter["xp"])
	else:
		body = "[color=#98a0c4]Your company is broken. Regroup and try the battle again.[/color]\n\n"
	if not levelups.is_empty():
		body += "[color=#6fd08c]%s[/color]\n\n" % " · ".join(levelups)
	for u in battle.units:
		if u.team != "P" or u.npc:
			continue
		var state := "%d/%d HP" % [u.hp, u.max_hp] if u.alive() else "[color=#e05b5b]fallen[/color]"
		body += "[color=%s]%s[/color] — %s Lv %d · %s · %d/%d XP\n" % [
			u.color().to_html(false), u.unit_name, u.job, u.level, state, u.xp, u.xp_to_next()]

	var buttons: Array = []
	if done:
		buttons.append({"id": "title", "label": "Main Menu", "accent": "primary"})
	elif win:
		buttons.append({"id": "learn", "label": "Learn Abilities", "accent": "primary"})
		buttons.append({"id": "next", "label": "Next Chapter"})
		buttons.append({"id": "title", "label": "Main Menu"})
	else:
		buttons.append({"id": "retry", "label": "Retry Battle", "accent": "primary"})
		buttons.append({"id": "title", "label": "Main Menu"})
	hud.show_sheet("Campaign Clear" if done else ("Victory" if win else "Defeat"), body, buttons)
	if autoplay:
		print("[autoplay] %s — %s after %d turns (%d allies, %d enemies left)" % [
			chapter["id"], battle.over, battle.turn, battle.living("P").size(), battle.living("E").size()])
		if done or not win:
			get_tree().quit()
		else:
			progress["party"] = progress["party"]
			hud.hide_sheet()
			start_battle(GameData.CAMPAIGN[mini(int(progress["chapter"]), GameData.CAMPAIGN.size() - 1)])

# ----------------------------------------------------- event visualisation --
func play_events(evts: Array) -> void:
	busy = true
	for e in evts:
		var t := String(e["type"])
		if t == "move" or t == "knockback":
			var u: Unit = e["unit"]
			var path: Array = e["path"] if e.has("path") else [e["to"]]
			var finished := [false]
			board.walk(u, e["from"], path, func(): finished[0] = true)
			if t == "move":
				audio.play("move")
			while not finished[0]:
				await get_tree().process_frame
			continue
		var delay := _visualise(e)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
	busy = false
	refresh()

func _visualise(e: Dictionary) -> float:
	var t := String(e["type"])
	match t:
		"damage":
			var u: Unit = e["unit"]
			var crit: bool = e.get("crit", false)
			var back: bool = String(e.get("side", "front")) == "back"
			board.float_text(u.pos, ("*" if crit else "") + str(e["amount"]),
				Color("#ffd86a") if crit else (Color("#ff9d9d") if u.team == "P" else Color.WHITE),
				26 if crit else 20)
			if back:
				# Offset so it does not sit on top of the damage number.
				board.float_text(u.pos, "BACK!", Color("#ffb366"), 12)
				board._floaters[board._floaters.size() - 1]["dx"] = 26.0
				board._floaters[board._floaters.size() - 1]["h"] -= 0.45
			board.flash_unit(u, Color.WHITE)
			board.burst(u.pos, Color("#ffd86a") if crit else Color("#ff8a8a"), 22 if crit else 12, 1.7 if crit else 1.0)
			audio.play("crit" if crit else "hit")
			hud.log_line("[color=%s]%s[/color] takes [b]%d[/b]%s" % [
				"#9dc0ff" if u.team == "P" else "#ffa8a8", u.unit_name, int(e["amount"]),
				" (CRIT)" if crit else (" (back)" if back else "")])
			return 0.11
		"heal":
			var u: Unit = e["unit"]
			if int(e["amount"]) > 0:
				board.float_text(u.pos, "+%d" % int(e["amount"]), Color("#8ce8a8"), 20)
				board.flash_unit(u, Color("#6fd08c"))
				board.burst(u.pos, Color("#8ce8a8"), 12, 0.8)
				audio.play("heal")
			return 0.09
		"miss":
			var u: Unit = e["unit"]
			board.float_text(u.pos, "MISS", Color("#cfd4e0"), 16)
			audio.play("miss")
			hud.log_line("[color=#98a0c4]%s misses %s.[/color]" % [e["by"].unit_name, u.unit_name])
			return 0.14
		"cast":
			var ab: Dictionary = e["ability"]
			var kind := String(ab.get("type", "phys"))
			var magical := kind in ["mag", "heal", "buff", "revive", "drain"]
			var target: Vector2i = e["target"]
			var dist := Iso.manhattan(e["unit"].pos, target)
			if magical:
				board.burst(target, Color("#8ce8a8") if kind == "heal" else Color("#c9a6ff"), 20, 1.3)
				audio.play("magic")
			# A melee swing lunges; anything thrown or shot arcs across the board.
			if dist == 1 and not magical:
				board.lunge(e["unit"], target)
			elif dist > 1 and kind != "buff" and kind != "revive" and not ab.has("shape"):
				board.projectile(e["unit"], target, Color("#c9a6ff") if magical else Color("#ffe9a8"))
			hud.log_line("[color=%s]%s[/color] uses [b]%s[/b]." % [
				"#9dc0ff" if e["unit"].team == "P" else "#ffa8a8", e["unit"].unit_name, ab["name"]])
			if dist > 1 and not ab.has("shape"):
				return 0.33
			return 0.2 if int(ab.get("mp", 0)) > 0 else 0.14
		"charge":
			for tile in e["tiles"]:
				board.burst(tile, Color("#ff9d5c"), 4, 0.6)
			hud.log_line("[color=%s]%s[/color] begins casting [b]%s[/b]..." % [
				"#9dc0ff" if e["unit"].team == "P" else "#ffa8a8", e["unit"].unit_name, e["ability"]["name"]])
			sync_threat()
			return 0.22
		"land":
			for tile in e["tiles"]:
				board.burst(tile, Color("#ffb066"), 14, 1.4)
			audio.play("magic")
			hud.log_line("[color=#e8c66a][b]%s[/b] lands![/color]" % e["ability"]["name"])
			sync_threat()
			return 0.2
		"fizzle":
			hud.log_line("[color=#e8c66a]%s fizzles - its caster is gone.[/color]" % GameData.ability(String(e["spell"]["abilityId"]))["name"])
			sync_threat()
			return 0.12
		"ko":
			var u: Unit = e["unit"]
			board.burst(u.pos, Color.WHITE, 26, 2.0)
			audio.play("ko")
			hud.log_line("[color=#e8c66a]%s is defeated![/color]" % u.unit_name)
			return 0.26
		"revive":
			board.float_text(e["unit"].pos, "REVIVED", Color("#ffd86a"), 16)
			board.burst(e["unit"].pos, Color("#ffd86a"), 26, 1.6)
			audio.play("levelup")
			hud.log_line("[color=#6fd08c]%s rises again![/color]" % e["unit"].unit_name)
			return 0.32
		"status":
			var sd: Dictionary = GameData.STATUS[e["status"]]
			board.float_text(e["unit"].pos, String(sd["name"]), Color(String(sd["color"])), 13)
			return 0.11
		"counter":
			board.float_text(e["unit"].pos, "COUNTER", Color("#ffd86a"), 14)
			return 0.12
		"summon":
			board.burst(e["unit"].pos, Color("#b48ef0"), 24, 1.5)
			hud.log_line("[color=#e8c66a]%s raises %s![/color]" % [e["by"].unit_name, e["unit"].unit_name])
			return 0.26
		"levelup":
			board.float_text(e["unit"].pos, "LEVEL UP!", Color("#ffd86a"), 18)
			audio.play("levelup")
			hud.log_line("[color=#6fd08c]%s reaches level %d![/color]" % [e["unit"].unit_name, e["unit"].level])
			return 0.3
		"turnSkipped":
			if String(e["reason"]) == "stun":
				board.float_text(e["unit"].pos, "STUNNED", Color("#e8c66a"), 15)
				return 0.3
			return 0.0
		"focus":
			board.float_text(e["unit"].pos, "+4 MP", Color("#7aa5ff"), 13)
			return 0.0
		"item":
			hud.log_line("[color=#9dc0ff]%s uses %s on %s.[/color]" % [
				e["unit"].unit_name, e["item"]["name"], e["target"].unit_name])
			return 0.12
	return 0.0

# ------------------------------------------------------------- interaction --
func me() -> Unit:
	if battle != null and battle.active != null and battle.active.team == "P" and not battle.active.npc:
		return battle.active
	return null

func clear_overlays() -> void:
	board.clear_overlays()
	hud.set_preview("")
	hud.set_hint("")

func enter_move() -> void:
	var u := me()
	if u == null or u.moved:
		return
	mode = "move"
	pending = {}
	clear_overlays()
	for t in battle.reachable_for(u)["tiles"]:
		board.overlay_move[t] = true
	hud.set_hint("Pick a highlighted tile to move. Esc to cancel.")
	refresh()

func enter_target(payload: Dictionary) -> void:
	var u := me()
	if u == null:
		return
	mode = "target"
	pending = payload
	clear_overlays()
	var ab: Dictionary
	if payload.has("ability"):
		ab = payload["ability"]
	else:
		var item: Dictionary = GameData.ITEMS[payload["item"]]
		ab = {"range": item["range"], "aoe": 0, "vert": 4, "target": item["target"]}
	if ab.get("selfCentered", false):
		board.overlay_act[u.pos] = true
	else:
		for t in battle.grid.tiles_in_range(u.pos.x, u.pos.y, ab):
			board.overlay_act[t] = true
	hud.set_hint("Pick a target. Esc to cancel.")
	refresh()

func cancel() -> void:
	if busy:
		return
	if mode == "move" or mode == "target":
		mode = "idle"
		pending = {}
		clear_overlays()
		audio.play("cancel")
		refresh()
	elif mode == "idle" or mode == "enemy":
		show_pause()

func hover(tile: Vector2i) -> void:
	if battle == null or tile.x < 0:
		return
	board.cursor = tile
	var occupant := battle.unit_at(tile.x, tile.y)
	if occupant == null:
		occupant = battle.ko_at(tile.x, tile.y)
	hud.set_inspect(occupant)
	var u := me()
	if u == null or busy:
		return
	if mode == "move":
		board.overlay_path.clear()
		if board.overlay_move.has(tile):
			board.overlay_path.assign(battle.grid.path_to(battle.reachable_for(u), u, tile))
	elif mode == "target":
		board.overlay_aoe.clear()
		if pending.has("ability"):
			var ab: Dictionary = pending["ability"]
			if battle.valid_target(u, ab, tile):
				for t in battle.grid.aoe_tiles(tile.x, tile.y, ab):
					board.overlay_aoe[t] = true
				_show_preview(u, ab, tile)
			else:
				hud.set_preview("")
		else:
			var item: Dictionary = GameData.ITEMS[pending["item"]]
			var target: Unit = battle.ko_at(tile.x, tile.y) if String(item["target"]) == "ko" else battle.unit_at(tile.x, tile.y)
			if target != null:
				board.overlay_aoe[tile] = true
				hud.set_preview("[b]%s[/b]\n[color=#98a0c4]on %s[/color]" % [item["name"], target.unit_name])
			else:
				hud.set_preview("")

## The numbers that make a tactics game readable: hit chance and damage.
func _show_preview(u: Unit, ab: Dictionary, tile: Vector2i) -> void:
	var hits := battle.affected(u, ab, tile)
	if hits.is_empty():
		hud.set_preview("[b]%s[/b]\n[color=#98a0c4]no target[/color]" % ab["name"] if ab.get("type", "") == "summon" else "")
		return
	var text := "[b]%s[/b]" % ab["name"]
	if int(ab.get("mp", 0)) > 0:
		text += " [color=#5b8def]%d MP[/color]" % int(ab["mp"])
	text += "\n"
	var kind := String(ab.get("type", "phys"))
	for t in hits:
		if kind == "heal":
			var amount: int = mini(t.max_hp - t.hp, roundi(u.stat("mag") * float(ab.get("power", 1.0)) * 1.6))
			text += "[color=#98a0c4]%s:[/color] [color=#6fd08c]+%d HP[/color]\n" % [t.unit_name, amount]
		elif kind == "buff":
			text += "[color=#98a0c4]%s: %s[/color]\n" % [t.unit_name, GameData.STATUS[ab["status"]["id"]]["name"]]
		elif kind == "revive":
			text += "[color=#98a0c4]%s: revive at %d HP[/color]\n" % [t.unit_name, roundi(t.max_hp * float(ab["power"]))]
		else:
			var acc := battle.hit_chance(u, t, ab)
			var dmg := battle.estimate_damage(u, t, ab)
			var side := Iso.relative_side(t.pos, t.facing, u.pos)
			text += "%s[color=#98a0c4]%s:[/color] [b]%d[/b] dmg · %d%%%s%s\n" % [
				"[color=#e05b5b]! [/color]" if t.team == u.team else "",
				t.unit_name, dmg, acc,
				" · [color=#e8c66a]%s[/color]" % side if side != "front" else "",
				" · [color=#e05b5b]KO[/color]" if dmg >= t.hp else ""]
	if ab.has("charge"):
		text += "[color=#e8c66a]~ charges first - lands on whoever is there then[/color]\n"
	hud.set_preview(text)

func click(tile: Vector2i) -> void:
	if battle == null or tile.x < 0 or busy:
		return
	var u := me()
	var clicked := battle.unit_at(tile.x, tile.y)
	if clicked == null:
		clicked = battle.ko_at(tile.x, tile.y)
	if mode == "deploy":
		deploy_click(tile, clicked)
		return
	if u == null:
		hud.set_inspect(clicked)
		return

	if mode == "move":
		if not board.overlay_move.has(tile):
			hud.set_inspect(clicked)
			return
		var from := u.pos
		battle.move_unit(u, tile)
		clear_overlays()
		mode = "busy"
		await play_events(battle.drain())
		mode = "over" if battle.over != "" else "idle"
		if battle.over != "":
			finish()
		else:
			refresh()
		return

	if mode == "target":
		var ok := false
		if pending.has("ability"):
			var ab: Dictionary = pending["ability"]
			ok = battle.use_ability(u, ab, tile)
		else:
			ok = battle.use_item(u, String(pending["item"]), tile)
		if not ok:
			audio.play("cancel")
			return
		clear_overlays()
		mode = "busy"
		await play_events(battle.drain())
		if battle.check_end():
			await play_events(battle.drain())
			finish()
			return
		mode = "idle"
		# Acting ends the turn unless there is still a move left to spend.
		if u.moved or not u.alive():
			end_turn()
		else:
			refresh()
		return

	# Idle: clicking is a shortcut for "attack that" / "walk there".
	if clicked != null and clicked != u and clicked.alive() and clicked.team == "E" and not u.acted:
		var atk := GameData.ability(String(u.abilities[0]))
		if battle.valid_target(u, atk, tile):
			enter_target({"ability": atk})
			hover(tile)
			return
	if not u.moved and clicked == null:
		for t in battle.reachable_for(u)["tiles"]:
			if t == tile:
				enter_move()
				hover(tile)
				return
	hud.set_inspect(clicked)

# ------------------------------------------------------------------- menus --
func refresh() -> void:
	if battle == null:
		return
	var u := battle.active
	hud.set_active_unit(u)
	var order: Array = []
	if u != null:
		order.append(u)
	order.append_array(battle.forecast(7))
	hud.set_turn_order(order, u)

	if mode == "deploy":
		hud.set_actions([{"label": "Deploy (%d tiles)" % battle.deploy_zone().size(), "kind": "none", "disabled": true},
			{"label": "Start Battle", "kind": "start", "accent": "primary"}])
		return
	if mode in ["enemy", "over", "busy", "title"] or u == null or u.team != "P" or u.npc:
		var label := "Enemy turn..."
		if u != null and u.npc:
			label = "%s..." % u.unit_name
		hud.set_actions([{"label": label, "kind": "none", "disabled": true}] if mode == "enemy" else [])
		return
	if mode == "move" or mode == "target":
		hud.set_actions([{"label": "Cancel", "kind": "cancel", "accent": "danger"}])
		return

	var entries: Array = [{"label": "Move", "kind": "move", "disabled": u.moved}]
	if u.moved and not u.acted:
		entries.append({"label": "Undo", "kind": "undo"})
	for aid in u.abilities:
		var a: Dictionary = GameData.ability(aid)
		var cd: int = int(u.cooldowns.get(aid, 0))
		var label := String(a["name"])
		if int(a.get("mp", 0)) > 0:
			label += " (%d)" % int(a["mp"])
		if a.has("charge"):
			label += " ~"
		if cd > 0:
			label += " [%dt]" % cd
		entries.append({"label": label, "kind": "ability", "payload": aid,
			"tip": String(a["desc"]), "disabled": u.acted or u.mp < int(a.get("mp", 0)) or cd > 0})
	var any_items := false
	for k in battle.items:
		if int(battle.items[k]) > 0:
			any_items = true
	if any_items and not u.acted:
		entries.append({"label": "Item", "kind": "items"})
	if not turn_snap.is_empty() and (u.moved or u.acted):
		entries.append({"label": "Rewind", "kind": "rewind"})
	entries.append({"label": "Wait", "kind": "wait", "accent": "primary"})
	hud.set_actions(entries)

func item_menu() -> void:
	var entries: Array = []
	for k in battle.items:
		var it: Dictionary = GameData.ITEMS[k]
		entries.append({"label": "%s x%d" % [it["name"], int(battle.items[k])], "kind": "item",
			"payload": k, "tip": String(it["desc"]), "disabled": int(battle.items[k]) <= 0})
	entries.append({"label": "Back", "kind": "back", "accent": "danger"})
	hud.set_actions(entries)

func _on_action(kind: String, payload: Variant) -> void:
	audio.play("select")
	match kind:
		"move": enter_move()
		"undo":
			var u := me()
			if u != null and battle.undo_move(u):
				board.snap(u)
				battle.drain()
				refresh()
		"ability": enter_target({"ability": GameData.ability(String(payload))})
		"items": item_menu()
		"item": enter_target({"item": String(payload)})
		"wait": end_turn()
		"start": begin_battle()
		"rewind": rewind_turn()
		"cancel": cancel()
		"back": refresh()
		"inspect":
			inspecting = payload
			hud.set_inspect(payload)
			board.cursor = (payload as Unit).pos

func _on_tool(tool: String) -> void:
	audio.play("select")
	match tool:
		"rot_l": rotate_camera(-1)
		"rot_r": rotate_camera(1)
		"zoom_in": zoom_target = clampf(zoom_target * 1.18, 0.38, 2.2)
		"zoom_out": zoom_target = clampf(zoom_target * 0.85, 0.38, 2.2)
		"fit": fit_camera()
		"menu": show_pause()

# ------------------------------------------------------------------ camera --
func _build_sky() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	sky = TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(sky)
	add_child(layer)
	_apply_sky("clear")

func _apply_sky(weather: String) -> void:
	var tints := {
		"clear": ["#1d2742", "#0d0f1a"], "rain": ["#1a2233", "#080a12"],
		"dusk": ["#3a2340", "#120c18"], "night": ["#141030", "#05040c"]}
	var pair: Array = tints.get(weather, tints["clear"])
	var grad := Gradient.new()
	grad.set_color(0, Color(String(pair[0])))
	grad.set_color(1, Color(String(pair[1])))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	sky.texture = tex

## Frame the board. On a narrow screen fitting the whole diagonal would make
## the tiles unreadable, so keep a legible floor zoom and follow the action.
func fit_camera() -> void:
	if battle == null:
		return
	var vp := get_viewport_rect().size
	var g := battle.grid
	var span_w := (g.cols + g.rows) * Iso.TW * 0.5 + 70.0
	var span_h := (g.cols + g.rows) * Iso.TH * 0.5 + 8.0 * Iso.HS + 150.0
	var z_fit: float = minf(vp.x / span_w, vp.y / span_h)
	var floor_z := 0.58 if vp.x < 720.0 else 0.62
	fits_board = z_fit >= floor_z
	zoom = clampf(maxf(z_fit, floor_z), 0.42, 1.7)
	zoom_target = zoom
	centre_board()

func centre_board() -> void:
	var g := battle.grid
	var c := board.project((g.cols - 1) * 0.5, (g.rows - 1) * 0.5, 1.2)
	cam_offset = -c
	cam_target = null

func focus_on(cell: Vector2i) -> void:
	if battle == null:
		return
	cam_target = -board.project(cell.x, cell.y, battle.grid.height_at(cell.x, cell.y))

func rotate_camera(d: int) -> void:
	var anchor = board.cursor if board.cursor != null else (battle.active.pos if battle != null and battle.active != null else null)
	board.rotate_by(d)
	if anchor != null:
		focus_on(anchor)
	elif battle != null:
		centre_board()

func _process(delta: float) -> void:
	_frames += 1
	if shot_dir != "" and _frames % shot_every == 0:
		_capture()
	if quit_frames > 0 and _frames >= quit_frames:
		get_tree().quit()
	if autoplay and mode == "idle" and not busy and me() != null:
		_autoplay_step()
	zoom = lerpf(zoom, zoom_target, minf(1.0, delta * 10.0))
	if cam_target != null:
		cam_offset = cam_offset.lerp(cam_target, minf(1.0, delta * 6.0))
		if cam_offset.distance_to(cam_target) < 0.5:
			cam_target = null
	world.scale = Vector2(zoom, zoom)
	world.position = get_viewport_rect().size * 0.5 + cam_offset * zoom

func _capture() -> void:
	var img := get_viewport().get_texture().get_image()
	_shot_index += 1
	img.save_png("%s/shot-%02d.png" % [shot_dir, _shot_index])

## Drives the player side with the same AI the enemies use. Goes through the
## real UI entry points so autoplay exercises the code a person would.
func _autoplay_step() -> void:
	var u := me()
	var plan := EnemyAI.plan_turn(battle, u)
	if plan["move"] != null and not u.moved:
		enter_move()
		click(plan["move"])
		return
	var ability: Dictionary = plan["ability"]
	if not ability.is_empty() and not u.acted and battle.valid_target(u, ability, plan["target"]):
		enter_target({"ability": ability})
		click(plan["target"])
		return
	end_turn()

func screen_to_world(p: Vector2) -> Vector2:
	return (p - world.position) / zoom

# ------------------------------------------------------------------- input --
func _unhandled_input(event: InputEvent) -> void:
	if hud.sheet_visible():
		return
	if event is InputEventMouseMotion:
		if _dragging:
			cam_offset += event.relative / zoom
			cam_target = null
			_drag_moved = true
		else:
			hover(board.pick(screen_to_world(event.position)))
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
				if event.pressed:
					_drag_moved = false
				elif not _drag_moved:
					cancel()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_target = clampf(zoom_target * 1.1, 0.38, 2.2)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_target = clampf(zoom_target * 0.9, 0.38, 2.2)
			MOUSE_BUTTON_LEFT:
				if not event.pressed:
					click(board.pick(screen_to_world(event.position)))
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = {"start": event.position, "moved": false}
	else:
		var info: Dictionary = _touches.get(event.index, {})
		_touches.erase(event.index)
		_pinch = 0.0
		if _touches.is_empty() and not info.get("moved", true):
			var world_pos := screen_to_world(event.position)
			hover(board.pick(world_pos))
			click(board.pick(world_pos))

func _handle_drag(event: InputEventScreenDrag) -> void:
	if _touches.has(event.index):
		_touches[event.index]["moved"] = true
	if _touches.size() >= 2:
		var pts: Array = []
		for k in _touches:
			pts.append(_touches[k]["start"])
		return
	cam_offset += event.relative / zoom
	cam_target = null

func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_Q: rotate_camera(-1)
		KEY_E: rotate_camera(1)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom_target = clampf(zoom_target * 1.15, 0.38, 2.2)
		KEY_MINUS, KEY_KP_SUBTRACT: zoom_target = clampf(zoom_target * 0.87, 0.38, 2.2)
		KEY_ESCAPE: cancel()
		KEY_SPACE:
			if mode == "idle":
				end_turn()
		KEY_M:
			if mode == "idle":
				enter_move()
		KEY_U:
			var u := me()
			if u != null and u.moved and not u.acted and battle.undo_move(u):
				board.snap(u)
				battle.drain()
				refresh()
		KEY_I:
			if mode == "idle":
				item_menu()
		KEY_F: fit_camera()
		KEY_R: rewind_turn()
		KEY_ENTER, KEY_KP_ENTER:
			if mode == "deploy":
				begin_battle()
		KEY_H: show_help(mode)
