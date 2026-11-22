extends Node
class_name WebRTCRoom

## Signaling client and WebRTC transport for browser and desktop rooms.
## The signaling server only relays JSON messages. Game packets travel directly
## over the data channels created by WebRTCMultiplayerPeer, so the host remains
## authoritative exactly as it does with ENet.

signal room_ready(peer_id: int, room: String)
signal failed(message: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal room_closed()

const SIGNAL_TIMEOUT := 12.0
const ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
]

var _socket := WebSocketPeer.new()
var _webrtc: WebRTCMultiplayerPeer = null
var _connections: Dictionary[int, WebRTCPeerConnection] = {}
var _pending_ice: Dictionary[int, Array] = {}
var _remote_ready: Dictionary[int, bool] = {}

var _signal_open := false
var _intentional_close := false
var _room := ""
var _host_mode := false
var _my_id := 0
var _max_players := 4
var _connect_elapsed := 0.0


func _ready() -> void:
	set_process(false)


## Opens a room. The local peer becomes id 1, which keeps the existing
## host-authoritative GameManager logic unchanged.
func start_host(signal_url: String, room: String, max_players: int) -> void:
	_start(signal_url, room, true, clampi(max_players, 2, 4))


## Joins an existing room. The signaling server assigns an id between 2 and 4.
func start_client(signal_url: String, room: String) -> void:
	_start(signal_url, room, false, 4)


func get_multiplayer_peer() -> WebRTCMultiplayerPeer:
	return _webrtc


func get_room() -> String:
	return _room


func close_room() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_intentional_close = true
		_send_signal({"type": "leave", "room": _room})
		_socket.close()
	elif _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_intentional_close = true
		_socket = WebSocketPeer.new()
	_drop_connections()
	_webrtc = null
	_signal_open = false
	_room = ""
	_my_id = 0
	set_process(false)
	room_closed.emit()


func _start(signal_url: String, room: String, as_host: bool, max_players: int) -> void:
	close_room()
	var url := signal_url.strip_edges()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		failed.emit("Enter a signaling URL starting with ws:// or wss://")
		return
	if OS.has_feature("web") and url.begins_with("ws://"):
		var protocol := str(JavaScriptBridge.eval("location.protocol"))
		if protocol == "https:":
			failed.emit("An HTTPS page needs a wss:// signaling URL.")
			return
	var code := room.strip_edges().to_upper()
	if code.length() < 3 or code.length() > 12:
		failed.emit("Room code must be 3 to 12 letters or digits.")
		return

	_socket = WebSocketPeer.new()
	_host_mode = as_host
	_max_players = max_players
	_room = code
	_signal_open = false
	_intentional_close = false
	_connect_elapsed = 0.0
	var error: Error = _socket.connect_to_url(url)
	if error != OK:
		failed.emit("Unable to contact the signaling server: %s" % error_string(error))
		return
	set_process(true)


