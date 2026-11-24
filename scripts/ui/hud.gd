extends CanvasLayer
class_name GameHUD

## Code-built race HUD. Altitude, timer and leaderboard come from the host
## snapshot; the local climber only drives stamina, jetpack and ragdoll readouts.
## Falls do not damage; the first climber to the summit wins.

signal chat_submitted(text: String)

const TEXT_COLOR := Color(0.92, 0.95, 1.0)
const ACCENT_COLOR := Color(0.32, 0.86, 1.0)
const WARNING_COLOR := Color(1.0, 0.28, 0.22)
const PANEL_COLOR := Color(0.035, 0.055, 0.09, 0.82)
const PANEL_EDGE := Color(0.28, 0.5, 0.72, 0.9)

var _ui: Control
var _time_label: Label
var _alt_label: Label
var _phase_label: Label
var _stamina_fill: ColorRect
var _jetpack_label: Label
var _jetpack_remove_button: Button
var _ragdoll_banner: Label
var _recover_banner: Label
var _countdown_label: Label
var _go_label: Label
var _rank_rows: Array[Label] = []
var _score_panel: PanelContainer
var _score_rows: Array[Label] = []
var _event_box: VBoxContainer
var _chat_box: VBoxContainer
var _chat_input: LineEdit
var _winner_panel: PanelContainer
var _winner_title: Label
var _winner_details: Label
var _winner_hint: Label

var _local_climber: Node = null
var _events: Array = []
var _chat_lines: Array = []
var _chat_open := false
var _recover_time := 0.0
var _go_time := 0.0
var _was_ragdoll := false
var _live_altitude := 0.0
var _local_best_altitude := 0.0
var _last_phase := 0
var _last_state: Dictionary = {}


func _ready() -> void:
	layer = 20
	_ui = Control.new()
	_ui.name = "Root"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_build_top_bar()
	_build_crosshair()
	_build_bars()
	_build_banners()
	_build_leaderboard()
	_build_message_feeds()
	_build_winner_overlay()


static func _arg_count(node: Object, signal_name: StringName) -> int:
	if node == null:
		return 0
	for info in node.get_signal_list():
		if String(info.get("name", "")) == String(signal_name):
			var args: Array = info.get("args", [])
			return args.size()
	return 0


func _style(bg: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _make_label(text: String, size: int, color: Color = TEXT_COLOR, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL_COLOR, PANEL_EDGE, 8))
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	panel.add_child(row)
	_time_label = _make_label("TIME 05:00", 22, ACCENT_COLOR)
	_alt_label = _make_label("ALT 0.0 m", 20)
	_phase_label = _make_label("GET READY", 18, Color(1.0, 0.86, 0.45))
	row.add_child(_time_label)
	row.add_child(_alt_label)
	row.add_child(_phase_label)


func _build_crosshair() -> void:
	_make_cross_line(16, 2)
	_make_cross_line(2, 16)


func _make_cross_line(width: float, height: float) -> void:
	var line := ColorRect.new()
	line.color = Color(0.9, 0.96, 1.0, 0.82)
	line.set_anchors_preset(Control.PRESET_CENTER)
	line.offset_left = -width * 0.5
	line.offset_right = width * 0.5
	line.offset_top = -height * 0.5
	line.offset_bottom = height * 0.5
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(line)


func _make_bar(title: String, color: Color) -> Dictionary:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	var caption := _make_label(title, 12, ACCENT_COLOR)
	var track := ColorRect.new()
	track.color = Color(0.08, 0.11, 0.16, 0.92)
	track.custom_minimum_size = Vector2(236, 14)
	var fill := ColorRect.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.color = color
	track.add_child(fill)
	column.add_child(caption)
	column.add_child(track)
	return {"root": column, "fill": fill, "track": track}


