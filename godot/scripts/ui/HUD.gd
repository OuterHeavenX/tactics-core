# ============================================================================
# The heads-up display: turn order strip, unit panels, action bar, targeting
# preview, battle log and the full-screen sheets (title, briefing, results).
#
# Built entirely in code so the scene file stays trivial and the layout can
# react to the viewport size — the same panels reflow for a phone.
# ============================================================================
class_name HUD
extends CanvasLayer

signal action_chosen(kind: String, payload: Variant)
signal tool_pressed(tool: String)
signal sheet_action(id: String)

const GOLD := Color("#e8c66a")
const DIM := Color("#98a0c4")
const BLUE := Color("#5b8def")
const RED := Color("#e05b5b")
const GREEN := Color("#6fd08c")

var root: Control
var chapter_label: RichTextLabel
var strip: HBoxContainer
var tools: HBoxContainer
var unit_panel: RichTextLabel
var inspect_panel: RichTextLabel
var action_bar: HBoxContainer
var preview: RichTextLabel
var log_box: RichTextLabel
var hint: Label
var sheet_layer: Control
var sheet_body: VBoxContainer

var compact := false

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()
	get_viewport().size_changed.connect(_relayout)
	_relayout()

# ------------------------------------------------------------- construction --
func _panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.078, 0.09, 0.149, 0.92)
	sb.border_color = Color(0.47, 0.52, 0.75, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(9)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

func _rich(size: int = 12) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _button(text: String, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 13)
	return b

func _build() -> void:
	# --- top left: chapter -------------------------------------------------
	var chapter_panel := _panel()
	chapter_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chapter_panel.position = Vector2(10, 10)
	chapter_label = _rich(12)
	chapter_label.custom_minimum_size = Vector2(190, 0)
	chapter_panel.add_child(chapter_label)
	root.add_child(chapter_panel)
	chapter_panel.name = "ChapterPanel"

	# --- top centre: turn order strip -------------------------------------
	var strip_panel := _panel()
	strip_panel.name = "StripPanel"
	strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	strip_panel.add_child(strip)
	root.add_child(strip_panel)

	# --- top right: tools --------------------------------------------------
	tools = HBoxContainer.new()
	tools.name = "Tools"
	tools.add_theme_constant_override("separation", 5)
	for spec in [["rot_l", "<", "Rotate camera left (Q)"], ["rot_r", ">", "Rotate camera right (E)"],
			["zoom_in", "+", "Zoom in"], ["zoom_out", "-", "Zoom out"],
			["fit", "[ ]", "Recentre camera (F)"], ["menu", "=", "Menu (Esc)"]]:
		var b := _button(spec[1], spec[2])
		b.custom_minimum_size = Vector2(36, 34)
		b.pressed.connect(func(): tool_pressed.emit(spec[0]))
		b.name = spec[0]
		tools.add_child(b)
	root.add_child(tools)

	# --- bottom left: active unit -----------------------------------------
	var up := _panel(Vector2(210, 0))
	up.name = "UnitPanel"
	unit_panel = _rich(12)
	up.add_child(unit_panel)
	root.add_child(up)

	# --- right: inspected unit --------------------------------------------
	var ip := _panel(Vector2(180, 0))
	ip.name = "InspectPanel"
	inspect_panel = _rich(11)
	ip.add_child(inspect_panel)
	ip.visible = false
	root.add_child(ip)

	# --- bottom centre: actions -------------------------------------------
	action_bar = HBoxContainer.new()
	action_bar.name = "ActionBar"
	action_bar.add_theme_constant_override("separation", 6)
	root.add_child(action_bar)

	# --- targeting preview -------------------------------------------------
	var pv := _panel(Vector2(200, 0))
	pv.name = "PreviewPanel"
	preview = _rich(12)
	pv.add_child(preview)
	pv.visible = false
	root.add_child(pv)

	# --- battle log --------------------------------------------------------
	var lp := _panel(Vector2(230, 150))
	lp.name = "LogPanel"
	log_box = _rich(11)
	log_box.fit_content = false
	log_box.scroll_active = true
	log_box.custom_minimum_size = Vector2(212, 132)
	lp.add_child(log_box)
	root.add_child(lp)

	hint = Label.new()
	hint.name = "Hint"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	# --- modal sheet -------------------------------------------------------
	sheet_layer = Control.new()
	sheet_layer.name = "Sheet"
	sheet_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet_layer.visible = false
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.025, 0.05, 0.93)
	sheet_layer.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := _panel(Vector2(520, 0))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_body = VBoxContainer.new()
	sheet_body.add_theme_constant_override("separation", 8)
	sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sheet_body)
	card.add_child(scroll)
	centre.add_child(card)
	sheet_layer.add_child(centre)
	root.add_child(sheet_layer)
	sheet_layer.set_meta("card", card)
	sheet_layer.set_meta("scroll", scroll)

