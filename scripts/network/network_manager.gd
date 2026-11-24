extends Node

## Autoload `Net`. Public surface matches docs/DESIGN.md.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connected()
signal connection_failed(message: String)
signal hosted()
signal lobby_changed()
signal match_started()
signal disconnected()
signal chat_message(peer_id: int, message: String)
signal match_start_rejected(reason: String)

const DEFAULT_PORT := 7777
const DEFAULT_NAME := "Climber"
const MATCH_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MAX_CHAT_ENTRIES := 60
const WEB_RTC_SCRIPT = preload("res://scripts/network/web_rtc_room.gd")

var peer_id: int = 0
var is_host: bool = false
var player_name: String = DEFAULT_NAME
var port: int = DEFAULT_PORT
var web_room: String = ""
var match_seed: int = 0
## Mirror of the class the host assigned to this peer. Classes are never
## chosen locally: the host alternates them in join order before match start.
var character_type: int = CharacterType.STRONG

## Keyed by peer id. Every value has at least name, color and ready.
var players: Dictionary[int, Dictionary] = {}
## Guest join order. Index 0 is Elastic, 1 is Strong, 2 is Elastic, and so on.
var _join_order: Array[int] = []
var recent_chat: Array[Dictionary] = []
var max_players: int = 4

var _enet_peer: ENetMultiplayerPeer
var _web_rtc: Node = null
var _last_address: String = "127.0.0.1"
var _match_starting: bool = false
var _match_started: bool = false
var _resetting: bool = false


func _ready() -> void:
	_web_rtc = WEB_RTC_SCRIPT.new()
	_web_rtc.name = "WebRTCRoom"
	add_child(_web_rtc)
	_web_rtc.room_ready.connect(_on_web_room_ready)
	_web_rtc.failed.connect(_on_web_room_failed)
	_web_rtc.peer_left.connect(_on_web_peer_left)

	multiplayer.peer_connected.connect(_on_multiplayer_peer_connected)
	multiplayer.peer_disconnected.connect(_on_multiplayer_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_multiplayer_connection_failed)
	multiplayer.server_disconnected.connect(_on_multiplayer_server_disconnected)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func create_server(p_player_name: String, p_max_players: int = 4, p_port: int = 7777) -> void:
	if OS.has_feature("web"):
		connection_failed.emit("ENet hosting is not available in the browser. Use a WebRTC room instead.")
		return
	_reset_transport(false)
	player_name = _clean_name(p_player_name)
	if player_name.is_empty():
		player_name = DEFAULT_NAME
	port = clampi(p_port, 1, 65535)
	max_players = clampi(p_max_players, 2, 4)
	is_host = true

	_enet_peer = ENetMultiplayerPeer.new()
	# ENet's client limit excludes the listening server itself.
	var client_slots := clampi(max_players - 1, 1, 3)
	var error: Error = _enet_peer.create_server(port, client_slots)
	if error != OK:
		var message := "Unable to host on port %d: %s" % [port, error_string(error)]
		_reset_transport(false)
		connection_failed.emit(message)
		return

	multiplayer.multiplayer_peer = _enet_peer
	peer_id = multiplayer.get_unique_id()
	players[1] = _make_player_entry(player_name, 1, true)
	assign_character_types()

	hosted.emit()
	connected.emit()
	lobby_changed.emit()


func join_server(p_player_name: String, address: String, p_port: int = 7777) -> void:
	if OS.has_feature("web"):
		connection_failed.emit("ENet joining is not available in the browser. Use a WebRTC room instead.")
		return
	_reset_transport(false)
	player_name = _clean_name(p_player_name)
	if player_name.is_empty():
		player_name = DEFAULT_NAME
	port = clampi(p_port, 1, 65535)
	_last_address = address.strip_edges()
	if _last_address.is_empty():
		connection_failed.emit("Enter a valid IP address.")
		return

	is_host = false
	_enet_peer = ENetMultiplayerPeer.new()
	var error: Error = _enet_peer.create_client(_last_address, port)
	if error != OK:
		var message := "Unable to join %s:%d: %s" % [_last_address, port, error_string(error)]
		_reset_transport(false)
		connection_failed.emit(message)
		return

	multiplayer.multiplayer_peer = _enet_peer


