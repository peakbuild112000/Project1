# Climb Together — design contract

## Goal
A difficult cooperative/competitive 3D climbing game for 1–4 players. The round lasts as long as players survive and climb; falling respawns at the last checkpoint and adds a time penalty. Players spawn in a cabin, leave it to bring a huge water bucket from the summit back home without spilling it. Delivering any remaining water to the cabin wins the match; emptying the bucket fails the delivery. Carrying objects, the bucket or climbers costs stamina and builds internal effort; if the effort overloads, the climber loses their grip and ragdolls. Longer falls accelerate gravity, widen the camera FOV and lock more stamina on impact. Hard landings and enemy strikes permanently lock part of the stamina bar in red until a bandage is used, and hard landings also cause injuries that slow regeneration. Stamina refills only on solid ground. A badly injured climber who empties their bar in a fall collapses unconscious; a death countdown runs until a bandage is used, and carrying the downed climber pauses that countdown without healing them. Nobody starts with bandages. There is no health bar, no effort bar and no carry slot readout. Total carried weight slows movement and jumping. Two classes are chosen in the lobby: **Strong** carries and throws an awake **Elastic** teammate high toward the camera direction; any class can carry a downed teammate. The Elastic owns a rope tail that stretches with `Q` so a Strong teammate can hook and climb it. A downed teammate can be dropped and revived with a bandage. Arm reach is short (14 m). There is no ball mode and no manual arm-stretch action; `Q` only tensions the Elastic rope tail.

Browsers cannot host ENet/UDP, and there is no offline solo mode. Online play uses WebRTC: **HOST ROOM** and **JOIN ROOM** talk to a WebSocket signaling relay (`tools/signaling_server.js`) through `scripts/network/web_rtc_room.gd`, then game traffic flows over `WebRTCMultiplayerPeer` data channels. The host is always id `1`, so the authoritative game logic is identical on desktop and Web. Direct `create_server()` / `join_server()` calls still reject Web with the ENet browser messages.

## Shared contracts

### Autoload `Net` (`scripts/network/network_manager.gd`)
- `peer_id: int`, `is_host: bool`, `player_name: String`, `port: int`, `web_room: String`
- `players: Dictionary[int, Dictionary]` with at least `name: String`, `color: Color`, `ready: bool`
- Signals: `peer_connected(peer_id)`, `peer_disconnected(peer_id)`, `connected()`, `connection_failed(message)`, `hosted()`, `lobby_changed()`, `match_started()`, `disconnected()`
- Methods:
  - `create_server(player_name: String, max_players: int = 4, port: int = 7777) -> void`
  - `join_server(player_name: String, address: String, port: int = 7777) -> void` (desktop ENet only)
  - `create_web_room(player_name: String, signal_url: String, room: String, max_players: int = 4) -> void`
  - `join_web_room(player_name: String, signal_url: String, room: String) -> void`
  - `start_match() -> void` (host only; changes every peer to `res://scenes/game.tscn`)
  - `leave() -> void`
  - `set_ready(ready: bool) -> void`
  - `send_chat(message: String) -> void`
  - `player_data(peer_id: int) -> Dictionary`

### WebRTC room (`scripts/network/web_rtc_room.gd`)
- Child of the `Net` autoload. Uses `WebSocketPeer` only for signaling JSON and `WebRTCMultiplayerPeer` for gameplay.
- Host calls `start_host(signal_url, room, max_players)` → server assigns id `1` → `WebRTCMultiplayerPeer.create_server()`.
- Client calls `start_client(signal_url, room)` → server assigns id `2`–`4` → `WebRTCMultiplayerPeer.create_client(id)`.
- The host creates an offer for every joining id; clients only answer. ICE candidates are buffered until the remote description is applied.
- Signaling messages: `create`, `join`, `created`, `joined`, `peer_joined`, `peer_left`, `offer`, `answer`, `ice`, `leave`, `error`. Rooms hold at most 4 players.
- `room_ready(peer_id, room)` tells `Net` to publish `hosted()` / `connected()`; `failed(message)` maps to `connection_failed`.
- `tools/signaling_server.js` is a standalone Node.js relay using the `ws` package. HTTPS pages require a `wss://` URL. Google STUN is configured by default; restrictive NATs need a TURN entry in `ICE_SERVERS`.