# ------------------------------------------------------------------ layout --
## Free-floating Controls under a plain Control parent only ever grow, so they
## are shrunk back to their content size every layout pass.
func _shrink(c: Control) -> void:
	c.size = c.get_combined_minimum_size()

func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	compact = vp.x < 860
	var pad := 8.0 if compact else 12.0

	var chapter_panel: PanelContainer = root.get_node("ChapterPanel")
	chapter_label.custom_minimum_size = Vector2(110 if compact else 190, 0)
	_shrink(chapter_panel)
	chapter_panel.position = Vector2(pad, pad)

	var strip_panel: PanelContainer = root.get_node("StripPanel")
	_shrink(strip)
	_shrink(strip_panel)
	strip_panel.position = Vector2(vp.x * 0.5 - strip_panel.size.x * 0.5, pad)

	_shrink(tools)
	tools.position = Vector2(vp.x - tools.size.x - pad, pad)
	for n in ["zoom_in", "zoom_out", "fit"]:
		tools.get_node(n).visible = not compact

	var up: PanelContainer = root.get_node("UnitPanel")
	var ip: PanelContainer = root.get_node("InspectPanel")
	var ab := action_bar
	var pv: PanelContainer = root.get_node("PreviewPanel")
	var lp: PanelContainer = root.get_node("LogPanel")

	lp.visible = not compact
	for c in [up, ip, pv, ab]:
		_shrink(c)
	if compact:
		# Phone: the board owns the middle; panels hug the top corners and the
		# action bar takes the whole bottom edge.
		up.custom_minimum_size = Vector2(142, 0)
		up.position = Vector2(pad, 58)
		ip.position = Vector2(vp.x - ip.size.x - pad, 58)
		ip.visible = ip.visible and vp.x >= 520
	else:
		up.custom_minimum_size = Vector2(210, 0)
		up.position = Vector2(pad, vp.y - up.size.y - pad)
		ip.position = Vector2(vp.x - ip.size.x - pad, 84)
		lp.position = Vector2(vp.x - lp.size.x - pad, vp.y - lp.size.y - pad)

	ab.position = Vector2(vp.x * 0.5 - ab.size.x * 0.5, vp.y - ab.size.y - pad)
	pv.position = Vector2(vp.x * 0.5 - pv.size.x * 0.5, ab.position.y - pv.size.y - 6)
	hint.size = Vector2(minf(vp.x - 40.0, 440.0), 34)
	hint.position = Vector2(vp.x * 0.5 - hint.size.x * 0.5, pv.position.y - 26)

	# The sheet hugs its content and only becomes scrollable when it overflows.
	var card: PanelContainer = sheet_layer.get_meta("card")
	var scroll: ScrollContainer = sheet_layer.get_meta("scroll")
	var w: float = minf(vp.x - 32.0, 560.0)
	card.custom_minimum_size = Vector2(w, 0)
	var wanted: float = sheet_body.get_combined_minimum_size().y
	scroll.custom_minimum_size = Vector2(w - 26.0, minf(wanted, vp.y - 90.0))

func _process(_dt: float) -> void:
	# Panels resize as their text changes, so keep them pinned every frame.
	_relayout()

# ------------------------------------------------------------------ content --
func set_chapter(title: String, objective: String) -> void:
	chapter_label.text = "[b][color=#e8c66a]%s[/color][/b]\n[color=#98a0c4]%s[/color]" % [title, objective]

func set_hint(text: String) -> void:
	hint.text = text
	hint.visible = text != "" and not (root.get_node("PreviewPanel").visible and compact)

func log_line(text: String) -> void:
	log_box.append_text(text + "\n")
	log_box.scroll_to_line(maxi(0, log_box.get_line_count() - 1))

func clear_log() -> void:
	log_box.clear()

func set_turn_order(units: Array, active: Unit) -> void:
	for c in strip.get_children():
		c.queue_free()
	var limit := 4 if get_viewport().get_visible_rect().size.x < 520 else (5 if compact else 7)
	for i in mini(limit, units.size()):
		if units[i] is Dictionary:
			# A charged spell about to land.
			var sp: Dictionary = units[i]["spell"]
			var sb := Button.new()
			sb.text = "*"
			sb.custom_minimum_size = Vector2(26 if compact else 32, 26 if compact else 30)
			sb.tooltip_text = "%s is charging" % GameData.ability(String(sp["abilityId"]))["name"]
			sb.add_theme_color_override("font_color", Color("#ff9d5c"))
			strip.add_child(sb)
			continue
		var u: Unit = units[i]
		var b := Button.new()
		b.text = BoardView.JOB_LETTER.get(u.job, "?")
		b.custom_minimum_size = Vector2(26 if compact else 32, 26 if compact else 30)
		b.tooltip_text = "%s — %s Lv %d" % [u.unit_name, u.job, u.level]
		b.add_theme_color_override("font_color", u.color())
		if u == active:
			b.add_theme_color_override("font_color", GOLD)
		b.pressed.connect(func(): action_chosen.emit("inspect", u))
		strip.add_child(b)

