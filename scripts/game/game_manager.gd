extends Node3D
class_name GameManager

## Authoritative match controller: countdown, timer, scores, respawns,
## winner, chat relay and compact 10 Hz state broadcast. There are no lives;
## falls hurt through stamina loss and a short respawn time penalty.

const HAZARD_SCRIPT = preload("res://scripts/game/hazard.gd")
const CLIMBER_SCENE := "res://scenes/climber.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MATCH_DURATION := 300.0
const STATE_INTERVAL := 0.1
const PHASE_COUNTDOWN := 0
const PHASE_ACTIVE := 1
const PHASE_ENDED := 2
const RESPAWN_PENALTY := 5.0
const FIX_REACH := 4.5
const REVIVE_REACH := 4.6
## A Strong climber launches an awake Elastic passenger with this extra arc.
## An Elastic cannot climb, so the Strong's throw is the main way to gain height.
const STRONG_THROW_FORWARD := 9.0
const STRONG_THROW_UP := 22.0

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var level: Node3D = $Level
@onready var players_root: Node3D = $Players
@onready var hud: CanvasLayer = $HUD
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var sfx: Node = $Sfx

var _phase := PHASE_COUNTDOWN
var _countdown := 3.0
var _elapsed := 0.0
var _state_timer := 0.0
var _winner_id := 0
var _end_reason := ""
var _last_countdown_beep := 99
var _local_id := 1
var _players_state: Dictionary = {}
var _climbers: Dictionary = {}
var _chat_dedupe: Dictionary = {}
var _ready_peers: Dictionary = {}
var _last_wind_message := 0
var _props: Dictionary = {}
var _items: Dictionary = {}
var _carry_links: Dictionary = {}
var _prop_state_timer := 0.0
var _carry_watchdog_timer := 0.0
var _bucket_water_stage := -1
const PROP_STATE_INTERVAL := 0.05
const PROP_PULL_INTERVAL := 0.05


func _ready() -> void:
	_local_id = int(Net.peer_id)
	if _local_id <= 0:
		_local_id = 1
	_setup_environment()
	_setup_light()
	if level.has_method("generate"):
		# The host picks one seed and sends it with the match-start RPC. Solo
		# matches get a fresh seed locally. Every peer therefore builds the same
		# procedural mountain instead of diverging per machine.
		var seed_value := int(Net.get("match_seed"))
		if seed_value <= 0:
			var seed_source := str(Net.get("web_room"))
			if seed_source.is_empty():
				seed_source = "climb-together-local"
			seed_value = 20261121 + abs(hash(seed_source)) % 100000
		level.call("generate", seed_value)
	if spawner.get_spawnable_scene_count() == 0:
		spawner.add_spawnable_scene(CLIMBER_SCENE)
	spawner.spawn_function = Callable(self, "_spawn_climber")
	players_root.child_entered_tree.connect(_on_player_entered)
	players_root.child_exiting_tree.connect(_on_player_exited)
	if level.has_signal(&"summit_touched"):
		level.connect(&"summit_touched", Callable(self, "_on_level_summit"))
	if level.has_signal(&"checkpoint_touched"):
		level.connect(&"checkpoint_touched", Callable(self, "_on_level_checkpoint"))
	if level.has_signal(&"hazard_hit"):
		level.connect(&"hazard_hit", Callable(self, "_on_level_hazard"))
	if level.has_signal(&"item_touched"):
		level.connect(&"item_touched", Callable(self, "_on_level_item_touched"))
	_index_world_objects()
	if hud.has_signal(&"chat_submitted"):
		hud.connect(&"chat_submitted", Callable(self, "_on_chat_submitted"))
	_connect_chat_signals()
	if Net.has_signal(&"peer_disconnected"):
		Net.connect(&"peer_disconnected", Callable(self, "_on_peer_disconnected"))
	if _has_network() and not _is_authority():
		rpc_id(1, "rpc_game_ready")
	_build_players_state()
	_spawn_all_players()
	_push_state_to_hud()


func _index_world_objects() -> void:
	_props.clear()
	_items.clear()
	for node in get_tree().get_nodes_in_group("climb_props"):
		var key := str(node.get("prop_id"))
		if not key.is_empty():
			_props[key] = node
	for node in get_tree().get_nodes_in_group("climb_items"):
		var key := str(node.get("item_id"))
		if not key.is_empty():
			_items[key] = node


func _setup_environment() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.055, 0.085, 0.19)
	sky_material.sky_horizon_color = Color(0.38, 0.46, 0.63)
	sky_material.sky_curve = 0.28
	sky_material.ground_bottom_color = Color(0.05, 0.06, 0.10)
	sky_material.ground_horizon_color = Color(0.24, 0.27, 0.36)
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.12
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.15
	environment.tonemap_white = 1.1
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.36, 0.43, 0.58)
	environment.fog_density = 0.0045
	environment.fog_sun_scatter = 0.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.12
	world_environment.environment = environment


func _setup_light() -> void:
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 240.0
	sun.rotation_degrees = Vector3(-43.0, 37.0, 0.0)


func _has_network() -> bool:
	if multiplayer == null:
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return true


func _is_authority() -> bool:
	return bool(Net.is_host) or not _has_network()


func _new_player_state(pid: int, display_name: String, color: Color) -> Dictionary:
	return {
		"peer_id": pid,
		"name": display_name,
		"color": color,
		"highest_y": 0.0,
		"checkpoint_y": 0.0,
		"penalty": 0.0,
		"score": 0
	}


func _build_players_state() -> void:
	_players_state.clear()
	var roster: Variant = Net.get("players")
	if roster is Dictionary and not (roster as Dictionary).is_empty():
		var dictionary: Dictionary = roster
		for key in dictionary.keys():
			var pid := int(key)
			var info: Dictionary = {}
			var value: Variant = dictionary[key]
			if value is Dictionary:
				info = value
			var color_value: Variant = info.get("color", Color.from_hsv(float(pid) * 0.27, 0.65, 0.95))
			var color := Color.WHITE
			if color_value is Color:
				color = color_value
			_players_state[pid] = _new_player_state(pid, str(info.get("name", "Climber %d" % pid)), color)
	else:
		var name_value: Variant = Net.get("player_name")
		var text := str(name_value)
		if text.is_empty():
			text = "Solo Climber"
		_players_state[_local_id] = _new_player_state(_local_id, text, Color(0.3, 0.8, 1.0))