### Player (`scenes/climber.tscn`, `scripts/player/climber.gd`)
- Root: `RigidBody3D` named `Climber`, class `Climber`
- Public state: `peer_id`, `display_name`, `player_color`, `character_type` (`0` Strong, `1` Elastic), `current_stamina`, `max_stamina`, `stamina_lock` (permanent red stamina), `stretch` (internal effort), `ragdoll_active`, `unconscious`, `persistent_unconscious`, `fall_time`, `carry_kind`, `carry_target_id`, `carried_by_peer`, `has_jetpack`, `jetpack_fuel`, `injury`, `bandages`, `highest_y`, `checkpoint_y`, `is_local`
- Signals: `stamina_changed(current, max)`, `stamina_lock_changed(value)`, `stretch_changed(value, overloaded)`, `ragdoll_started`, `ragdoll_ended`, `unconscious_changed(value)`, `revived(helper_id)`, `carry_changed(kind, target_id)`, `jetpack_changed(equipped, fuel)`, `bandages_changed(count)`, `injury_changed(value)`, `fall_damage(amount, impact_speed)`, `notice_requested(text)`, `died(reason)`, `checkpoint_reached(y)`, `summit_reached`, `landed`, `anchor_changed`
- Methods:
  - `configure(peer_id: int, display_name: String, player_color: Color, character_type: int = CharacterType.STRONG) -> void`
  - `is_strong() -> bool`, `is_elastic() -> bool`, `can_carry_climber(target: Node) -> bool`
  - `set_character_type(value: int) -> void`, `launch_from_carry(velocity: Vector3) -> void`
  - `respawn_at(pos: Vector3, _unused: bool = false) -> void`
  - `apply_hazard(impulse: Vector3, label: String) -> void`
  - `apply_bounce(impulse: Vector3, label: String) -> void`
  - `apply_fall_impact(impact_speed: float, fall_duration: float = 0.0) -> void`
  - `equip_jetpack(amount: float) -> void`
  - `remove_jetpack() -> void`
  - `add_bandage(amount: int = 1) -> void`
  - `use_bandage() -> void`
  - `find_bandage_target() -> Node`
  - `use_bandage_on_target(target_pid: int) -> void`
  - `revive_with_bandage(helper_pid: int) -> void`
  - `set_persistent_unconscious(value: bool) -> void`
  - `usable_max_stamina() -> float`
  - `set_stamina_lock(value: float) -> void`
  - `get_total_weight() -> float`
  - `set_carry(kind: int, target_id: String) -> void`
  - `set_carried_by(peer_id: int) -> void`
  - `get_carry_hold_point() -> Vector3`
  - `find_fix_target() -> Node`
  - `get_state() -> Dictionary`
