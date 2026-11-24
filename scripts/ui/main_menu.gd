extends Control

const DEFAULT_HINT := "Host a race on 127.0.0.1  -  Ask your host for their address."
const WEB_HINT := "Browser rooms use WebRTC and a WebSocket signaling server. ENet/UDP is unavailable here; host or join a room to play."
const SIGNAL_CONFIG := "user://web_room.cfg"
const DEFAULT_DISPLAY_NAME := "Climber"
const MENU_WIDTH := 560.0
const LOBBY_WIDTH := 920.0
const LOBBY_HEIGHT := 600.0

var _menu_panel: PanelContainer
var _lobby_panel: PanelContainer

var _name_field: LineEdit
var _address_field: LineEdit
var _signal_field: LineEdit
var _room_field: LineEdit
var _port_field: SpinBox
var _players_option: OptionButton
var _error_label: Label
var _hint_label: Label
var _host_button: Button
var _join_button: Button
var _is_web := false
var _saved_signal_url := ""
var _saved_room_code := ""

var _player_list: VBoxContainer
var _chat_log: RichTextLabel
var _chat_field: LineEdit
var _ready_button: Button
var _start_button: Button
var _leave_button: Button
var _lobby_status: Label
var _host_tag: Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_is_web = OS.has_feature("web")
	randomize()
	_load_web_settings()
	_build_ui()
	_connect_net_signals()
	_show_menu()
	_refresh_lobby()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.035, 0.05, 0.085, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.color = Color(0.10, 0.42, 0.62, 0.16)
	glow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow.offset_bottom = 320.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var accent := ColorRect.new()
	accent.color = Color(0.25, 0.85, 0.72, 0.55)
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 4.0
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent)

	var footer := ColorRect.new()
	footer.color = Color(0.03, 0.04, 0.07, 0.9)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -3.0
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 40)
	outer.add_theme_constant_override("margin_top", 28)
	outer.add_theme_constant_override("margin_right", 40)
	outer.add_theme_constant_override("margin_bottom", 32)
	add_child(outer)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	outer.add_child(column)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	column.add_child(header)

	var title := _make_label("SUMMIT RACE", 46, Color(0.94, 0.98, 1.0), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)

	var subtitle := _make_label("First to the summit wins. Falls cost five seconds.", 18, Color(0.52, 0.80, 0.90))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(subtitle)

	var divider := HSeparator.new()
	var divider_style := StyleBoxLine.new()
	divider_style.color = Color(0.30, 0.60, 0.72, 0.45)
	divider.add_theme_stylebox_override("separator", divider_style)
	column.add_child(divider)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)

	_menu_panel = _build_menu_panel()
	_lobby_panel = _build_lobby_panel()
	center.add_child(_menu_panel)
	center.add_child(_lobby_panel)