func _spawn_all_players() -> void:
	if not _is_authority():
		return
	for key in _players_state.keys():
		var pid := int(key)
		var node: Node = null
		if _has_network():
			node = spawner.spawn(pid)
		if node == null:
			node = _spawn_climber(pid)
			players_root.add_child(node)


func _spawn_climber(data: Variant) -> Node:
	var pid := int(data)
	var info: Dictionary = {}
	var roster: Variant = Net.get("players")
	if roster is Dictionary:
		var dictionary: Dictionary = roster
		if dictionary.has(pid):
			var value: Variant = dictionary[pid]
			if value is Dictionary:
				info = value
	var color_value: Variant = info.get("color", Color.from_hsv(float(pid) * 0.27, 0.65, 0.95))
	var color := Color.WHITE
	if color_value is Color:
		color = color_value
	var packed := load(CLIMBER_SCENE) as PackedScene
	if packed == null:
		return null
	var climber := packed.instantiate()
	var character_value := int(info.get("character_type", CharacterType.STRONG))
	if not CharacterType.is_valid(character_value):
		character_value = CharacterType.STRONG
	climber.call("configure", pid, str(info.get("name", "Climber %d" % pid)), color, character_value)
	if climber.has_method("set_persistent_unconscious"):
		climber.call("set_persistent_unconscious", _has_network())
	climber.set("peer_id", pid)
	climber.set("summit_y", 142.0)
	climber.set_multiplayer_authority(pid)
	var slot := 0
	for key in _players_state.keys():
		if int(key) == pid:
			break
		slot += 1
	var spawn_point: Vector3 = level.call("get_spawn_point", slot)
	climber.set("position", spawn_point)
	climber.set("replicated_position", spawn_point)
	climber.name = "Climber_%d" % pid
	return climber