- Carry kinds: `-1` empty, `0` physical prop, `1` another climber, `2` another climber's tail. `find_carry_target()` favours a nearby tail over props and passengers; `_find_tail()` / `_find_tail_by_owner()` resolve the target on both sides. `TailRope.set_carrier()` makes the tail `top_level` while held, then unfreezes it and gives it a forward/up impulse on release. A 2.6 s timer returns it to `rest_transform` under its owner. `_apply_carry_link()`, `_clear_carry_link()` and `_check_carry_links()` mirror prop carry links for kind `2`, and remote climbers call `_process_active_carry()` so the tail follows the carrier on every peer. `can_carry_climber()` and `GameManager._authorize_carry()` allow any class to lift a downed teammate, but only a Strong carrying an Elastic can lift an awake climber. Releasing that link calls `launch_from_carry()` with `carrier.linear_velocity + forward * 14 + up * 11`, so the Elastic is thrown higher toward the carrier's camera direction (the forward vector is flattened so camera pitch cannot remove the upward arc). The host also sends `rpc_carry_launch` to the passenger node: the owner peer is the only one that simulates that body, so it re-applies the velocity locally; `last_launch_velocity` records it for verification. `set_carried_by()` recovers an awake ragdoll, but keeps an unconscious teammate down while folding the ragdoll rig away; `_process_carried()` pulls the passenger to the holder's hold point. Dropping an unconscious passenger reopens the ragdoll without clearing `unconscious`. The watchdog drops the link only if the target dies or is no longer linked to that carrier.
- `unconscious` is the downed game state; `ragdoll_active` is only the visual/physics state. In multiplayer `_spawn_climber()` sets `persistent_unconscious` so a ragdoll timer cannot revive the climber for free. Solo matches keep the old timed recovery. `find_bandage_target()` prefers a carried downed teammate, then the closest unconscious one inside `carry_reach + 1.0`. `use_bandage_on_target()` spends the local player's bandage and asks the host to revive; `revive_with_bandage()` stands the target up, clears the ragdoll, unlocks up to `bandage_heal` red stamina, eases injury and grants brief invulnerability.
- Fall impacts above `fall_damage_min_speed` subtract stamina, then lock the same amount with `set_stamina_lock()`. `_update_fall_dynamics()` grows `fall_time` only while airborne, descending and unanchored; it raises `gravity_scale`, lowers `linear_damp` and caps speed at `fall_speed_cap`. `apply_fall_impact()` adds `fall_time * fall_damage_per_second` to the impact speed, lowers the safe threshold with duration, and scales injury gain and stun with duration. Locked stamina is red, excluded from `usable_max_stamina()`, survives respawn and ragdoll recovery, and can only be won back by a bandage (up to `bandage_heal` per use). Nobody starts with bandages. Injury multiplies stamina regeneration by `1 - injury * injury_regen_penalty`; a bandage also subtracts `bandage_injury_relief` injury. Regeneration only runs in the `grounded` branch of `_update_stamina()`: hanging, climbing and ordinary airborne movement never refill stamina. `PlayerCamera` widens FOV by up to `fall_fov_boost` during a long fall.
- `is_critically_damaged()` is true at `injury >= critical_injury` or `stamina_lock >= max_stamina * critical_lock_ratio`. When `apply_fall_impact()` empties such a climber's bar, `_collapse_from_fall()` forces `persistent_unconscious` and starts a ragdoll. `unconscious_time` advances only in `_process_ragdoll()` while the climber is down and not carried; `get_death_time_left()` exposes `unconscious_death_time - unconscious_time` to the HUD. At 25/50/75% the HUD feed warns that a bandage is needed; at 100% `_die_from_unconscious()` emits `died("unconscious")`. `set_carried_by()` stops the timer because a carried passenger is no longer in `_process_ragdoll()`, but the downed state survives; only `revive_with_bandage()` clears it.
- `apply_enemy_strike()` is the enemy contact path. It drains stamina, locks the same amount with `set_stamina_lock()`, adds injury and starts a short invulnerability window. Unlike gust damage, the stolen part cannot regenerate; it comes back only through a bandage.
- `get_total_weight()` sums the carried prop mass, carried climber mass and `jetpack_mass_kg`. Weight scales walk/air speed and jump impulse. The bucket uses a two-hand hold point and hand visual, and `_hands_full_with_bucket()` releases anchors and blocks new ones while it is carried. `LeftFoot` / `RightFoot` meshes animate with `walk_cycle`; the grounded `can_walk` check no longer depends on `count_anchors()`, and jumping keeps full impulse with two anchors, so feet work while both hands are busy.
- The player shadow is a ground-projected blob (`GroundShadow`); arm shadow casting is disabled so ropes do not paint long silhouettes. `_update_shadow()` bails out when the climber or its root-level shadow is no longer in the tree.
- `harpoon_reach` is `14.0` m (down from `35.0`) so holds must be reached progressively; `carry_reach` stays `3.6` m for grabbing props or teammates.
- Local peer reads input and simulates physics. Remote peers freeze as kinematic bodies and receive `replicated_position` / `replicated_yaw` through `MultiplayerSynchronizer`; `_apply_remote_transform()` interpolates toward that target instead of letting the synchronizer write physics transforms directly. `respawn_at()` and `recover()` preserve the freeze state so remote bodies never fight gravity, teleport or vibrate.
- Arms normally hook static geometry on layer 1. The water bucket is also hookable on layer 4: its hook point follows the moving body and the reaction force is sent to the host, which applies a capped impulse plus torque so hands can drag and tip it. Both climbers carry a `TailRope` node for a uniform scene shape, but only the Elastic tail is active: `TailRope.setup()` sets `elastic`, visibility and collision layer, while a Strong tail is hidden and never grappleable. `_ray_exclusions()` hides a climber's own tail so they cannot hook themselves. `can_be_grappled()` requires an Elastic owner with no carrier, so teammates can hook an Elastic tail and winch up. The tail carries `owner_peer_id` / `carrier_id`.
- Holding `Q` as an Elastic calls `TailRope.set_tension(true, camera_forward, 13.0)`, which stretches a frozen kinematic rope body toward the camera and replicates the state through `rpc_apply_tension` every 0.05 s. `_clamp_length_to_walls()` raycasts from the owner origin along the tension direction against world layer 1 and shortens the rope at the first hit (minus `WALL_MARGIN`), so the kinematic body cannot be placed through walls; remote peers receive the already clamped length. Stretching drains `tail_tension_drain` stamina per second; hands-full states and ragdoll disable it. A Strong teammate can hook the tensioned rope with a grappling hand and climb it because the arm anchor pulls toward `body.global_transform * body_local_point`. `Q` is not an arm stretch and has no effect for Strong climbers. When a carrier releases a tail, it switches to collision layer 1 with mask 1 so it collides with world bodies in both directions; `_reset_to_owner()` restores layer 4 / mask 0.
- Arm visuals are sent every 0.05 s, including the released state, through `receive_arm_visual`; a released grappling arm therefore disappears instead of staying stuck in the wall on other peers.
- Camera yaw is kept in `PlayerCamera.yaw_rad`; `_process` must not reset it, otherwise mouse look stops working.
- Controls: WASD move, mouse look, LMB/RMB fire arms, Space jump/mantle, wheel winch, F grab/drop, E fix/release prop, Shift jetpack, B bandage (self or downed teammate), G remove empty jetpack, Esc release mouse.
- `find_fix_target()` returns the nearest crate, plank or trampoline within `fix_reach`, preferring props held by another peer or already fixed. The HUD shows the contextual `E: FIX/RELEASE ...` prompt.
- Players spawn inside a cabin. Simple 3D pictograms on the back wall show the basic controls; a large `BRING WATER TO YOUR HOUSE` sign lives in the world. The HUD no longer shows a mission banner when the local climber exits. The mountain center was moved to `MOUNTAIN_CENTER_Z = 16.0` so its foot no longer rises in front of the door, and `_build_rocks()` skips the exit corridor.
- All climber bodies are kept upright by `_integrate_forces`; remote climbers are also uprighted after replication so looking at them never shows a rolling body.