## Web/desktop room over WebRTC. Browsers cannot open UDP sockets, so this is
## the multiplayer path used by the Web build. `create_server()` remains the
## ENet-only API and keeps its explicit browser rejection.
func create_web_room(p_player_name: String, p_signal_url: String, p_room: String, p_max_players: int = 4) -> void:
	_reset_transport(false)
	player_name = _clean_name(p_player_name)
	if player_name.is_empty():
		player_name = DEFAULT_NAME
	max_players = clampi(p_max_players, 2, 4)
	is_host = true
	web_room = p_room.strip_edges().to_upper()
	_web_rtc.call("start_host", p_signal_url, web_room, max_players)


func join_web_room(p_player_name: String, p_signal_url: String, p_room: String) -> void:
	_reset_transport(false)
	player_name = _clean_name(p_player_name)
	if player_name.is_empty():
		player_name = DEFAULT_NAME
	is_host = false
	web_room = p_room.strip_edges().to_upper()
	_web_rtc.call("start_client", p_signal_url, web_room)


## The duo needs both classes: only Strong can throw an awake Elastic, and only
## Elastic can grow the rope a Strong climbs. A same-class lobby cannot play.
func has_both_classes() -> bool:
	var has_strong := false
	var has_elastic := false
	for id in players:
		var value := int((players[id] as Dictionary).get("character_type", CharacterType.STRONG))
		if value == CharacterType.STRONG:
			has_strong = true
		elif value == CharacterType.ELASTIC:
			has_elastic = true
	return has_strong and has_elastic


## The host is always Strong. Guests alternate in the order they joined, so the
## first guest is Elastic and every two-player lobby has both signature moves.
func class_for_join_index(index: int) -> int:
	return CharacterType.ELASTIC if index % 2 == 0 else CharacterType.STRONG


## Recomputes every roster entry from the join order. Called whenever someone
## joins or leaves so the duo stays available even after a disconnect.
func assign_character_types() -> void:
	if not is_host:
		return
	if players.has(1):
		var host_entry: Dictionary = players[1]
		host_entry["character_type"] = CharacterType.STRONG
		players[1] = host_entry
	for i in range(_join_order.size()):
		var id := _join_order[i]
		if not players.has(id):
			continue
		var entry: Dictionary = players[id]
		entry["character_type"] = class_for_join_index(i)
		players[id] = entry
	if peer_id > 0 and players.has(peer_id):
		character_type = int((players[peer_id] as Dictionary).get("character_type", CharacterType.STRONG))
	lobby_changed.emit()
	_broadcast_lobby()


func start_match() -> void:
	if not is_host or not multiplayer.is_server() or _match_starting:
		return
	if players.size() < 2:
		match_start_rejected.emit("Need at least one Strong and one Elastic climber.")
		return
	if not has_both_classes():
		match_start_rejected.emit("Both classes are required: one Strong and one Elastic.")
		return
	_match_starting = true
	match_seed = 20261121 + (Time.get_ticks_msec() % 100000)
	rpc("_rpc_start_match", match_seed)


func leave() -> void:
	_reset_transport(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var current := get_tree().current_scene
	if current != null and current.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)


func set_ready(ready: bool) -> void:
	if peer_id <= 0 or is_host:
		return
	if not players.has(peer_id):
		players[peer_id] = _make_player_entry(player_name, peer_id, ready)
	else:
		var entry: Dictionary = players[peer_id]
		entry["ready"] = ready
		players[peer_id] = entry
	lobby_changed.emit()

	if is_host:
		_broadcast_lobby()
	else:
		rpc_id(1, "_rpc_set_ready", ready)