func _on_player_entered(node: Node) -> void:
	if not node.has_method("get_state"):
		return
	var id_value: Variant = node.get("peer_id")
	var pid := int(id_value)
	if pid <= 0 or _climbers.has(pid):
		return
	_climbers[pid] = node
	if not _players_state.has(pid):
		var name_value: Variant = node.get("display_name")
		_players_state[pid] = _new_player_state(pid, str(name_value), Color(0.72, 0.82, 1.0))
	_connect_climber_signals(node, pid)
	if pid == _local_id:
		hud.call("bind_local_climber", node)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_player_exited(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var id_value: Variant = node.get("peer_id")
	var pid := int(id_value)
	if _climbers.get(pid) == node:
		_climbers.erase(pid)


func _connect_climber_signals(climber: Node, pid: int) -> void:
	if climber.has_signal(&"died"):
		if HAZARD_SCRIPT.signal_arg_count(climber, &"died") > 0:
			climber.connect(&"died", Callable(self, "_on_climber_died").bind(pid))
		else:
			climber.connect(&"died", Callable(self, "_on_climber_died_no_reason").bind(pid))
	if climber.has_signal(&"checkpoint_reached"):
		if HAZARD_SCRIPT.signal_arg_count(climber, &"checkpoint_reached") > 0:
			climber.connect(&"checkpoint_reached", Callable(self, "_on_climber_checkpoint").bind(pid))
		else:
			climber.connect(&"checkpoint_reached", Callable(self, "_on_climber_checkpoint_no_height").bind(pid))
	if climber.has_signal(&"summit_reached"):
		if HAZARD_SCRIPT.signal_arg_count(climber, &"summit_reached") > 0:
			climber.connect(&"summit_reached", Callable(self, "_on_climber_summit_arg"))
		else:
			climber.connect(&"summit_reached", Callable(self, "_on_climber_summit_no_arg").bind(pid))
	if pid != _local_id:
		return
	if climber.has_signal(&"ragdoll_started"):
		climber.connect(&"ragdoll_started", Callable(self, "_on_local_ragdoll_started"))
	if climber.has_signal(&"ragdoll_ended"):
		climber.connect(&"ragdoll_ended", Callable(self, "_on_local_ragdoll_ended"))
	if climber.has_signal(&"stretch_changed"):
		if HAZARD_SCRIPT.signal_arg_count(climber, &"stretch_changed") >= 2:
			climber.connect(&"stretch_changed", Callable(self, "_on_local_stretch_changed"))
		else:
			climber.connect(&"stretch_changed", Callable(self, "_on_local_stretch_changed_one"))
	if climber.has_signal(&"anchor_changed"):
		if HAZARD_SCRIPT.signal_arg_count(climber, &"anchor_changed") > 0:
			climber.connect(&"anchor_changed", Callable(self, "_on_local_anchor_changed_arg"))
		else:
			climber.connect(&"anchor_changed", Callable(self, "_on_local_anchor_changed"))
	if climber.has_signal(&"notice_requested"):
		climber.connect(&"notice_requested", Callable(self, "_on_local_notice"))
	if climber.has_signal(&"carry_changed"):
		climber.connect(&"carry_changed", Callable(self, "_on_local_carry_changed"))
	if climber.has_signal(&"jetpack_changed"):
		climber.connect(&"jetpack_changed", Callable(self, "_on_local_jetpack_changed"))


func _on_local_carry_changed(kind: int, target_id: String) -> void:
	if kind == -1:
		hud.call("push_event", "OBJECT RELEASED")
		return
	var object_name := target_id.to_upper()
	if kind == 0:
		var prop: Node = _props.get(target_id)
		if prop != null:
			object_name = str(prop.get("display_name")).to_upper()
	hud.call("push_event", "HOLDING %s" % object_name)
	_play_fx("anchor", -10.0)


func _on_local_jetpack_changed(equipped: bool, fuel: float) -> void:
	if equipped and fuel > 0.0:
		_play_fx("go", -7.0)


func _on_climber_died(reason: Variant, pid: int) -> void:
	_handle_death(str(reason), pid)


func _on_climber_died_no_reason(pid: int) -> void:
	_handle_death("FALL", pid)


func _handle_death(reason: String, pid: int) -> void:
	if not _is_authority() or _phase != PHASE_ACTIVE:
		return
	var entry: Dictionary = _players_state.get(pid, {})
	if entry.is_empty():
		return
	entry["penalty"] = float(entry.get("penalty", 0.0)) + RESPAWN_PENALTY
	_authorize_drop(pid)
	_notify("%s is out (%s)  +%.0f s" % [str(entry.get("name", "Climber")), reason, RESPAWN_PENALTY])
	_play_fx("fall", -4.0)
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(_respawn_after_delay.bind(pid))


func _respawn_after_delay(pid: int) -> void:
	if not _players_state.has(pid):
		return
	var entry: Dictionary = _players_state[pid]
	var climber: Node = _climbers.get(pid)
	if climber == null or not climber.has_method("respawn_at"):
		return
	var position: Vector3 = level.call("get_checkpoint_position", float(entry.get("checkpoint_y", 0.0)))
	climber.call("respawn_at", position, false)
	_notify("%s respawned at %.0f m" % [str(entry.get("name", "Climber")), position.y])


func _on_climber_checkpoint(height: Variant, pid: int) -> void:
	_register_checkpoint(float(height), pid)


func _on_climber_checkpoint_no_height(pid: int) -> void:
	_register_checkpoint(0.0, pid)


func _on_level_checkpoint(height: float, body: Node) -> void:
	var id_value: Variant = body.get("peer_id")
	_register_checkpoint(height, int(id_value))


func _register_checkpoint(height: float, pid: int) -> void:
	if not _is_authority() or not _players_state.has(pid):
		return
	var entry: Dictionary = _players_state[pid]
	if height <= float(entry.get("checkpoint_y", 0.0)):
		return
	entry["checkpoint_y"] = height
	_notify("%s reached the %.0f m checkpoint" % [str(entry.get("name", "Climber")), height])
	_play_fx("checkpoint", -4.0)


func _on_climber_summit_arg(arg: Variant) -> void:
	var pid := -1
	if arg is int:
		pid = int(arg)
	elif arg is Dictionary:
		pid = int((arg as Dictionary).get("peer_id", -1))
	elif arg is Node:
		var id_value: Variant = (arg as Node).get("peer_id")
		pid = int(id_value)
	if pid < 0:
		pid = _local_id
	_on_summit_for_peer(pid)


func _on_climber_summit_no_arg(pid: int) -> void:
	_on_summit_for_peer(pid)


func _on_level_summit(body: Node) -> void:
	var id_value: Variant = body.get("peer_id")
	_on_summit_for_peer(int(id_value))


func _on_summit_for_peer(pid: int) -> void:
	if not _is_authority() or _phase != PHASE_ACTIVE:
		return
	var entry: Dictionary = _players_state.get(pid, {})
	if entry.is_empty():
		return
	entry["highest_y"] = maxf(float(entry.get("highest_y", 0.0)), 142.0)
	_notify("SUMMIT! FIND THE WATER BUCKET")


func _find_climber_by_id(pid: int) -> Node:
	var node: Variant = _climbers.get(pid)
	if node is Node and is_instance_valid(node):
		return node
	return null


func is_strong_climber(climber: Node) -> bool:
	return climber != null and int(climber.get("character_type")) == CharacterType.STRONG


func is_elastic_climber(climber: Node) -> bool:
	return climber != null and int(climber.get("character_type")) == CharacterType.ELASTIC


func _find_tail_by_owner(pid: int) -> Node:
	for tail in get_tree().get_nodes_in_group("climb_tails"):
		if int(tail.get("owner_peer_id")) == pid:
			return tail
	return null


func _peer_of_sender(sender: int) -> int:
	if sender > 0:
		return sender
	return _local_id


func request_carry(kind: int, target_id: String) -> void:
	if _is_authority():
		_authorize_carry(_local_id, kind, target_id)
		return
	rpc_id(1, "rpc_request_carry", kind, target_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_carry(kind: int, target_id: String) -> void:
	_authorize_carry(_peer_of_sender(multiplayer.get_remote_sender_id()), kind, target_id)


func _authorize_carry(carrier_pid: int, kind: int, target_id: String) -> void:
	if not _is_authority() or _phase == PHASE_ENDED:
		return
	var carrier: Node = _find_climber_by_id(carrier_pid)
	if carrier == null or bool(carrier.get("dead")) or bool(carrier.get("ragdoll_active")):
		return
	if int(carrier.get("carried_by_peer")) > 0:
		return
	if _carry_links.has(carrier_pid):
		_clear_carry_link(carrier_pid, false)

	if kind == 0:
		var prop: Node = _props.get(target_id)
		if prop == null or int(prop.get("carrier_id")) != 0:
			_notify("OBJECT UNAVAILABLE")
			return
		if bool(prop.get("is_fixed")):
			_notify("OBJECT IS FIXED - RELEASE IT FIRST")
			return
	elif kind == 1:
		var target_pid := int(target_id)
		var target: Node = _find_climber_by_id(target_pid)
		if target == null or target_pid == carrier_pid or bool(target.get("dead")):
			_notify("CLIMBER UNAVAILABLE")
			return
		# Any class can move a downed teammate. An awake climber can only be
		# lifted by a Strong carrying an Elastic, which enables the high throw.
		if not bool(target.get("unconscious")):
			if int(carrier.get("character_type")) != CharacterType.STRONG or int(target.get("character_type")) != CharacterType.ELASTIC:
				_notify("ONLY STRONG CAN CARRY AN AWAKE ELASTIC")
				return
		# A teammate must press F to grab and F again (or the passenger) to drop.
		if int(target.get("carried_by_peer")) > 0:
			_notify("CLIMBER ALREADY CARRIED")
			return
		if _carry_links.has(target_pid):
			_clear_carry_link(target_pid, true)
	elif kind == 2:
		var owner_pid := int(target_id)
		var owner: Node = _find_climber_by_id(owner_pid)
		var tail: Node = _find_tail_by_owner(owner_pid)
		if owner == null or tail == null or owner_pid == carrier_pid:
			_notify("TAIL UNAVAILABLE")
			return
		if tail.has_method("can_be_grappled") and not bool(tail.call("can_be_grappled")):
			_notify("THAT CLIMBER HAS NO ROPE TAIL")
			return
		if int(tail.get("carrier_id")) != 0:
			_notify("TAIL ALREADY CARRIED")
			return
	else:
		return

	_apply_carry_link(carrier_pid, kind, target_id)
	_broadcast_carry_link(carrier_pid, kind, target_id)


## Coop build step: one climber carries a plank or crate while a teammate
## anchors it as a temporary platform. The reverse action releases it.
func request_fix_prop(prop_id: String) -> void:
	if _is_authority():
		_authorize_fix(_local_id, prop_id)
		return
	rpc_id(1, "rpc_request_fix", prop_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_fix(prop_id: String) -> void:
	_authorize_fix(_peer_of_sender(multiplayer.get_remote_sender_id()), prop_id)


func _authorize_fix(fixer_pid: int, prop_id: String) -> void:
	if not _is_authority() or _phase == PHASE_ENDED:
		return
	var fixer: Node = _find_climber_by_id(fixer_pid)
	if fixer == null or bool(fixer.get("dead")) or bool(fixer.get("ragdoll_active")):
		return
	var prop: Node = _props.get(prop_id)
	if prop == null or int(prop.get("kind")) == ClimbProp.Kind.BUCKET:
		_notify("THIS OBJECT CANNOT BE FIXED")
		return
	var carrier_pid := int(prop.get("carrier_id"))
	if carrier_pid == fixer_pid:
		_notify("A TEAMMATE MUST HOLD IT WHILE YOU FIX")
		return
	if fixer.global_position.distance_to(prop.global_position) > FIX_REACH:
		_notify("TOO FAR TO FIX")
		return
	var next_value: bool = not bool(prop.get("is_fixed"))
	if next_value and carrier_pid > 0 and _carry_links.has(carrier_pid):
		_clear_carry_link(carrier_pid, true)
	prop.call("set_fixed", next_value)
	_broadcast_prop_fixed(prop_id, next_value)
	var verb := "FIXED" if next_value else "RELEASED"
	_notify("%s %s" % [str(prop.get("display_name")).to_upper(), verb])


func _broadcast_prop_fixed(prop_id: String, value: bool) -> void:
	if not _has_network() or not _is_authority():
		return
	for pid in _remote_targets():
		rpc_id(pid, "rpc_apply_prop_fixed", prop_id, value)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_prop_fixed(prop_id: String, value: bool) -> void:
	var prop: Node = _props.get(prop_id)
	if prop != null and prop.has_method("set_fixed"):
		prop.call("set_fixed", value)


## Strong player throws an awake Elastic passenger in the camera direction.
## The normal F drop stays gentle; Q calls this dedicated RPC instead.
func request_throw_elastic(carrier_pid: int) -> void:
	if not _is_authority():
		rpc_id(1, "rpc_request_throw_elastic", carrier_pid)
		return
	var link: Dictionary = _carry_links.get(carrier_pid, {})
	if int(link.get("kind", -1)) != 1:
		return
	var carrier: Node = _find_climber_by_id(carrier_pid)
	var target: Node = _find_climber_by_id(int(link.get("target_id", -1)))
	if (
		carrier == null or target == null
		or not is_strong_climber(carrier)
		or not is_elastic_climber(target)
		or bool(target.get("unconscious"))
	):
		return
	_clear_carry_link(carrier_pid, true)
	_notify("ELASTIC THROWN")


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_throw_elastic(carrier_pid: int) -> void:
	_authorize_throw_elastic(_peer_of_sender(multiplayer.get_remote_sender_id()), carrier_pid)


func _authorize_throw_elastic(sender_pid: int, carrier_pid: int) -> void:
	if not _is_authority() or sender_pid != carrier_pid:
		return
	if not _carry_links.has(carrier_pid):
		return
	var carrier: Node = _find_climber_by_id(carrier_pid)
	var link: Dictionary = _carry_links[carrier_pid]
	var target: Node = _find_climber_by_id(int(link.get("target_id", -1)))
	if (
		carrier == null or target == null
		or not is_strong_climber(carrier)
		or not is_elastic_climber(target)
		or bool(target.get("unconscious"))
	):
		return
	_clear_carry_link(carrier_pid, true)
	_notify("ELASTIC THROWN")


func request_drop() -> void:
	if _is_authority():
		_authorize_drop(_local_id)
		return
	rpc_id(1, "rpc_request_drop")


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_drop() -> void:
	_authorize_drop(_peer_of_sender(multiplayer.get_remote_sender_id()))


func _authorize_drop(pid: int) -> void:
	if not _is_authority():
		return
	if _carry_links.has(pid):
		_clear_carry_link(pid, true)
		return
	for key in _carry_links.keys():
		var link: Dictionary = _carry_links[key]
		if int(link.get("kind", -1)) == 1 and str(link.get("target_id", "")) == str(pid):
			_clear_carry_link(int(key), true)
			break
	var climber: Node = _find_climber_by_id(pid)
	if climber != null and int(climber.get("carried_by_peer")) > 0:
		var carrier_pid := int(climber.get("carried_by_peer"))
		if _carry_links.has(carrier_pid):
			_clear_carry_link(carrier_pid, true)


func request_bandage_revive(target_pid: int) -> void:
	if _is_authority():
		_authorize_bandage_revive(_local_id, target_pid)
		return
	rpc_id(1, "rpc_request_bandage_revive", target_pid)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_bandage_revive(target_pid: int) -> void:
	_authorize_bandage_revive(_peer_of_sender(multiplayer.get_remote_sender_id()), target_pid)


func _authorize_bandage_revive(helper_pid: int, target_pid: int) -> void:
	if not _is_authority() or _phase == PHASE_ENDED:
		return
	var helper: Node = _find_climber_by_id(helper_pid)
	var target: Node = _find_climber_by_id(target_pid)
	if helper == null or target == null or helper_pid == target_pid:
		return
	if bool(helper.get("dead")) or bool(helper.get("ragdoll_active")) or int(helper.get("carried_by_peer")) > 0:
		return
	if bool(target.get("dead")) or not bool(target.get("unconscious")):
		_notify("NO DOWNED TEAMMATE")
		return
	var carrier_pid := int(target.get("carried_by_peer"))
	if carrier_pid != 0 and carrier_pid != helper_pid:
		_notify("TEAMMATE ALREADY CARRIED")
		return
	if helper.global_position.distance_to(target.global_position) > REVIVE_REACH:
		_notify("TOO FAR TO REVIVE")
		return
	if _carry_links.has(helper_pid):
		var link: Dictionary = _carry_links[helper_pid]
		if int(link.get("kind", -1)) == 1 and str(link.get("target_id", "")) == str(target_pid):
			_clear_carry_link(helper_pid, true)
	_apply_bandage_revive(target_pid, helper_pid)
	_broadcast_bandage_revive(target_pid, helper_pid)


func _apply_bandage_revive(target_pid: int, helper_pid: int) -> void:
	var target: Node = _find_climber_by_id(target_pid)
	if target != null and target.has_method("revive_with_bandage"):
		target.call("revive_with_bandage", helper_pid)
	if helper_pid == _local_id:
		_notify("TEAMMATE REVIVED")


func _broadcast_bandage_revive(target_pid: int, helper_pid: int) -> void:
	if not _has_network() or not _is_authority():
		return
	for pid in _remote_targets():
		rpc_id(pid, "rpc_apply_bandage_revive", target_pid, helper_pid)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_bandage_revive(target_pid: int, helper_pid: int) -> void:
	_apply_bandage_revive(target_pid, helper_pid)


func _apply_carry_link(carrier_pid: int, kind: int, target_id: String) -> void:
	var carrier: Node = _find_climber_by_id(carrier_pid)
	if kind == -1:
		if carrier != null and carrier.has_method("set_carry"):
			carrier.call("set_carry", -1, "")
		return
	if carrier == null or not carrier.has_method("set_carry"):
		return

	if kind == 0:
		var prop: Node = _props.get(target_id)
		if prop != null and prop.has_method("set_carrier"):
			prop.call("set_carrier", carrier_pid)
	elif kind == 1:
		var target: Node = _find_climber_by_id(int(target_id))
		if target != null and target.has_method("set_carried_by"):
			target.call("set_carried_by", carrier_pid)
	elif kind == 2:
		var tail: Node = _find_tail_by_owner(int(target_id))
		if tail != null and tail.has_method("set_carrier"):
			tail.call("set_carrier", carrier_pid)

	carrier.call("set_carry", kind, target_id)
	_carry_links[carrier_pid] = {"kind": kind, "target_id": target_id}


func _clear_carry_link(carrier_pid: int, broadcast: bool) -> void:
	var link: Dictionary = _carry_links.get(carrier_pid, {})
	_carry_links.erase(carrier_pid)
	if broadcast and _has_network() and _is_authority():
		_broadcast_carry_link(carrier_pid, -1, "")

	var carrier: Node = _find_climber_by_id(carrier_pid)
	if carrier != null and carrier.has_method("set_carry"):
		carrier.call("set_carry", -1, "")
	if link.is_empty():
		return
	var kind := int(link.get("kind", -1))
	var target_id := str(link.get("target_id", ""))
	if kind == 0:
		var prop: Node = _props.get(target_id)
		if prop != null and prop.has_method("set_carrier"):
			prop.call("set_carrier", 0)
	elif kind == 1:
		var target: Node = _find_climber_by_id(int(target_id))
		if target != null and target.has_method("set_carried_by"):
			target.call("set_carried_by", 0)
			if (
				carrier != null
				and is_strong_climber(carrier)
				and is_elastic_climber(target)
				and not bool(target.get("unconscious"))
				and target.has_method("launch_from_carry")
			):
				var throw_dir := Vector3.FORWARD
				var camera: Camera3D = carrier.get_node_or_null("CameraPivot/Camera3D") as Camera3D
				if camera != null:
					throw_dir = -camera.global_transform.basis.z.normalized()
				else:
					throw_dir = -carrier.global_transform.basis.z.normalized()
				throw_dir.y = 0.0
				if throw_dir.length_squared() < 0.001:
					throw_dir = Vector3.FORWARD
				var velocity: Vector3 = (
					carrier.linear_velocity
					+ throw_dir.normalized() * STRONG_THROW_FORWARD
					+ (Vector3.UP * STRONG_THROW_UP)
				)
				target.call("launch_from_carry", velocity)
				if _has_network() and _is_authority():
					target.rpc("rpc_carry_launch", velocity)
				_notify("ELASTIC LAUNCHED")
	elif kind == 2:
		var tail: Node = _find_tail_by_owner(int(target_id))
		if tail != null and tail.has_method("set_carrier"):
			var throw_dir := Vector3.FORWARD
			var throw_origin := Vector3.ZERO
			if carrier != null:
				throw_dir = -carrier.global_transform.basis.z.normalized()
				throw_dir.y = 0.0
				throw_origin = carrier.linear_velocity
				if throw_dir.length_squared() < 0.001:
					throw_dir = Vector3.FORWARD
			var velocity: Vector3 = throw_origin + throw_dir.normalized() * 12.0 + (Vector3.UP * 4.5)
			tail.call("set_carrier", 0, velocity)


func _broadcast_carry_link(carrier_pid: int, kind: int, target_id: String) -> void:
	if not _has_network() or not _is_authority():
		return
	for pid in _remote_targets():
		rpc_id(pid, "rpc_apply_carry", carrier_pid, kind, target_id)


@rpc("authority", "call_remote", "reliable")
func rpc_apply_carry(carrier_pid: int, kind: int, target_id: String) -> void:
	if kind == -1:
		_clear_carry_link(carrier_pid, false)
		return
	_apply_carry_link(carrier_pid, kind, target_id)


func _check_carry_links() -> void:
	if not _is_authority():
		return
	for key in _carry_links.keys():
		var carrier_pid := int(key)
		var link: Dictionary = _carry_links[carrier_pid]
		var carrier: Node = _find_climber_by_id(carrier_pid)
		if carrier == null or bool(carrier.get("dead")) or bool(carrier.get("ragdoll_active")):
			_clear_carry_link(carrier_pid, true)
			continue
		var kind := int(link.get("kind", -1))
		if kind == 0:
			var prop: Node = _props.get(str(link.get("target_id", "")))
			if prop == null or int(prop.get("carrier_id")) != carrier_pid or bool(prop.get("is_fixed")):
				_clear_carry_link(carrier_pid, true)
		elif kind == 1:
			var target: Node = _find_climber_by_id(int(link.get("target_id", "0")))
			if target == null or bool(target.get("dead")) or int(target.get("carried_by_peer")) != carrier_pid:
				_clear_carry_link(carrier_pid, true)
		elif kind == 2:
			var tail: Node = _find_tail_by_owner(int(link.get("target_id", "0")))
			if tail == null or int(tail.get("carrier_id")) != carrier_pid:
				_clear_carry_link(carrier_pid, true)


func _on_level_item_touched(item_id: String, body: Node) -> void:
	if not _is_authority():
		rpc_id(1, "rpc_request_item", item_id)
		return
	var pid := int(body.get("peer_id"))
	_authorize_item(pid, item_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_item(item_id: String) -> void:
	_authorize_item(_peer_of_sender(multiplayer.get_remote_sender_id()), item_id)


func _authorize_item(receiver_id: int, item_id: String) -> void:
	if not _is_authority() or _phase == PHASE_ENDED:
		return
	var item: Node = _items.get(item_id)
	if item == null or bool(item.get("taken")):
		return
	var receiver: Node = _find_climber_by_id(receiver_id)
	if receiver == null or bool(receiver.get("dead")):
		return
	var amount := float(item.get("fuel_amount"))
	_apply_item_taken(item_id, receiver_id, amount)
	if _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "rpc_item_taken", item_id, receiver_id, amount)


func _apply_item_taken(item_id: String, receiver_id: int, amount: float) -> void:
	var item: Node = _items.get(item_id)
	if item != null and item.has_method("set_taken"):
		item.call("set_taken", true)
	if receiver_id != _local_id:
		return
	var receiver: Node = _find_climber_by_id(receiver_id)
	if receiver == null:
		return
	var kind := 0
	if item != null:
		var kind_value: Variant = item.get("item_kind")
		if kind_value != null:
			kind = int(kind_value)
	if kind == ClimbItemPickup.Kind.BANDAGE:
		if receiver.has_method("add_bandage"):
			receiver.call("add_bandage", int(amount))
	else:
		if receiver.has_method("equip_jetpack"):
			receiver.call("equip_jetpack", amount)


@rpc("authority", "call_remote", "reliable")
func rpc_item_taken(item_id: String, receiver_id: int, amount: float) -> void:
	_apply_item_taken(item_id, receiver_id, amount)


func report_carried_prop(prop_id: String, transform_value: Transform3D, linear_value: Vector3, angular_value: Vector3, water_value: float = -1.0) -> void:
	if _is_authority():
		_apply_carried_prop(_local_id, prop_id, transform_value, linear_value, angular_value, water_value)
		return
	rpc_id(1, "rpc_report_carried_prop", prop_id, transform_value, linear_value, angular_value, water_value)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_report_carried_prop(prop_id: String, transform_value: Transform3D, linear_value: Vector3, angular_value: Vector3, water_value: float = -1.0) -> void:
	_apply_carried_prop(_peer_of_sender(multiplayer.get_remote_sender_id()), prop_id, transform_value, linear_value, angular_value, water_value)


func _apply_carried_prop(carrier_pid: int, prop_id: String, transform_value: Transform3D, linear_value: Vector3, angular_value: Vector3, water_value: float = -1.0) -> void:
	if not _is_authority():
		return
	var prop: Node = _props.get(prop_id)
	if prop == null or int(prop.get("carrier_id")) != carrier_pid:
		return
	prop.call("apply_state", transform_value, linear_value, angular_value)
	if water_value >= 0.0 and prop.has_method("set_water"):
		prop.call("set_water", water_value)


func report_prop_pull(prop_id: String, force: Vector3) -> void:
	if _is_authority():
		_apply_prop_pull(_local_id, prop_id, force)
		return
	rpc_id(1, "rpc_report_prop_pull", prop_id, force)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_report_prop_pull(prop_id: String, force: Vector3) -> void:
	_apply_prop_pull(_peer_of_sender(multiplayer.get_remote_sender_id()), prop_id, force)


func _apply_prop_pull(puller_pid: int, prop_id: String, force: Vector3) -> void:
	if not _is_authority() or _phase == PHASE_ENDED:
		return
	var prop: Node = _props.get(prop_id)
	if prop == null or not prop.has_method("apply_pull_impulse") or not prop.has_method("can_be_grappled"):
		return
	if not bool(prop.call("can_be_grappled")):
		return
	var puller := _find_climber_by_id(puller_pid)
	if puller == null or bool(puller.get("dead")) or bool(puller.get("ragdoll_active")):
		return
	if puller.global_position.distance_to(prop.global_position) > 40.0:
		return
	var impulse: Vector3 = force * PROP_PULL_INTERVAL
	if impulse.length() > 65.0:
		impulse = impulse.normalized() * 65.0
	prop.call("apply_pull_impulse", impulse)


func _broadcast_prop_states() -> void:
	if not _is_authority() or not _has_network():
		return
	var states: Array = []
	for key in _props.keys():
		var prop: Node = _props[key]
		if prop == null or not is_instance_valid(prop):
			continue
		var packed: Variant = prop.call("pack_state")
		if packed is Array:
			states.append(packed)
	var chunk: Array = []
	for state in states:
		chunk.append(state)
		if chunk.size() >= 5:
			_broadcast_prop_chunk(chunk)
			chunk = []
	if not chunk.is_empty():
		_broadcast_prop_chunk(chunk)


func _broadcast_prop_chunk(chunk: Array) -> void:
	for pid in _remote_targets():
		rpc_id(pid, "rpc_prop_states", chunk)


@rpc("authority", "call_remote", "unreliable")
func rpc_prop_states(states: Array) -> void:
	for state in states:
		if not state is Array:
			continue
		var fields: Array = state
		if fields.size() < 4:
			continue
		var prop: Node = _props.get(str(fields[0]))
		if prop != null and prop.has_method("apply_state"):
			var fixed_value: bool = bool(fields[5]) if fields.size() >= 6 else false
			prop.call("apply_state", fields[1], fields[2], fields[3], fixed_value)
			if fields.size() >= 5 and prop.has_method("set_water"):
				prop.call("set_water", float(fields[4]))


func _on_level_hazard(kind: int, hazard_label: String, body: Node) -> void:
	if kind == HAZARD_SCRIPT.Type.WIND and _is_authority():
		var id_value: Variant = body.get("peer_id")
		if int(id_value) == _local_id and Time.get_ticks_msec() - _last_wind_message > 4000:
			_last_wind_message = Time.get_ticks_msec()
			_notify("WIND GUST - brace yourself!")
	elif kind == HAZARD_SCRIPT.Type.BRITTLE and _is_authority():
		_notify(hazard_label)
	elif kind == HAZARD_SCRIPT.Type.ENEMY and _is_authority():
		if int(body.get("peer_id")) == _local_id:
			_notify("ENEMY STRIKE - use a bandage")
			_play_fx("warning", -6.0)


func _on_local_ragdoll_started() -> void:
	_play_fx("ragdoll", -2.0)


func _on_local_ragdoll_ended() -> void:
	_play_fx("recover", -3.0)


var _stretch_warned := false


func _on_local_stretch_changed(value: Variant, overloaded: Variant) -> void:
	var is_overloaded := bool(overloaded) or float(value) >= 0.99
	if is_overloaded and not _stretch_warned:
		_play_fx("stretch_warning", -6.0)
	_stretch_warned = is_overloaded


func _on_local_stretch_changed_one(value: Variant) -> void:
	_on_local_stretch_changed(value, false)


func _on_local_anchor_changed_arg(_arg: Variant) -> void:
	_play_fx("anchor", -9.0)


func _on_local_anchor_changed() -> void:
	_play_fx("anchor", -9.0)


func _on_local_notice(text: String) -> void:
	var key := text.to_upper()
	var sound := ""
	match key:
		"LOW STAMINA", "EXHAUSTED":
			sound = "warning"
		"WIND GUST":
			sound = "shoot"
		"BRITTLE HOLD", "HOLD SNAPPED":
			sound = "ragdoll"
	if not sound.is_empty():
		sfx.call("play", sound, -8.0)
	hud.call("push_event", text)


func _process(delta: float) -> void:
	if _is_authority():
		match _phase:
			PHASE_COUNTDOWN:
				_countdown -= delta
				var shown := ceili(_countdown)
				if shown != _last_countdown_beep and shown > 0:
					_last_countdown_beep = shown
					_play_fx("countdown", -3.0)
				if _countdown <= 0.0:
					_countdown = 0.0
					_phase = PHASE_ACTIVE
					_notify("GO! CLIMB!")
					_play_fx("go", -1.0)
					_show_go()
			PHASE_ACTIVE:
				_elapsed += delta
				_update_altitudes()
				_update_water_objective()
				if _elapsed >= MATCH_DURATION:
					_finish_match(_best_player_id(), "TIME UP")
			PHASE_ENDED:
				pass
		_state_timer += delta
		if _state_timer >= STATE_INTERVAL:
			_state_timer = 0.0
			_broadcast_state()
		_prop_state_timer += delta
		if _prop_state_timer >= PROP_STATE_INTERVAL:
			_prop_state_timer = 0.0
			_broadcast_prop_states()
		_carry_watchdog_timer += delta
		if _carry_watchdog_timer >= 0.25:
			_carry_watchdog_timer = 0.0
			_check_carry_links()
	_push_state_to_hud()


func _update_altitudes() -> void:
	for key in _climbers.keys():
		var entry: Dictionary = _players_state.get(key, {})
		if entry.is_empty():
			continue
		var climber: Node = _climbers[key]
		if not is_instance_valid(climber) or not climber.is_inside_tree():
			_climbers.erase(key)
			continue
		var altitude := maxf(0.0, float(climber.get("highest_y")) - 2.0)
		if altitude <= 0.0:
			var position_value: Variant = climber.get("global_position")
			if position_value is Vector3:
				altitude = maxf(0.0, (position_value as Vector3).y - 2.0)
		if altitude > float(entry.get("highest_y", 0.0)):
			entry["highest_y"] = altitude


func _update_water_objective() -> void:
	var bucket: Node = _props.get("bucket_0")
	if bucket == null or not is_instance_valid(bucket):
		return
	var water := maxf(0.0, float(bucket.get("water")))
	var stage := ceili(water / 25.0)
	if stage != _bucket_water_stage:
		_bucket_water_stage = stage
		_notify("WATER %d%%" % int(water))
		if water <= 0.0:
			_notify("THE BUCKET IS EMPTY!")
	var house: Vector3 = level.call("get_house_position")
	for key in _carry_links.keys():
		var link: Dictionary = _carry_links[key]
		if str(link.get("target_id", "")) != "bucket_0":
			continue
		var carrier_pid := int(key)
		var carrier := _find_climber_by_id(carrier_pid)
		if carrier == null:
			continue
		var position_value: Variant = carrier.get("global_position")
		if not position_value is Vector3:
			continue
		var carrier_position: Vector3 = position_value
		if water > 0.0 and carrier_position.distance_to(house) <= 6.0 and carrier_position.y < 10.0:
			_finish_match(carrier_pid, "WATER DELIVERED")
			return


func _score_for(entry: Dictionary) -> int:
	var altitude := maxf(0.0, float(entry.get("highest_y", 0.0)))
	var penalty := maxf(0.0, float(entry.get("penalty", 0.0)))
	return int(round(altitude * 10.0)) - int(round(penalty))


func _best_player_id() -> int:
	var best_id := 0
	var best_score := -1000000
	var best_altitude := -1.0
	for key in _players_state.keys():
		var entry: Dictionary = _players_state[key]
		var score := _score_for(entry)
		var altitude := float(entry.get("highest_y", 0.0))
		if score > best_score or (score == best_score and altitude > best_altitude):
			best_score = score
			best_altitude = altitude
			best_id = int(key)
	return best_id


func _finish_match(winner_id: int, reason: String) -> void:
	if _phase == PHASE_ENDED:
		return
	_phase = PHASE_ENDED
	_winner_id = winner_id
	_end_reason = reason
	for key in _players_state.keys():
		var entry: Dictionary = _players_state[key]
		entry["score"] = _score_for(entry)
	var winner_entry: Dictionary = _players_state.get(winner_id, {})
	_notify("WINNER: %s (%s)" % [str(winner_entry.get("name", "Nobody")), reason])
	_play_fx("summit" if winner_id > 0 else "go", -1.0)
	_broadcast_state()


func _pack_state() -> Array:
	var packed: Array = []
	for key in _players_state.keys():
		var entry: Dictionary = _players_state[key]
		packed.append([
			int(key),
			str(entry.get("name", "Climber")),
			entry.get("color", Color.WHITE),
			float(entry.get("highest_y", 0.0)),
			float(entry.get("checkpoint_y", 0.0)),
			float(entry.get("penalty", 0.0)),
			int(_score_for(entry))
		])
	return packed


func _apply_snapshot(snapshot: Array) -> void:
	for item in snapshot:
		if not item is Array:
			continue
		var fields: Array = item
		if fields.size() < 7:
			continue
		var pid := int(fields[0])
		var entry: Dictionary = _players_state.get(pid, _new_player_state(pid, str(fields[1]), Color.WHITE))
		entry["name"] = str(fields[1])
		entry["color"] = fields[2]
		entry["highest_y"] = float(fields[3])
		entry["checkpoint_y"] = float(fields[4])
		entry["penalty"] = float(fields[5])
		entry["score"] = int(fields[6])
		_players_state[pid] = entry


func _remote_targets() -> Array[int]:
	var result: Array[int] = []
	for key in _ready_peers.keys():
		var pid := int(key)
		if pid > 1:
			result.append(pid)
	return result


func _on_peer_disconnected(peer_id_value: int) -> void:
	_ready_peers.erase(peer_id_value)
	if not _is_authority():
		return
	if _carry_links.has(peer_id_value):
		_clear_carry_link(peer_id_value, true)
	for key in _carry_links.keys():
		var link: Dictionary = _carry_links[key]
		if int(link.get("kind", -1)) == 1 and str(link.get("target_id", "")) == str(peer_id_value):
			_clear_carry_link(int(key), true)
			break
	var climber: Node = _find_climber_by_id(peer_id_value)
	if climber == null:
		_climbers.erase(peer_id_value)
		_players_state.erase(peer_id_value)


@rpc("any_peer", "call_local", "reliable")
func rpc_game_ready() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	_ready_peers[sender] = true


func _broadcast_state() -> void:
	var snapshot := _pack_state()
	_apply_snapshot(snapshot)
	if bool(Net.is_host) and _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "receive_state", snapshot, _countdown, _elapsed, _phase, _winner_id, _end_reason)


@rpc("authority", "call_remote", "unreliable")
func receive_state(snapshot: Array, countdown_value: float, elapsed_value: float, phase_value: int, winner_value: int, reason_value: String) -> void:
	_countdown = countdown_value
	_elapsed = elapsed_value
	_phase = phase_value
	_winner_id = winner_value
	_end_reason = reason_value
	_apply_snapshot(snapshot)


static func _sort_players(a: Variant, b: Variant) -> bool:
	return int((a as Dictionary).get("peer_id", 0)) < int((b as Dictionary).get("peer_id", 0))


func _player_list() -> Array:
	var result: Array = []
	for key in _players_state.keys():
		var entry: Dictionary = (_players_state[key] as Dictionary).duplicate(true)
		entry["peer_id"] = int(key)
		result.append(entry)
	result.sort_custom(_sort_players)
	return result


func _push_state_to_hud() -> void:
	if not hud.has_method("update_state"):
		return
	var local_penalty := 0.0
	if _players_state.has(_local_id):
		local_penalty = float((_players_state[_local_id] as Dictionary).get("penalty", 0.0))
	var winner_entry: Dictionary = _players_state.get(_winner_id, {})
	var bucket: Node = _props.get("bucket_0")
	var bucket_water := -1.0
	if bucket != null and is_instance_valid(bucket):
		bucket_water = float(bucket.get("water"))
	var state := {
		"phase": _phase,
		"bucket_water": bucket_water,
		"countdown": _countdown,
		"time_left": maxf(0.0, MATCH_DURATION - _elapsed - local_penalty),
		"elapsed": _elapsed,
		"players": _player_list(),
		"local_peer_id": _local_id,
		"winner": _winner_id,
		"winner_name": str(winner_entry.get("name", "")),
		"reason": _end_reason,
		"is_host": _is_authority()
	}
	hud.call("update_state", state)


func _notify(text: String) -> void:
	rpc_event(text)
	if bool(Net.is_host) and _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "rpc_event", text)


@rpc("authority", "call_remote", "reliable")
func rpc_event(text: String) -> void:
	hud.call("push_event", text)


func _play_fx(sound_name: String, volume_db: float) -> void:
	sfx.call("play", sound_name, volume_db, 1.0)
	if bool(Net.is_host) and _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "rpc_fx", sound_name, volume_db)