func _build_bars() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 20
	box.offset_right = 260
	box.offset_top = -132
	box.offset_bottom = -20
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(box)
	var stamina: Dictionary = _make_bar("STAMINA", Color(0.28, 0.85, 0.62))
	_stamina_fill = stamina["fill"]
	box.add_child(stamina["root"])
	_jetpack_label = _make_label("JETPACK: NONE", 13, ACCENT_COLOR)
	box.add_child(_jetpack_label)
	_jetpack_remove_button = Button.new()
	_jetpack_remove_button.text = "REMOVE EMPTY JETPACK  [G]"
	_jetpack_remove_button.visible = false
	_jetpack_remove_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_jetpack_remove_button.pressed.connect(_on_remove_jetpack_pressed)
	box.add_child(_jetpack_remove_button)


func _build_banners() -> void:
	_countdown_label = _make_label("3", 110, Color(1.0, 0.92, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.offset_left = -110
	_countdown_label.offset_right = 110
	_countdown_label.offset_top = -90
	_countdown_label.offset_bottom = 20
	_ui.add_child(_countdown_label)
	_go_label = _make_label("GO!", 72, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_go_label.set_anchors_preset(Control.PRESET_CENTER)
	_go_label.offset_left = -160
	_go_label.offset_right = 160
	_go_label.offset_top = -80
	_go_label.offset_bottom = 10
	_go_label.visible = false
	_ui.add_child(_go_label)
	_ragdoll_banner = _make_label("STUMBLE", 30, WARNING_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_ragdoll_banner.set_anchors_preset(Control.PRESET_CENTER)
	_ragdoll_banner.offset_left = -330
	_ragdoll_banner.offset_right = 330
	_ragdoll_banner.offset_top = -40
	_ragdoll_banner.offset_bottom = 10
	_ragdoll_banner.visible = false
	_ui.add_child(_ragdoll_banner)
	_recover_banner = _make_label("RECOVERED!", 26, Color(0.35, 1.0, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
	_recover_banner.set_anchors_preset(Control.PRESET_CENTER)
	_recover_banner.offset_left = -240
	_recover_banner.offset_right = 240
	_recover_banner.offset_top = -16
	_recover_banner.offset_bottom = 26
	_recover_banner.visible = false
	_ui.add_child(_recover_banner)


func _build_leaderboard() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL_COLOR, PANEL_EDGE))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -272
	panel.offset_right = -16
	panel.offset_top = 14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	column.add_child(_make_label("CLIMBERS", 13, ACCENT_COLOR))
	for i in range(4):
		var row := _make_label("-", 14)
		_rank_rows.append(row)
		column.add_child(row)

	_score_panel = PanelContainer.new()
	_score_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.035, 0.06, 0.94), ACCENT_COLOR, 10))
	_score_panel.set_anchors_preset(Control.PRESET_CENTER)
	_score_panel.offset_left = -310
	_score_panel.offset_right = 310
	_score_panel.offset_top = -230
	_score_panel.offset_bottom = 230
	_score_panel.visible = false
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_score_panel)
	var score_column := VBoxContainer.new()
	score_column.add_theme_constant_override("separation", 8)
	_score_panel.add_child(score_column)
	score_column.add_child(_make_label("SCOREBOARD", 24, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER))
	score_column.add_child(_make_label("NAME                       ALT        SCORE", 13, Color(0.7, 0.8, 0.95)))
	for i in range(4):
		var row := _make_label("-", 16)
		_score_rows.append(row)
		score_column.add_child(row)


func _build_message_feeds() -> void:
	_event_box = VBoxContainer.new()
	_event_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_event_box.offset_left = -320
	_event_box.offset_right = 320
	_event_box.offset_top = -190
	_event_box.offset_bottom = -54
	_event_box.add_theme_constant_override("separation", 2)
	_event_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_event_box)

	_chat_box = VBoxContainer.new()
	_chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_box.offset_left = 20
	_chat_box.offset_right = 430
	_chat_box.offset_top = -300
	_chat_box.offset_bottom = -146
	_chat_box.add_theme_constant_override("separation", 2)
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_chat_box)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Chat - press Enter to send"
	_chat_input.add_theme_stylebox_override("normal", _style(Color(0.03, 0.05, 0.09, 0.95), ACCENT_COLOR, 5))
	_chat_input.add_theme_stylebox_override("focus", _style(Color(0.05, 0.08, 0.13, 0.98), ACCENT_COLOR, 5))
	_chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.offset_left = 20
	_chat_input.offset_right = 430
	_chat_input.offset_top = -140
	_chat_input.offset_bottom = -104
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_text_submitted)
	_ui.add_child(_chat_input)