func send_chat(message: String) -> void:
	var text := message.strip_edges()
	if text.is_empty():
		return
	text = text.substr(0, 300)

	if is_host:
		var sender := peer_id if peer_id > 0 else 1
		_add_chat(sender, text)
		rpc("_rpc_chat_broadcast", sender, text)
	else:
		if multiplayer.multiplayer_peer == null:
			return
		rpc_id(1, "_rpc_chat_to_server", text)


func player_data(id: int) -> Dictionary:
	if players.has(id):
		return (players[id] as Dictionary).duplicate()
	return _make_player_entry(_default_name_for(id), id, false)


# ---------------------------------------------------------------------------
# MultiplayerAPI callbacks
# ---------------------------------------------------------------------------

func _on_multiplayer_peer_connected(id: int) -> void:
	if _resetting or not is_host or id <= 1:
		return

	if not _join_order.has(id):
		_join_order.append(id)
	players[id] = _make_player_entry(_default_name_for(id), id, false)
	assign_character_types()
	peer_connected.emit(id)

	# The joining peer gets the complete snapshot first, then everyone else is
	# updated so all clients agree on the same roster.
	rpc_id(id, "_rpc_apply_lobby", _snapshot())
	_broadcast_lobby(id)


func _on_multiplayer_peer_disconnected(id: int) -> void:
	if _resetting:
		return
	players.erase(id)
	_join_order.erase(id)
	peer_disconnected.emit(id)
	if is_host:
		assign_character_types()
	else:
		lobby_changed.emit()


func _on_connected_to_server() -> void:
	if _resetting:
		return
	peer_id = multiplayer.get_unique_id()
	players.erase(0)
	if not players.has(peer_id):
		players[peer_id] = _make_player_entry(player_name, peer_id, false)
	connected.emit()
	lobby_changed.emit()
	rpc_id(1, "_rpc_register_name", player_name)


func _on_multiplayer_connection_failed() -> void:
	if _resetting:
		return
	var message := "Could not connect to %s:%d. Check the address and firewall." % [_last_address, port]
	if not web_room.is_empty():
		message = "The WebRTC room connection failed. Check the signaling URL and room code."
	_reset_transport(false)
	connection_failed.emit(message)


func _on_multiplayer_server_disconnected() -> void:
	if _resetting:
		return
	var message := "The host ended the session."
	if not web_room.is_empty():
		message = "The WebRTC host ended the room."
	_reset_transport(false)
	disconnected.emit()
	connection_failed.emit(message)


# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_name(requested_name: String) -> void:
	if _resetting or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	if not players.has(sender):
		if not _join_order.has(sender):
			_join_order.append(sender)
		players[sender] = _make_player_entry(_default_name_for(sender), sender, false)
	var entry: Dictionary = players[sender]
	entry["name"] = _clean_name(requested_name)
	if entry["name"].is_empty():
		entry["name"] = _default_name_for(sender)
	players[sender] = entry
	assign_character_types()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if _resetting or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not players.has(sender):
		return
	var entry: Dictionary = players[sender]
	entry["ready"] = ready
	players[sender] = entry
	lobby_changed.emit()
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_lobby(snapshot: Dictionary) -> void:
	if _resetting or is_host:
		return
	players.clear()
	for key in snapshot.keys():
		var id := int(key)
		var value: Dictionary = snapshot[key]
		players[id] = {
			"name": str(value.get("name", _default_name_for(id))),
			"color": value.get("color", _color_for_peer(id)),
			"ready": bool(value.get("ready", false)),
			"character_type": int(value.get("character_type", CharacterType.STRONG)),
		}
	if peer_id > 0 and not players.has(peer_id):
		players[peer_id] = _make_player_entry(player_name, peer_id, false)
	if peer_id > 0 and players.has(peer_id):
		character_type = int((players[peer_id] as Dictionary).get("character_type", CharacterType.STRONG))
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat_to_server(text: String) -> void:
	if _resetting or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_add_chat(sender, text)
	rpc("_rpc_chat_broadcast", sender, text)


@rpc("authority", "call_remote", "reliable")
func _rpc_chat_broadcast(sender: int, text: String) -> void:
	if _resetting:
		return
	_add_chat(sender, text)