func _build_menu_panel() -> PanelContainer:
	var panel := _make_panel(Color(0.07, 0.11, 0.18, 0.96), Color(0.24, 0.52, 0.66, 0.9), 26)
	panel.custom_minimum_size = Vector2(MENU_WIDTH, 0)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	panel.add_child(inner)

	inner.add_child(_make_section("IDENTITY"))
	_name_field = _make_field("Your display name", DEFAULT_DISPLAY_NAME)
	inner.add_child(_make_row("Display name", _name_field))


	_address_field = _make_field("IP address", "127.0.0.1")
	_port_field = SpinBox.new()
	_port_field.min_value = 1
	_port_field.max_value = 65535
	_port_field.step = 1
	_port_field.value = 7777
	_port_field.custom_minimum_size = Vector2(0, 44)
	_port_field.add_theme_font_size_override("font_size", 15)

	_players_option = OptionButton.new()
	_players_option.custom_minimum_size = Vector2(0, 44)
	_players_option.add_item("2 players", 2)
	_players_option.add_item("3 players", 3)
	_players_option.add_item("4 players", 4)
	_players_option.select(2)
	_players_option.add_theme_font_size_override("font_size", 15)

	if _is_web:
		inner.add_child(_make_section("BROWSER ROOM"))
		_signal_field = _make_field("wss://signal.example.com", _saved_signal_url)
		_room_field = _make_field("Room code", _saved_room_code)
		inner.add_child(_make_row("Signal URL", _signal_field))
		inner.add_child(_make_row("Room code", _room_field))
		inner.add_child(_make_row("Max players", _players_option))
	else:
		inner.add_child(_make_section("CONNECTION"))
		inner.add_child(_make_row("IP address", _address_field))
		inner.add_child(_make_row("Port", _port_field))
		inner.add_child(_make_row("Max players", _players_option))

	_error_label = _make_label("", 15, Color(1.0, 0.36, 0.36), true)
	_error_label.custom_minimum_size = Vector2(0, 24)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_error_label)

	_hint_label = _make_label(WEB_HINT if _is_web else DEFAULT_HINT, 13, Color(0.55, 0.67, 0.78))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_hint_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_host_button = _make_button("HOST ROOM" if _is_web else "HOST", "host")
	_join_button = _make_button("JOIN ROOM" if _is_web else "JOIN", "join")
	var quit_button := _make_button("QUIT", "danger")
	buttons.add_child(_host_button)
	buttons.add_child(_join_button)
	buttons.add_child(quit_button)
	for button in buttons.get_children():
		(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(buttons)

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	if _is_web:
		quit_button.hide()

	return panel


func _build_lobby_panel() -> PanelContainer:
	var panel := _make_panel(Color(0.07, 0.11, 0.18, 0.97), Color(0.24, 0.52, 0.66, 0.9), 22)
	panel.custom_minimum_size = Vector2(LOBBY_WIDTH, LOBBY_HEIGHT)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	panel.add_child(inner)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_host_tag = _make_label("HOST", 13, Color(0.35, 0.92, 0.72), true)
	top.add_child(_host_tag)
	var spacer_top := Control.new()
	spacer_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer_top)
	_lobby_status = _make_label("", 14, Color(0.70, 0.84, 0.92))
	top.add_child(_lobby_status)
	inner.add_child(top)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	inner.add_child(columns)

	var players_panel := _make_panel(Color(0.05, 0.09, 0.15, 0.9), Color(0.18, 0.38, 0.50, 0.8), 16)
	players_panel.custom_minimum_size = Vector2(360, 300)
	players_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var players_column := VBoxContainer.new()
	players_column.add_theme_constant_override("separation", 10)
	players_panel.add_child(players_column)
	players_column.add_child(_make_section("PLAYERS IN LOBBY"))
	_player_list = VBoxContainer.new()
	_player_list.add_theme_constant_override("separation", 7)
	_player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_column.add_child(_player_list)
	columns.add_child(players_panel)

	var chat_panel := _make_panel(Color(0.05, 0.09, 0.15, 0.9), Color(0.18, 0.38, 0.50, 0.8), 16)
	chat_panel.custom_minimum_size = Vector2(420, 300)
	chat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chat_column := VBoxContainer.new()
	chat_column.add_theme_constant_override("separation", 10)
	chat_panel.add_child(chat_column)
	chat_column.add_child(_make_section("CHAT"))

	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false
	_chat_log.scroll_active = true
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(0, 180)
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override("normal_font_size", 14)
	chat_column.add_child(_chat_log)

	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 8)
	_chat_field = _make_field("Say something...", "")
	_chat_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_row.add_child(_chat_field)
	var send_button := _make_button("SEND", "small")
	chat_row.add_child(send_button)
	chat_column.add_child(chat_row)
	columns.add_child(chat_panel)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_ready_button = _make_button("READY", "join")
	_ready_button.custom_minimum_size = Vector2(130, 46)
	bottom.add_child(_ready_button)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer_bottom)

	_start_button = _make_button("START MATCH", "host")
	bottom.add_child(_start_button)
	_leave_button = _make_button("LEAVE", "danger")
	bottom.add_child(_leave_button)
	inner.add_child(bottom)

	_chat_field.text_submitted.connect(_on_chat_submitted)
	send_button.pressed.connect(_on_send_pressed)
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)

	return panel


func _connect_net_signals() -> void:
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.hosted.connect(_on_hosted)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.match_started.connect(_on_match_started)
	Net.match_start_rejected.connect(_on_match_start_rejected)
	Net.disconnected.connect(_on_disconnected)
	Net.chat_message.connect(_on_chat_message)


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _make_panel(bg: Color, border: Color, margin: float) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_label(text: String, size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_color_override("font_color", color.lightened(0.12))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_section(text: String) -> Label:
	var label := _make_label(text, 12, Color(0.42, 0.74, 0.84), true)
	label.add_theme_constant_override("line_spacing", 0)
	return label


func _make_field(placeholder: String, initial: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = initial
	field.custom_minimum_size = Vector2(0, 44)
	field.add_theme_font_size_override("font_size", 15)
	field.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.06, 0.11, 0.95)
	normal.border_color = Color(0.20, 0.40, 0.52, 0.9)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	field.add_theme_stylebox_override("normal", normal)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.36, 0.86, 0.78, 1.0)
	focus.set_border_width_all(2)
	field.add_theme_stylebox_override("focus", focus)

	var read_only := normal.duplicate() as StyleBoxFlat
	read_only.bg_color = Color(0.06, 0.09, 0.13, 0.9)
	field.add_theme_stylebox_override("read_only", read_only)
	return field