### Physical props (`scripts/game/prop.gd`)
- Root: `RigidBody3D`, class `ClimbProp`, group `climb_props`.
- Kinds: `CRATE`, `PLANK`, `TRAMPOLINE`, `BUCKET`.
- Host simulates free props and broadcasts `pack_state()` at 20 Hz.
- `set_carrier(peer_id)` freezes a grabbed prop; `apply_state()` interpolates remote state.
- `is_fixed` / `set_fixed(value)` turns a crate, plank or trampoline into a static platform (`FREEZE_MODE_STATIC`) with a cyan emissive overlay. `pack_state()` carries the flag as its sixth field, and `fixed_changed(value)` lets visuals react. A fixed prop clears its carrier and cannot be grabbed until released.
- Trampolines create a local `Area3D` bounce zone that calls `apply_bounce()` on climbers.
- The bucket starts full and stays a free `RigidBody3D`; it is never frozen until carried. `can_be_grappled()` allows either hand to hook it, and `apply_pull_impulse()` moves and tips it on the host. Host-only spill drains water on tilt, speed or spin and emits `water_changed(value)`. `pack_state()` includes the water amount as its fifth field.

### Item pickups (`scripts/game/item_pickup.gd`)
- Root: `Area3D`, class `ClimbItemPickup`, group `climb_items`.
- `Kind { JETPACK, BANDAGE }`. `setup(item_id, amount, kind)` configures it; jetpacks use the amount as fuel, bandages as count.
- Touch is confirmed by the host, which sends `rpc_item_taken(item_id, receiver_id, amount)`.
- `set_taken(true)` hides the pickup globally; only the receiver equips/refills the jetpack or adds bandages.

