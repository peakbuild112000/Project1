# Climb Together — design contract

## Goal
A difficult cooperative/competitive 3D climbing game for 1–4 players. The round lasts as long as players survive and climb; falling costs a life and a time penalty. Players spawn in a cabin, leave it to bring a huge water bucket from the summit back home without spilling it. Delivering any remaining water to the cabin wins the match; emptying the bucket fails the delivery. Carrying objects, the bucket or climbers costs stamina and builds effort; if the effort overloads, the climber loses their grip and ragdolls. There is no ball mode and no manual stretch action.

Browsers cannot host ENet/UDP, so the Web build uses `start_solo()` and the main menu's **PLAY SOLO** button. `scripts/ui/main_menu.gd` detects Web with `OS.has_feature("web")`, hides **HOST** and **JOIN**, and `scripts/network/network_manager.gd` rejects direct `create_server()` / `join_server()` calls there. Desktop builds keep the full host/join flow.

## Shared contracts

### Autoload `Net` (`scripts/network/network_manager.gd`)
- `peer_id: int`, `is_host: bool`, `player_name: String`, `port: int`
- `players: Dictionary[int, Dictionary]` with at least `name: String`, `color: Color`, `ready: bool`
- Signals: `peer_connected(peer_id)`, `peer_disconnected(peer_id)`, `connected()`, `connection_failed(message)`, `hosted()`, `lobby_changed()`, `match_started()`, `disconnected()`
- Methods:
  - `create_server(player_name: String, max_players: int = 4, port: int = 7777) -> void`
  - `join_server(player_name: String, address: String, port: int = 7777) -> void`
  - `start_match() -> void` (host only; changes every peer to `res://scenes/game.tscn`)
  - `start_solo() -> void` (starts a match with `OfflineMultiplayerPeer`; used by the Web demo and by solo players)
  - `leave() -> void`
  - `set_ready(ready: bool) -> void`
  - `send_chat(message: String) -> void`
  - `player_data(peer_id: int) -> Dictionary`

### Player (`scenes/climber.tscn`, `scripts/player/climber.gd`)
- Root: `RigidBody3D` named `Climber`, class `Climber`
- Public state: `peer_id`, `display_name`, `player_color`, `current_stamina`, `max_stamina`, `stretch` (internal effort), `ragdoll_active`, `carry_kind`, `carry_target_id`, `carried_by_peer`, `has_jetpack`, `jetpack_fuel`, `highest_y`, `checkpoint_y`, `lives`, `is_local`
- Signals: `stamina_changed(current, max)`, `stretch_changed(value, overloaded)`, `ragdoll_started`, `ragdoll_ended`, `carry_changed(kind, target_id)`, `jetpack_changed(equipped, fuel)`, `died(reason)`, `checkpoint_reached(y)`, `summit_reached`, `landed`, `anchor_changed`
- Methods:
  - `configure(peer_id: int, display_name: String, player_color: Color) -> void`
  - `respawn_at(pos: Vector3, restore_life: bool = false) -> void`
  - `apply_hazard(impulse: Vector3, label: String) -> void`
  - `apply_bounce(impulse: Vector3, label: String) -> void`
  - `equip_jetpack(amount: float) -> void`
  - `set_carry(kind: int, target_id: String) -> void`
  - `set_carried_by(peer_id: int) -> void`
  - `get_carry_hold_point() -> Vector3`
  - `get_state() -> Dictionary`