func _make_button(text: String, variant: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 16)

	var bg := Color(0.16, 0.34, 0.46)
	var border := Color(0.30, 0.62, 0.74)
	var fg := Color(0.95, 0.99, 1.0)
	match variant:
		"host":
			bg = Color(0.10, 0.42, 0.35)
			border = Color(0.30, 0.88, 0.66)
			fg = Color(0.96, 1.0, 0.98)
		"join":
			bg = Color(0.13, 0.32, 0.52)
			border = Color(0.36, 0.68, 0.94)
			fg = Color(0.96, 0.99, 1.0)
		"danger":
			bg = Color(0.34, 0.14, 0.18)
			border = Color(0.82, 0.38, 0.42)
			fg = Color(1.0, 0.94, 0.94)
		"small":
			bg = Color(0.14, 0.30, 0.40)
			border = Color(0.28, 0.58, 0.68)
			button.custom_minimum_size = Vector2(96, 44)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = border
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(9)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.12)
	hover.border_color = border.lightened(0.18)
	button.add_theme_stylebox_override("hover", hover)

	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = bg.darkened(0.18)
	button.add_theme_stylebox_override("pressed", pressed_style)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.92, 0.98, 1.0)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.12, 0.15, 0.19)
	disabled.border_color = Color(0.24, 0.28, 0.32)
	button.add_theme_stylebox_override("disabled", disabled)

	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg.lightened(0.15))
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.58, 0.62))
	return button


func _make_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _make_label(label_text, 15, Color(0.72, 0.82, 0.90))
	label.custom_minimum_size = Vector2(122, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


# ---------------------------------------------------------------------------
# Screen state
# ---------------------------------------------------------------------------

func _show_menu() -> void:
	_lobby_panel.hide()
	_menu_panel.show()
	_error_label.text = ""
	_hint_label.text = WEB_HINT if _is_web else DEFAULT_HINT
	_ready_button.text = "READY"
	_ready_button.disabled = false
	_ready_button.self_modulate = Color.WHITE
	_start_button.disabled = false
	_name_field.grab_focus()


func _show_lobby() -> void:
	_menu_panel.hide()
	_lobby_panel.show()
	_error_label.text = ""
	_refresh_chat()
	_refresh_lobby()
	_chat_field.grab_focus()


func _refresh_lobby() -> void:
	var me := Net.player_data(Net.peer_id)
	var local_ready := bool(me.get("ready", false))
	_ready_button.visible = not Net.is_host
	_ready_button.text = "READY ✓" if local_ready else "READY"
	_ready_button.self_modulate = Color(0.45, 1.0, 0.7) if local_ready else Color.WHITE
	_start_button.visible = Net.is_host
	_host_tag.text = "HOST" if Net.is_host else "CLIENT"

	_start_button.disabled = Net.players.size() < 2
	if Net.is_host:
		if _is_web:
			_lobby_status.text = "Room %s  -  %d/%d players" % [Net.web_room, Net.players.size(), Net.max_players]
		else:
			_lobby_status.text = "Port %d  -  %d/%d players" % [Net.port, Net.players.size(), Net.max_players]
		if _start_button.disabled:
			_lobby_status.add_theme_color_override("font_color", Color(1.0, 0.62, 0.5))
		else:
			_lobby_status.remove_theme_color_override("font_color")
	else:
		_lobby_status.text = "Waiting for host to start…"
		_lobby_status.remove_theme_color_override("font_color")

	_refresh_players()


func _refresh_players() -> void:
	for child in _player_list.get_children():
		child.queue_free()

	var ids: Array = Net.players.keys()
	ids.sort()
	if ids.is_empty():
		_player_list.add_child(_make_label("No players connected yet.", 14, Color(0.60, 0.70, 0.78)))
		return

	for id_variant in ids:
		var id := int(id_variant)
		var data := Net.player_data(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var swatch := ColorRect.new()
		swatch.color = data.get("color", Color.WHITE)
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)

		var who := str(data.get("name", "Player"))
		if id == Net.peer_id:
			who += " (you)"
		var name_label := _make_label(who, 15, Color(0.93, 0.97, 1.0))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)


		var is_host_slot := id == 1
		var is_ready := bool(data.get("ready", false))
		var status_text := "HOST" if is_host_slot else ("READY" if is_ready else "NOT READY")
		var status_color := Color(0.35, 0.92, 0.72) if is_host_slot else (Color(0.38, 0.92, 0.65) if is_ready else Color(0.68, 0.72, 0.78))
		row.add_child(_make_label(status_text, 13, status_color, is_host_slot or is_ready))
		_player_list.add_child(row)