### Game manager (`scripts/game/game_manager.gd`)
- Scene `res://scenes/game.tscn`, root `Game` with children `Level`, `Players`, `HUD`, `MultiplayerSpawner` (`spawn_path="../Players"`)
- Spawn function uses peer id as data, configures each `Climber` from `Net.player_data(peer_id)`, sets multiplayer authority to that peer, places at generated spawn points.
- Lobby clients toggle a READY button; the host has no ready step and starts the match directly with START MATCH.
- Host owns countdown, match timer, scores, checkpoints, winner, chat relay, carry links, bandage revives, prop states, fixed/unfixed props and item pickups, and broadcasts state with `@rpc`. Falls add a time penalty; there are no lives.
- Carry RPCs: `rpc_request_carry`, `rpc_request_drop`, `rpc_apply_carry`; watchdog drops invalid links. `_authorize_carry()` enforces the class rule: downed targets may be carried by anyone, awake targets only by a Strong carrying an Elastic. `_clear_carry_link()` launches a strong-thrown awake Elastic passenger with `launch_from_carry()`.
- Character choice travels with the lobby: `Net.set_character_type()` sends `_rpc_register_character()` to the host, `_rpc_register_name()` carries the initial class in the same reliable packet, `_rpc_apply_lobby()` includes `character_type` in every player entry, and `_spawn_climber()` passes it into `Climber.configure()`. `scripts/game/character_type.gd` defines the shared constants (`STRONG = 0`, `ELASTIC = 1`).
- `Net.has_both_classes()` is the match gate. `start_match()` refuses to start with fewer than two climbers or with all players on the same class, emitting `match_start_rejected(reason)`. The lobby disables START MATCH and explains the requirement; the host can retry after a missing class joins.
- Revive RPCs: `request_bandage_revive` / `rpc_request_bandage_revive` carry the helper's id to the host, which checks target distance (`REVIVE_REACH = 4.6`), downed state and carry ownership, clears an active carry link, then broadcasts `rpc_apply_bandage_revive`. The bandage itself is spent on the helping client before the request.
- Coop build RPCs: `rpc_request_fix` and `rpc_apply_prop_fixed`. `_authorize_fix()` rejects the bucket, a fixer farther than `FIX_REACH` and the carrier of the held prop; fixing a carried prop clears that carry link first. Releasing is allowed for any nearby climber.
- Item RPCs: `rpc_request_item`, `rpc_item_taken`.
- Prop RPCs: `rpc_report_carried_prop`, `rpc_report_prop_pull`, `rpc_prop_states`, `rpc_apply_prop_fixed`.
- Level generator builds a seeded procedural mountain heightfield with a concave collider, then pins irregular ledges, overhangs, hazards, checkpoints, summit, the starting cabin, rocks, a narrow harder pillar, low-poly props, the water bucket, jetpack pickups, bandage pickups and patrolling enemy drones to that slope. The host chooses the seed per match and sends it with the start RPC so every peer builds the same mountain. `get_house_position()` returns the delivery point. `Prop` water level is host-authoritative and travels in the prop-state packets.
- `scripts/game/enemy.gd` defines `ClimbEnemy`, an `Area3D` drone on a deterministic local route. It emits `enemy_hit(body)`; hits are applied locally by each peer via `apply_hazard()` and `set_current_stamina()`, so no replication is required. `hazard.gd` exposes `Type.ENEMY` for its notices.
- GLB models are `jetpack.glb`, `trampoline.glb`, `plank.glb`, `crate.glb`, `bandage.glb`, `cabin.glb`, `rock.glb` and `enemy.glb`, all produced by `assets/blender/generate_items.py`. Missing files fall back to engine primitives at runtime, but validation checks that all eight exist.

## Quality bar
- No TODO/FIXME/placeholder/stub text, no empty source files.
- Godot 4.6 headless import and scripts must parse without errors.
- Gameplay must be understandable from the HUD alone.
- `tests/run_tests.ps1` runs the import, headless regression harnesses and static checks. Expected result: `RESULT PASSED` with all `failures=0`, `STATIC BAD: 0` and `EMPTY FILES: 0`.