func _build_winner_overlay() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.58)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(dim)
	_winner_panel = PanelContainer.new()
	_winner_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.08, 0.96), ACCENT_COLOR, 12))
	_winner_panel.set_anchors_preset(Control.PRESET_CENTER)
	_winner_panel.offset_left = -340
	_winner_panel.offset_right = 340
	_winner_panel.offset_top = -220
	_winner_panel.offset_bottom = 220
	_winner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_winner_panel.visible = false
	_ui.add_child(_winner_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_winner_panel.add_child(column)
	_winner_title = _make_label("SUMMIT!", 46, Color(1.0, 0.9, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_winner_details = _make_label("", 18, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_winner_hint = _make_label("ENTER - RETURN TO MENU (HOST)", 15, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_winner_title)
	column.add_child(_winner_details)
	column.add_child(_winner_hint)


func bind_local_climber(climber: Node) -> void:
	if _local_climber == climber:
		return
	_local_climber = climber
	if climber.has_signal(&"ragdoll_started"):
		if _arg_count(climber, &"ragdoll_started") > 0:
			climber.connect(&"ragdoll_started", Callable(self, "_on_ragdoll_started_1"))
		else:
			climber.connect(&"ragdoll_started", Callable(self, "_on_ragdoll_started"))
	if climber.has_signal(&"ragdoll_ended"):
		if _arg_count(climber, &"ragdoll_ended") > 0:
			climber.connect(&"ragdoll_ended", Callable(self, "_on_ragdoll_ended_1"))
		else:
			climber.connect(&"ragdoll_ended", Callable(self, "_on_ragdoll_ended"))


func _on_ragdoll_started() -> void:
	_ragdoll_banner.visible = true


func _on_ragdoll_started_1(_arg: Variant) -> void:
	_on_ragdoll_started()


func _on_ragdoll_ended() -> void:
	_ragdoll_banner.visible = false
	_recover_banner.visible = true
	_recover_time = 1.5


func _on_ragdoll_ended_1(_arg: Variant) -> void:
	_on_ragdoll_ended()


static func _sort_by_altitude(a: Variant, b: Variant) -> bool:
	return float((a as Dictionary).get("highest_y", 0.0)) > float((b as Dictionary).get("highest_y", 0.0))


static func _sort_by_score(a: Variant, b: Variant) -> bool:
	var left: Dictionary = a
	var right: Dictionary = b
	if int(left.get("score", 0)) == int(right.get("score", 0)):
		return float(left.get("highest_y", 0.0)) > float(right.get("highest_y", 0.0))
	return int(left.get("score", 0)) > int(right.get("score", 0))


func update_state(state: Dictionary) -> void:
	_last_state = state
	var phase := int(state.get("phase", 0))
	_last_phase = phase
	var time_left := maxf(0.0, float(state.get("time_left", 300.0)))
	var whole := int(time_left)
	_time_label.text = "TIME %02d:%02d" % [whole / 60, whole % 60]
	_phase_label.text = "GET READY" if phase == 0 else ("CLIMB" if phase == 1 else "MATCH OVER")
	var players: Array = state.get("players", [])
	var local_id := int(state.get("local_peer_id", 0))
	var local_entry: Dictionary = {}
	for item in players:
		if item is Dictionary and int((item as Dictionary).get("peer_id", 0)) == local_id:
			local_entry = item
			break
	_local_best_altitude = float(local_entry.get("highest_y", 0.0))
	_alt_label.text = "ALT %.1f m" % maxf(_local_best_altitude, _live_altitude)
	if phase == 0:
		_countdown_label.visible = true
		_countdown_label.text = str(maxi(1, ceili(float(state.get("countdown", 3.0)))))
	else:
		_countdown_label.visible = false
	_fill_leaderboards(players, local_id)
	_update_winner(state, players)


func _fill_leaderboards(players: Array, local_id: int) -> void:
	var by_altitude: Array = players.duplicate(true)
	by_altitude.sort_custom(_sort_by_altitude)
	for i in range(_rank_rows.size()):
		var row: Label = _rank_rows[i]
		if i >= by_altitude.size():
			row.text = "-"
			continue
		var entry: Dictionary = by_altitude[i]
		var marker := ">" if int(entry.get("peer_id", 0)) == local_id else " "
		row.text = "%s %d. %-12s %5.0fm" % [marker, i + 1, String(entry.get("name", "Climber")).substr(0, 12), float(entry.get("highest_y", 0.0))]
		if int(entry.get("peer_id", 0)) == local_id:
			row.add_theme_color_override("font_color", ACCENT_COLOR)
		else:
			row.add_theme_color_override("font_color", TEXT_COLOR)
	if not _score_panel.visible:
		return
	var by_score: Array = players.duplicate(true)
	by_score.sort_custom(_sort_by_score)
	for i in range(_score_rows.size()):
		var row: Label = _score_rows[i]
		if i >= by_score.size():
			row.text = "-"
			continue
		var entry: Dictionary = by_score[i]
		row.text = "%d. %-20s %6.0fm   %6d" % [i + 1, String(entry.get("name", "Climber")).substr(0, 20), float(entry.get("highest_y", 0.0)), int(entry.get("score", 0))]


func _update_winner(state: Dictionary, players: Array) -> void:
	var phase := int(state.get("phase", 0))
	_winner_panel.visible = phase == 2
	if phase != 2:
		return
	var winner_id := int(state.get("winner", 0))
	var winner_name := str(state.get("winner_name", "Climber"))
	var reason := str(state.get("reason", "TIME UP"))
	_winner_title.text = ("SUMMIT - %s WINS!" % winner_name) if winner_id > 0 else "TIME UP!"
	_winner_details.text = "%s\n\n" % reason
	var ordered: Array = players.duplicate(true)
	ordered.sort_custom(_sort_by_score)
	for item in ordered:
		var entry: Dictionary = item
		_winner_details.text += "%-20s  %6.0f m   %d pts\n" % [String(entry.get("name", "Climber")).substr(0, 20), float(entry.get("highest_y", 0.0)), int(entry.get("score", 0))]
	_winner_details.text += "\n%s" % ("HOST: press ENTER to return to the menu" if bool(state.get("is_host", false)) else "Waiting for the host...")


func _on_remove_jetpack_pressed() -> void:
	if is_instance_valid(_local_climber) and _local_climber.has_method("remove_jetpack"):
		_local_climber.call("remove_jetpack")


func push_event(text: String) -> void:
	var label := _make_label(text, 14, Color(1.0, 0.88, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_event_box.add_child(label)
	_events.append({"label": label, "life": 4.2})
	while _events.size() > 4:
		var oldest: Dictionary = _events.pop_front()
		var old_label: Label = oldest["label"]
		old_label.queue_free()


func add_chat(_peer_id: int, sender: String, text: String) -> void:
	var label := _make_label("%s: %s" % [sender, text], 14, Color(0.78, 0.95, 1.0))
	_chat_box.add_child(label)
	_chat_lines.append({"label": label, "life": 8.0})
	while _chat_lines.size() > 5:
		var oldest: Dictionary = _chat_lines.pop_front()
		var old_label: Label = oldest["label"]
		old_label.queue_free()


func _set_fill(fill: ColorRect, ratio: float) -> void:
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.offset_right = 0.0





func _process(delta: float) -> void:
	if is_instance_valid(_local_climber) and _local_climber.is_inside_tree():
		var stamina := float(_local_climber.get("current_stamina"))
		var max_stamina := float(_local_climber.get("max_stamina"))
		if max_stamina <= 0.0:
			max_stamina = 1.0
		_set_fill(_stamina_fill, stamina / max_stamina)
		_stamina_fill.color = Color(0.28, 0.85, 0.62)
		var has_jetpack := bool(_local_climber.get("has_jetpack"))
		var fuel := clampf(float(_local_climber.get("jetpack_fuel")), 0.0, 100.0)
		if has_jetpack:
			_jetpack_label.text = "JETPACK: %.0f%%" % fuel
		else:
			_jetpack_label.text = "JETPACK: NONE"
		var empty_jetpack: bool = has_jetpack and fuel <= 0.01
		if _jetpack_remove_button.visible != empty_jetpack:
			_jetpack_remove_button.visible = empty_jetpack
			if empty_jetpack:
				_jetpack_label.text += "  - EMPTY: press G or click REMOVE"
		var ragdoll := bool(_local_climber.get("ragdoll_active"))
		if ragdoll and not _was_ragdoll:
			_ragdoll_banner.visible = true
		if ragdoll:
			_ragdoll_banner.text = "STUMBLE"
		elif not ragdoll and _was_ragdoll:
			_ragdoll_banner.visible = false
			_recover_banner.visible = true
			_recover_time = 1.5
		_was_ragdoll = ragdoll
		var pos := Vector3.ZERO
		var pos_value: Variant = _local_climber.get("global_position")
		if pos_value is Vector3:
			pos = pos_value as Vector3
		_live_altitude = maxf(0.0, pos.y - 2.0)
		if _last_phase == 1:
			_alt_label.text = "ALT %.1f m" % maxf(_local_best_altitude, _live_altitude)
	if _recover_time > 0.0:
		_recover_time -= delta
		if _recover_time <= 0.0:
			_recover_banner.visible = false
	if _go_time > 0.0:
		_go_time -= delta
		if _go_time <= 0.0:
			_go_label.visible = false
	_fade_feed(_events, delta)
	_fade_feed(_chat_lines, delta)

func _fade_feed(feed: Array, delta: float) -> void:
	for i in range(feed.size() - 1, -1, -1):
		var item: Dictionary = feed[i]
		item["life"] = float(item["life"]) - delta
		var label: Label = item["label"]
		if not is_instance_valid(label):
			feed.remove_at(i)
			continue
		var alpha := clampf(float(item["life"]) / 1.2, 0.0, 1.0)
		var color: Color = label.get("modulate")
		color.a = alpha
		label.modulate = color
		if float(item["life"]) <= 0.0:
			label.queue_free()
			feed.remove_at(i)


func _on_chat_text_submitted(text: String) -> void:
	var clean := text.strip_edges()
	_close_chat()
	if not clean.is_empty():
		chat_submitted.emit(clean)


func _open_chat() -> void:
	_chat_open = true
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_chat() -> void:
	if not _chat_open:
		return
	_chat_open = false
	_chat_input.visible = false
	_chat_input.release_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if _chat_open:
		if event.is_action_pressed(&"ui_cancel"):
			_close_chat()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey:
			for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "jetpack", "arm_left", "arm_right", "winch_up", "winch_down"]:
				if InputMap.has_action(action) and InputMap.event_is_action(event, action):
					get_viewport().set_input_as_handled()
					break
		return
	if event.is_action_pressed(&"scoreboard"):
		_score_panel.visible = true
		_fill_leaderboards((_last_state.get("players", []) as Array), int(_last_state.get("local_peer_id", 0)))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(&"scoreboard"):
		_score_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action(&"chat") and event.is_action_pressed(&"chat"):
		_open_chat()
		get_viewport().set_input_as_handled()


func show_go_flash() -> void:
	_go_label.visible = true
	_go_time = 1.0