func _refresh_chat() -> void:
	_chat_log.clear()
	for entry in Net.recent_chat:
		_append_chat_entry(entry)


func _append_chat_entry(entry: Dictionary) -> void:
	var color: Color = entry.get("color", Color.WHITE)
	var who := str(entry.get("name", "Player"))
	var text := str(entry.get("message", ""))
	_chat_log.push_color(color)
	_chat_log.add_text("[%s] " % who)
	_chat_log.pop()
	_chat_log.add_text(text + "\n")


func _load_web_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SIGNAL_CONFIG) != OK:
		_saved_signal_url = ""
		_saved_room_code = str(randi() % 9000 + 1000)
		return
	_saved_signal_url = str(config.get_value("room", "signal_url", ""))
	_saved_room_code = str(config.get_value("room", "code", str(randi() % 9000 + 1000)))


func _save_web_settings(signal_url: String, room: String) -> void:
	var config := ConfigFile.new()
	config.set_value("room", "signal_url", signal_url)
	config.set_value("room", "code", room)
	config.save(SIGNAL_CONFIG)


# ---------------------------------------------------------------------------
# Local button handlers
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	_error_label.text = ""
	var display := _name_field.text.strip_edges()
	if display.is_empty():
		display = DEFAULT_DISPLAY_NAME
	_name_field.text = display
	if _is_web:
		var signal_url := _signal_field.text.strip_edges()
		var room := _room_field.text.strip_edges().to_upper()
		_save_web_settings(signal_url, room)
		_hint_label.text = "Opening WebRTC room %s..." % room
		Net.create_web_room(display, signal_url, room, _players_option.get_selected_id())
		return
	_hint_label.text = "Starting server on port %d..." % int(_port_field.value)
	Net.create_server(display, _players_option.get_selected_id(), int(_port_field.value))


func _on_join_pressed() -> void:
	_error_label.text = ""
	var display := _name_field.text.strip_edges()
	if display.is_empty():
		display = DEFAULT_DISPLAY_NAME
	_name_field.text = display
	if _is_web:
		var signal_url := _signal_field.text.strip_edges()
		var room := _room_field.text.strip_edges().to_upper()
		_save_web_settings(signal_url, room)
		_hint_label.text = "Joining WebRTC room %s..." % room
		Net.join_web_room(display, signal_url, room)
		return
	var address := _address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	_address_field.text = address
	_hint_label.text = "Connecting to %s:%d..." % [address, int(_port_field.value)]
	Net.join_server(display, address, int(_port_field.value))


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_chat_submitted(text: String) -> void:
	Net.send_chat(text)
	_chat_field.clear()
	_chat_field.grab_focus()


func _on_send_pressed() -> void:
	_on_chat_submitted(_chat_field.text)


func _on_ready_pressed() -> void:
	if Net.is_host:
		return
	var me := Net.player_data(Net.peer_id)
	Net.set_ready(not bool(me.get("ready", false)))
	_refresh_lobby()


func _on_start_pressed() -> void:
	Net.start_match()


func _on_leave_pressed() -> void:
	Net.leave()


# ---------------------------------------------------------------------------
# Net signal handlers
# ---------------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	_refresh_lobby()


func _on_peer_disconnected(_id: int) -> void:
	_refresh_lobby()


func _on_connected() -> void:
	_show_lobby()


func _on_hosted() -> void:
	_show_lobby()


func _on_connection_failed(message: String) -> void:
	_show_menu()
	_error_label.text = "ERROR: " + message
	_hint_label.text = "Check the settings above and try again."


func _on_lobby_changed() -> void:
	if _lobby_panel.visible:
		_refresh_lobby()


func _on_match_started() -> void:
	_lobby_status.text = "Starting match..."
	_start_button.disabled = true
	_ready_button.disabled = true


func _on_match_start_rejected(reason: String) -> void:
	_lobby_status.text = "CANNOT START: " + reason
	_lobby_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.48))


func _on_disconnected() -> void:
	_show_menu()
	_ready_button.disabled = false
	_refresh_lobby()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_chat_message(peer_id: int, message: String) -> void:
	var data := Net.player_data(peer_id)
	_append_chat_entry({
		"name": data.get("name", "Player"),
		"color": data.get("color", Color.WHITE),
		"message": message,
	})