@rpc("authority", "call_local", "reliable")
func _rpc_start_match(seed_value: int) -> void:
	if _match_started:
		return
	match_seed = seed_value
	_match_started = true
	match_started.emit()
	var error: Error = get_tree().change_scene_to_file(MATCH_SCENE)
	if error != OK:
		push_warning("Unable to load %s: %s" % [MATCH_SCENE, error_string(error)])


# ---------------------------------------------------------------------------
# WebRTC room callbacks
# ---------------------------------------------------------------------------

func _on_web_room_ready(assigned_id: int, room: String) -> void:
	web_room = room
	multiplayer.multiplayer_peer = _web_rtc.get_multiplayer_peer()
	peer_id = multiplayer.get_unique_id()
	if peer_id <= 0:
		peer_id = assigned_id
	if is_host:
		players[1] = _make_player_entry(player_name, 1, true)
		assign_character_types()
		hosted.emit()
	else:
		players[peer_id] = _make_player_entry(player_name, peer_id, false)
	connected.emit()
	lobby_changed.emit()


func _on_web_room_failed(message: String) -> void:
	_reset_transport(false)
	connection_failed.emit(message)


func _on_web_peer_left(left_id: int) -> void:
	if not is_host or left_id <= 1 or not players.has(left_id):
		return
	players.erase(left_id)
	peer_disconnected.emit(left_id)
	_broadcast_lobby()
	lobby_changed.emit()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for id in players:
		snapshot[id] = (players[id] as Dictionary).duplicate()
	return snapshot


func _broadcast_lobby(except_peer: int = -1) -> void:
	if not is_host or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var snapshot := _snapshot()
	for id in players:
		if id <= 1 or id == except_peer:
			continue
		rpc_id(id, "_rpc_apply_lobby", snapshot)


func _add_chat(sender: int, text: String) -> void:
	var data := player_data(sender)
	recent_chat.append({
		"peer_id": sender,
		"name": data.get("name", _default_name_for(sender)),
		"color": data.get("color", _color_for_peer(sender)),
		"message": text,
	})
	while recent_chat.size() > MAX_CHAT_ENTRIES:
		recent_chat.pop_front()
	chat_message.emit(sender, text)


func _make_player_entry(display_name: String, id: int, ready: bool) -> Dictionary:
	var clean := _clean_name(display_name)
	if clean.is_empty():
		clean = _default_name_for(id)
	var assigned := CharacterType.STRONG
	if is_host:
		if id == 1:
			assigned = CharacterType.STRONG
		else:
			var index := _join_order.find(id)
			assigned = class_for_join_index(index) if index >= 0 else CharacterType.ELASTIC
	return {
		"name": clean,
		"color": _color_for_peer(id),
		"ready": ready,
		"character_type": assigned,
	}


func _default_name_for(id: int) -> String:
	if id == 1:
		return "Host"
	if id <= 0:
		return "Unknown"
	return "Player %d" % id


func _clean_name(value: String) -> String:
	return value.strip_edges().substr(0, 24)


func _color_for_peer(id: int) -> Color:
	var index := absi(id)
	if index == 0:
		index = 7
	var hue := fmod(float(index) * 0.6180339887498949, 1.0)
	return Color.from_hsv(hue, 0.62, 0.96)


func _reset_transport(emit_disconnected: bool = false) -> void:
	if _resetting:
		return
	_resetting = true
	var was_active := multiplayer.multiplayer_peer != null

	if _enet_peer != null:
		_enet_peer.close()
		_enet_peer = null
	if _web_rtc != null:
		_web_rtc.call("close_room")
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null

	peer_id = 0
	is_host = false
	players.clear()
	_join_order.clear()
	character_type = CharacterType.STRONG
	recent_chat.clear()
	port = DEFAULT_PORT
	max_players = 4
	web_room = ""
	match_seed = 0
	_last_address = "127.0.0.1"
	_match_starting = false
	_match_started = false
	_resetting = false

	if emit_disconnected and was_active:
		disconnected.emit()