@rpc("authority", "call_remote", "reliable")
func rpc_fx(sound_name: String, volume_db: float) -> void:
	sfx.call("play", sound_name, volume_db, 1.0)


func _show_go() -> void:
	hud.call("show_go_flash")
	if bool(Net.is_host) and _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "rpc_show_go")


@rpc("authority", "call_remote", "reliable")
func rpc_show_go() -> void:
	hud.call("show_go_flash")


func _connect_chat_signals() -> void:
	for info in Net.get_signal_list():
		var signal_name := String(info.get("name", ""))
		if not signal_name.to_lower().contains("chat"):
			continue
		var count := HAZARD_SCRIPT.signal_arg_count(Net, signal_name)
		if count <= 0:
			continue
		var callback: Callable
		if count == 1:
			callback = Callable(self, "_on_net_chat_1")
		elif count == 2:
			callback = Callable(self, "_on_net_chat_2")
		else:
			callback = Callable(self, "_on_net_chat_3")
		Net.connect(signal_name, callback)


func _on_net_chat_1(a: Variant) -> void:
	_display_chat(0, str(a))


func _on_net_chat_2(a: Variant, b: Variant) -> void:
	if a is int:
		_display_chat(int(a), str(b))
	elif b is int:
		_display_chat(int(b), str(a))
	else:
		_display_chat(0, str(b))