func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _signal_open:
			_signal_open = true
			_connect_elapsed = 0.0
			if _host_mode:
				_send_signal({"type": "create", "room": _room, "slots": _max_players})
			else:
				_send_signal({"type": "join", "room": _room})
		while _socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = _socket.get_packet()
			_handle_signal_text(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		if not _intentional_close:
			failed.emit("Signaling connection lost.")
			set_process(false)
			return
	else:
		_connect_elapsed += delta
		if not _signal_open and _connect_elapsed >= SIGNAL_TIMEOUT:
			failed.emit("The signaling server did not answer.")
			_intentional_close = true
			_socket = WebSocketPeer.new()
			set_process(false)
			return

	for id in _connections.keys():
		var connection: WebRTCPeerConnection = _connections[int(id)]
		if connection != null:
			connection.poll()


func _handle_signal_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var kind := str(data.get("type", ""))
	match kind:
		"created", "joined":
			_on_room_assigned(data)
		"peer_joined":
			_on_peer_joined(int(data.get("id", 0)))
		"peer_left":
			_on_peer_left(int(data.get("id", 0)))
		"offer":
			_on_offer(int(data.get("from", 0)), str(data.get("sdp", "")))
		"answer":
			_on_answer(int(data.get("from", 0)), str(data.get("sdp", "")))
		"ice":
			_on_ice(int(data.get("from", 0)), data)
		"error":
			failed.emit(str(data.get("message", "Signaling server error.")))


func _on_room_assigned(data: Dictionary) -> void:
	var assigned := int(data.get("id", 0))
	if assigned < (1 if _host_mode else 2) or assigned > 4:
		failed.emit("The signaling server returned an invalid player id.")
		return
	_my_id = assigned
	_room = str(data.get("room", _room))
	_webrtc = WebRTCMultiplayerPeer.new()
	var error: Error = OK
	if _host_mode:
		error = _webrtc.create_server()
	else:
		error = _webrtc.create_client(_my_id)
	if error != OK:
		failed.emit("Unable to create the WebRTC peer: %s" % error_string(error))
		return
	room_ready.emit(_my_id, _room)
	if not _host_mode:
		_ensure_connection(1)


func _on_peer_joined(peer_id: int) -> void:
	if not _host_mode or peer_id <= 1 or peer_id == _my_id or peer_id > _max_players:
		return
	var connection := _ensure_connection(peer_id)
	if connection == null:
		return
	var error: Error = connection.create_offer()
	if error != OK:
		failed.emit("Unable to create an offer for player %d: %s" % [peer_id, error_string(error)])
		return
	peer_joined.emit(peer_id)


func _on_peer_left(peer_id: int) -> void:
	_drop_connection(peer_id)
	peer_left.emit(peer_id)
	if not _host_mode and peer_id == 1:
		failed.emit("The host left the room.")


func _on_offer(peer_id: int, sdp: String) -> void:
	if sdp.is_empty() or peer_id <= 0 or peer_id == _my_id:
		return
	var connection := _ensure_connection(peer_id)
	if connection == null:
		return
	var error: Error = connection.set_remote_description("offer", sdp)
	if error != OK:
		failed.emit("Unable to accept an offer: %s" % error_string(error))
		return
	_remote_ready[peer_id] = true
	_flush_ice(peer_id, connection)


func _on_answer(peer_id: int, sdp: String) -> void:
	if sdp.is_empty() or not _connections.has(peer_id):
		return
	var connection: WebRTCPeerConnection = _connections[peer_id]
	if connection == null:
		return
	var error: Error = connection.set_remote_description("answer", sdp)
	if error != OK:
		failed.emit("Unable to accept an answer: %s" % error_string(error))
		return
	_remote_ready[peer_id] = true
	_flush_ice(peer_id, connection)


func _on_ice(peer_id: int, data: Dictionary) -> void:
	var candidate := {
		"media": str(data.get("media", "")),
		"index": int(data.get("index", 0)),
		"name": str(data.get("name", "")),
	}
	if not _connections.has(peer_id) or not bool(_remote_ready.get(peer_id, false)):
		if not _pending_ice.has(peer_id):
			_pending_ice[peer_id] = []
		(_pending_ice[peer_id] as Array).append(candidate)
		return
	var connection: WebRTCPeerConnection = _connections[peer_id]
	if connection != null:
		connection.add_ice_candidate(str(candidate["media"]), int(candidate["index"]), str(candidate["name"]))


func _flush_ice(peer_id: int, connection: WebRTCPeerConnection) -> void:
	if not _pending_ice.has(peer_id):
		return
	for candidate in _pending_ice[peer_id]:
		var item: Dictionary = candidate
		connection.add_ice_candidate(str(item.get("media", "")), int(item.get("index", 0)), str(item.get("name", "")))
	_pending_ice.erase(peer_id)


func _ensure_connection(peer_id: int) -> WebRTCPeerConnection:
	if _connections.has(peer_id):
		return _connections[peer_id]
	if _webrtc == null:
		return null
	var connection := WebRTCPeerConnection.new()
	var error: Error = connection.initialize({"iceServers": ICE_SERVERS})
	if error != OK:
		failed.emit("Unable to initialise WebRTC: %s" % error_string(error))
		return null
	connection.session_description_created.connect(_on_session_created.bind(peer_id))
	connection.ice_candidate_created.connect(_on_ice_created.bind(peer_id))
	_connections[peer_id] = connection
	_pending_ice[peer_id] = []
	_remote_ready[peer_id] = false
	error = _webrtc.add_peer(connection, peer_id)
	if error != OK:
		failed.emit("Unable to add WebRTC peer %d: %s" % [peer_id, error_string(error)])
		return null
	return connection


func _on_session_created(kind: String, sdp: String, peer_id: int) -> void:
	var local: WebRTCPeerConnection = _connections.get(peer_id)
	if local != null:
		local.set_local_description(kind, sdp)
	_send_signal({"type": kind, "from": _my_id, "to": peer_id, "sdp": sdp})


func _on_ice_created(media: String, index: int, name: String, peer_id: int) -> void:
	_send_signal({
		"type": "ice",
		"from": _my_id,
		"to": peer_id,
		"media": media,
		"index": index,
		"name": name,
	})


func _send_signal(data: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(data))


func _drop_connection(peer_id: int) -> void:
	if _connections.has(peer_id):
		var connection: WebRTCPeerConnection = _connections[peer_id]
		if connection != null:
			connection.close()
		_connections.erase(peer_id)
	if _webrtc != null and _webrtc.has_peer(peer_id):
		_webrtc.remove_peer(peer_id)
	_pending_ice.erase(peer_id)
	_remote_ready.erase(peer_id)


func _drop_connections() -> void:
	for id in _connections.keys():
		_drop_connection(int(id))
	_connections.clear()
	_pending_ice.clear()
	_remote_ready.clear()