- Carry kinds: `-1` empty, `0` physical prop, `1` another climber.
- Local peer reads input and simulates physics. Remote peers freeze as kinematic bodies and receive `replicated_position` / `replicated_yaw` through `MultiplayerSynchronizer`; `_apply_remote_transform()` interpolates toward that target instead of letting the synchronizer write physics transforms directly. `respawn_at()` and `recover()` preserve the freeze state so remote bodies never fight gravity, teleport or vibrate.
- Arms normally hook static geometry on layer 1. The water bucket is also hookable on layer 4: its hook point follows the moving body and the reaction force is sent to the host, which applies a capped impulse plus torque so hands can drag and tip it.
- Arm visuals are sent every 0.05 s, including the released state, through `receive_arm_visual`; a released grappling arm therefore disappears instead of staying stuck in the wall on other peers.
- Camera yaw is kept in `PlayerCamera.yaw_rad`; `_process` must not reset it, otherwise mouse look stops working.
- Controls: WASD move, mouse look, LMB/RMB fire arms, Space jump/mantle, wheel winch, F grab/drop, Shift jetpack, Esc release mouse.
- Players spawn inside a cabin. Simple 3D pictograms on the back wall show the basic controls; a large `BRING WATER TO YOUR HOUSE` sign appears when the local climber exits.
- All climber bodies are kept upright by `_integrate_forces`; remote climbers are also uprighted after replication so looking at them never shows a rolling body.

### Physical props (`scripts/game/prop.gd`)
- Root: `RigidBody3D`, class `ClimbProp`, group `climb_props`.
- Kinds: `CRATE`, `PLANK`, `TRAMPOLINE`, `BUCKET`.
- Host simulates free props and broadcasts `pack_state()` at 20 Hz.
- `set_carrier(peer_id)` freezes a grabbed prop; `apply_state()` interpolates remote state.
- Trampolines create a local `Area3D` bounce zone that calls `apply_bounce()` on climbers.
- The bucket starts full and stays a free `RigidBody3D`; it is never frozen until carried. `can_be_grappled()` allows either hand to hook it, and `apply_pull_impulse()` moves and tips it on the host. Host-only spill drains water on tilt, speed or spin and emits `water_changed(value)`. `pack_state()` includes the water amount as its fifth field.

### Item pickups (`scripts/game/item_pickup.gd`)
- Root: `Area3D`, class `ClimbItemPickup`, group `climb_items`.
- Only the jetpack exists. `setup(item_id, fuel)` configures it.
- Touch is confirmed by the host, which sends `rpc_item_taken(item_id, receiver_id, amount)`.
- `set_taken(true)` hides the pickup globally; only the receiver equips/refills the jetpack.

### Game manager (`scripts/game/game_manager.gd`)
- Scene `res://scenes/game.tscn`, root `Game` with children `Level`, `Players`, `HUD`, `MultiplayerSpawner` (`spawn_path="../Players"`)
- Spawn function uses peer id as data, configures each `Climber` from `Net.player_data(peer_id)`, sets multiplayer authority to that peer, places at generated spawn points.
- Lobby clients toggle a READY button; the host has no ready step and starts the match directly with START MATCH.
- Host owns countdown, match timer, scores, lives, checkpoints, winner, chat relay, carry links, prop states and item pickups, and broadcasts state with `@rpc`.
- Carry RPCs: `rpc_request_carry`, `rpc_request_drop`, `rpc_apply_carry`; watchdog drops invalid links.
- Item RPCs: `rpc_request_item`, `rpc_item_taken`.
- Prop RPCs: `rpc_report_carried_prop`, `rpc_report_prop_pull`, `rpc_prop_states`.
- Level generator builds a layered mountain shell, deterministic obstacles, hazards, checkpoints, summit, the starting cabin, low-poly props, the water bucket and jetpack pickups. `get_house_position()` returns the delivery point. `Prop` water level is host-authoritative and travels in the prop-state packets.

## Quality bar
- No TODO/FIXME/placeholder/stub text, no empty source files.
- Godot 4.6 headless import and scripts must parse without errors.
- Gameplay must be understandable from the HUD alone.
- `tests/run_tests.ps1` runs the import, headless regression harnesses and static checks. Expected result: `RESULT PASSED` with all `failures=0`, `STATIC BAD: 0` and `EMPTY FILES: 0`.