func _on_net_chat_3(_a: Variant, b: Variant, c: Variant) -> void:
	_display_chat(int(b) if b is int else 0, str(c))


func _on_chat_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	if Net.has_method("send_chat"):
		Net.call("send_chat", clean)
	_display_chat(_local_id, clean)
	if bool(Net.is_host) and _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "rpc_chat", _local_id, clean)


@rpc("any_peer", "call_remote", "reliable")
func rpc_chat(sender_id: int, text: String) -> void:
	_display_chat(sender_id, text)


func _display_chat(sender_id: int, text: String) -> void:
	if text.is_empty():
		return
	var key := "%d|%s" % [sender_id, text]
	var now := Time.get_ticks_msec()
	if int(_chat_dedupe.get(key, 0)) + 1200 > now:
		return
	_chat_dedupe[key] = now
	var entry: Dictionary = _players_state.get(sender_id, {})
	var sender := str(entry.get("name", "Peer %d" % sender_id))
	hud.call("add_chat", sender_id, sender, text)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
	if event.is_action_pressed(&"ui_accept") and _phase == PHASE_ENDED:
		_return_to_menu()


func _return_to_menu() -> void:
	if not _is_authority():
		return
	if _has_network():
		for pid in _remote_targets():
			rpc_id(pid, "rpc_return_to_menu")
	rpc_return_to_menu()


@rpc("any_peer", "call_remote", "reliable")
func rpc_return_to_menu() -> void:
	if Net.has_method("leave"):
		Net.call("leave")
	get_tree().change_scene_to_file(MENU_SCENE)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