func unit_block(u: Unit, brief: bool) -> String:
	var hp_pct := float(u.hp) / u.max_hp
	var bar := func(frac: float, col: String) -> String:
		var filled := int(round(frac * 10.0))
		return "[color=%s]%s[/color][color=#222738]%s[/color]" % [col, "|".repeat(filled), "|".repeat(10 - filled)]
	var out := "[b][color=#%s]%s %s[/color][/b]\n" % [u.color().to_html(false), BoardView.JOB_LETTER.get(u.job, "?"), u.unit_name]
	out += "[color=#e8c66a]%s · Lv %d[/color] [color=#98a0c4]· %s[/color]\n" % [
		u.job, u.level, "Ally" if u.team == "P" else "Enemy"]
	out += "HP %d/%d %s\n" % [u.hp, u.max_hp, bar.call(hp_pct, "#6fd08c" if hp_pct > 0.35 else "#e05b5b")]
	if u.max_mp > 0:
		out += "MP %d/%d %s\n" % [u.mp, u.max_mp, bar.call(float(u.mp) / u.max_mp, "#7aa5ff")]
	if u.team == "P" and not brief and not u.npc:
		out += "[color=#98a0c4]XP %d/%d · %d JP[/color]\n" % [u.xp, u.xp_to_next(), u.jp]
	out += "[color=#98a0c4]ATK[/color] %d  [color=#98a0c4]DEF[/color] %d  [color=#98a0c4]MAG[/color] %d\n" % [
		u.stat("atk"), u.stat("def"), u.stat("mag")]
	out += "[color=#98a0c4]RES[/color] %d  [color=#98a0c4]SPD[/color] %d  [color=#98a0c4]MOV[/color] %d  [color=#98a0c4]JMP[/color] %d\n" % [
		u.stat("res"), u.stat("spd"), u.stat("move"), u.stat("jump")]
	if not u.status.is_empty():
		var bits: Array[String] = []
		for sid in u.status:
			var sd: Dictionary = GameData.STATUS[sid]
			bits.append("[color=%s]%s %d[/color]" % [sd["color"], sd["name"], int(u.status[sid])])
		out += " ".join(bits) + "\n"
	return out

func set_active_unit(u: Unit) -> void:
	unit_panel.text = unit_block(u, false) if u != null else "[color=#98a0c4]—[/color]"

func set_inspect(u: Unit) -> void:
	var ip: PanelContainer = root.get_node("InspectPanel")
	ip.visible = u != null and not (compact and get_viewport().get_visible_rect().size.x < 520)
	if u != null:
		inspect_panel.text = unit_block(u, true)

func set_preview(text: String) -> void:
	var pv: PanelContainer = root.get_node("PreviewPanel")
	pv.visible = text != ""
	preview.text = text
	set_hint(hint.text)

## `entries` is an Array of {label, kind, payload, disabled, accent}.
func set_actions(entries: Array) -> void:
	for c in action_bar.get_children():
		c.queue_free()
	for e in entries:
		var b := _button(String(e["label"]), String(e.get("tip", "")))
		b.disabled = bool(e.get("disabled", false))
		if e.get("accent", "") == "primary":
			b.add_theme_color_override("font_color", GOLD)
		elif e.get("accent", "") == "danger":
			b.add_theme_color_override("font_color", RED)
		var kind := String(e["kind"])
		var payload: Variant = e.get("payload", null)
		b.pressed.connect(func(): action_chosen.emit(kind, payload))
		action_bar.add_child(b)

# ------------------------------------------------------------------- sheets --
## `buttons` is an Array of {id, label, accent}.
func show_sheet(title: String, body: String, buttons: Array, subtitle: String = "") -> void:
	for c in sheet_body.get_children():
		c.queue_free()
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", 26)
	h.add_theme_color_override("font_color", GOLD)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_body.add_child(h)
	if subtitle != "":
		var sl := Label.new()
		sl.text = subtitle
		sl.add_theme_font_size_override("font_size", 14)
		sl.add_theme_color_override("font_color", DIM)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sheet_body.add_child(sl)
	var r := _rich(13)
	r.text = body
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_body.add_child(r)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for b in buttons:
		var btn := _button(String(b["label"]))
		if b.get("accent", "") == "primary":
			btn.add_theme_color_override("font_color", GOLD)
		elif b.get("accent", "") == "danger":
			btn.add_theme_color_override("font_color", RED)
		var id := String(b["id"])
		btn.pressed.connect(func(): sheet_action.emit(id))
		row.add_child(btn)
	sheet_body.add_child(row)
	sheet_layer.visible = true

func hide_sheet() -> void:
	sheet_layer.visible = false

func sheet_visible() -> bool:
	return sheet_layer.visible
