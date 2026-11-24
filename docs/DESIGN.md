# Summit Race — design contract

## Goal

A difficult competitive 3D climbing race for 2–4 players. Every racer starts on
the same flat pad at the foot of a seeded procedural mountain. The first climber
to touch the summit hazard wins immediately with reason `SUMMIT`. If the
300-second timer expires, the racer with the best score wins with reason
`TIME UP`. Falls below `y = -12` respawn at the last checkpoint and add
`RESPAWN_PENALTY = 5.0` seconds; there are no lives, health, injuries, bandages,
permanent stamina locks, classes, carry slots, manual arm stretch or ball mode.
Ragdoll is a short stumble that always recovers automatically.

There is no solo mode. Desktop uses ENet host/join on UDP port `7777`. Web uses
WebRTC with WebSocket/WSS signaling. `Net.start_match()` refuses any lobby with
fewer than two players and emits `match_start_rejected(reason)`; the gate is
player count only.

## Shared contracts

### Autoload `Net` (`scripts/network/network_manager.gd`)

- `peer_id: int`, `is_host: bool`, `player_name: String`, `port: int`,
  `web_room: String`, `match_seed: int`, `max_players: int = 4`
- `players: Dictionary[int, Dictionary]` with at least `name: String`,
  `color: Color`, `ready: bool`
- Signals: `peer_connected(peer_id)`, `peer_disconnected(peer_id)`,
  `connected()`, `connection_failed(message)`, `hosted()`, `lobby_changed()`,
  `match_started()`, `disconnected()`, `chat_message(peer_id, message)`,
  `match_start_rejected(reason)`
- Methods:
  - `create_server(player_name: String, max_players: int = 4, port: int = 7777) -> void`
  - `join_server(player_name: String, address: String, port: int = 7777) -> void` (desktop ENet only)
  - `create_web_room(player_name: String, signal_url: String, room: String, max_players: int = 4) -> void`
  - `join_web_room(player_name: String, signal_url: String, room: String) -> void`
  - `start_match() -> void` (host only; requires at least two players and changes every peer to `res://scenes/game.tscn`)
  - `leave() -> void`
  - `set_ready(ready: bool) -> void`
  - `send_chat(message: String) -> void`
  - `player_data(peer_id: int) -> Dictionary`
- Lobby snapshots carry only identity, colour and readiness. `Net` has no class
  assignment or class gating methods.
- Every client sends `_rpc_register_name(player_name)` to the host on both ENet
  and WebRTC connection. The host keeps an existing entry instead of replacing a
  fast-arriving name with `Player <id>`, then broadcasts the corrected snapshot
  so the lobby and HUD show the chosen name on every peer.

### WebRTC room (`scripts/network/web_rtc_room.gd`)

- Child of the `Net` autoload. Uses `WebSocketPeer` only for signaling JSON and
  `WebRTCMultiplayerPeer` for gameplay.
- Host calls `start_host(signal_url, room, max_players)` → server assigns id `1`
  → `WebRTCMultiplayerPeer.create_server()`.
- Client calls `start_client(signal_url, room)` → server assigns id `2`–`4` →
  `WebRTCMultiplayerPeer.create_client(id)`.
- The host creates an offer for every joining id; clients only answer. ICE
  candidates are buffered until the remote description is applied.
- Signaling messages: `create`, `join`, `created`, `joined`, `peer_joined`,
  `peer_left`, `offer`, `answer`, `ice`, `leave`, `error`. Rooms hold at most four
  players.
- `room_ready(peer_id, room)` tells `Net` to publish `hosted()` / `connected()`;
  `failed(message)` maps to `connection_failed`.
- `tools/signaling_server.js` is a standalone Node.js relay using the `ws`
  package. HTTPS pages require a `wss://` URL. Google STUN is configured by
  default; restrictive NATs need a TURN entry in `ICE_SERVERS`.

### Racer (`scenes/climber.tscn`, `scripts/player/climber.gd`)

- Root: `RigidBody3D` named `Climber`, class `Climber`.
- Public state: `peer_id`, `display_name`, `player_color`, `current_stamina`,
  `max_stamina`, `ragdoll_active`, `fall_time`, `highest_y`, `checkpoint_y`,
  `replicated_position`, `replicated_yaw`, `has_jetpack`, `jetpack_fuel`,
  `is_local`.
- Signals: `stamina_changed(current, max)`, `ragdoll_started`, `ragdoll_ended`,
  `died(reason)`, `checkpoint_reached(y)`, `summit_reached`, `landed`,
  `anchor_changed`, `jetpack_changed(equipped, fuel)`, `notice_requested(text)`.
- Methods:
  - `configure(peer_id: int, display_name: String, player_color: Color, _unused: int = 0) -> void`
  - `respawn_at(pos: Vector3, _unused: bool = false) -> void`
  - `apply_hazard(impulse: Vector3, label: String) -> void`
  - `apply_enemy_strike(amount: float, impulse: Vector3) -> void`
  - `apply_bounce(impulse: Vector3, label: String) -> void`
  - `start_ragdoll() -> void`, `recover() -> void`
  - `usable_max_stamina() -> float` (always `max_stamina`)
  - `equip_jetpack(amount: float) -> void`, `remove_jetpack() -> void`
  - `get_total_weight() -> float` (jetpack mass only)
  - `can_climb() -> bool`, `count_anchors() -> int`
  - `get_state() -> Dictionary`
- `get_state()` reports identity, position, velocity, stamina, ragdoll, fall
  time, jetpack, anchor flags, grounded, `highest_y`, `checkpoint_y`, `dead` and
  `stunned`. It has no class, carry, injury, unconsciousness or bandage fields.
- `harpoon_reach` is `14.0` m so holds must be reached progressively. Arms hook
  layer 1; trampolines are not grappleable. `_ray_exclusions()` excludes the
  climber's own body and ragdoll parts.
- Stamina drains only while hanging or climbing and regenerates only on solid
  ground. Emptying the bar releases all anchors and emits `EXHAUSTED`. Hazard
  and enemy damage subtract stamina and start a short stun/invulnerability
  window; neither locks stamina.
- `_update_fall_dynamics()` grows `fall_time` only while airborne, descending
  and unanchored. It raises `gravity_scale`, lowers `linear_damp`, caps speed
  with `fall_speed_cap` and widens camera FOV. Landing only resets this state;
  there is no impact damage. Falling below `FALL_LIMIT_Y = -12.0` emits
  `died("fall")`.
- Ragdoll releases arms, freezes the body for a short `ragdoll_duration` and
  plays the hidden ragdoll rig. `_process_ragdoll()` always calls `recover()`
  when the timer expires. `recover()` restores an upright transform, clears
  stun/fall state and grants brief invulnerability.
- `LeftFoot` / `RightFoot` meshes animate with `walk_cycle`; their contact plane
  matches the 1.7 m capsule collider, feet only lift upward and toe tilt is
  compensated so shoes never sink through the floor.
- The player shadow is a ground-projected blob (`GroundShadow`); arm shadow
  casting is disabled so ropes do not paint long silhouettes.
- Local peers read input and simulate physics. Remote peers freeze as kinematic
  bodies and receive `replicated_position` / `replicated_yaw` through
  `MultiplayerSynchronizer`; `_apply_remote_transform()` interpolates toward
  that target instead of letting the synchronizer write physics transforms
  directly. `respawn_at()` and `recover()` preserve the freeze state.
- `MultiplayerSynchronizer` replicates identity, stamina, ragdoll, fall time,
  progress, replicated transform and yaw. It does not replicate class, carry,
  stretch or condition state.
- Camera yaw lives in `PlayerCamera.yaw_rad`; `_process` must not reset it.
- Controls: WASD move, mouse look, LMB/RMB fire arms, Space jump/mantle, wheel
  winch, Shift jetpack, G remove empty jetpack, T chat, Tab scoreboard, Esc
  release mouse.

### Trampolines (`scripts/game/prop.gd`)

- Root: `RigidBody3D`, class `ClimbProp`, group `climb_props`.
- `enum Kind { TRAMPOLINE }`; `kind` defaults to `TRAMPOLINE`. There are no
  crate, plank, bucket, water, carrier or fixed states.
- Props are frozen static bodies on the host and peers. `apply_state()` accepts
  `[prop_id, transform, linear, angular]` from `rpc_prop_states`.
- Each trampoline builds a local `Area3D` bounce zone on layer 4 with mask 2.
  A body with `apply_bounce()` triggers a per-body 700 ms cooldown and receives
  `Vector3.UP * bounce_impulse` plus a `TRAMPOLINE` notice.
- `can_be_grappled()` is always false and `apply_pull_impulse()` is inert.

### Jetpack pickups (`scripts/game/item_pickup.gd`)

- Root: `Area3D`, class `ClimbItemPickup`, group `climb_items`.
- Only `item_id`, `fuel_amount` and `taken` exist; there is no kind enum and no
  bandage branch.
- `setup(id: String, fuel: float)` configures the pickup. Touch asks the host to
  reserve it; the host confirms with `rpc_item_taken(item_id, receiver_id,
  amount)` and `set_taken(true)` hides it globally.
- The receiver calls `equip_jetpack(amount)`; an empty jetpack can be removed
  with `remove_jetpack()`.

### Race manager (`scripts/game/game_manager.gd`)

- Scene `res://scenes/game.tscn`, root `Game` with children `Level`, `Players`,
  `HUD`, `MultiplayerSpawner` (`spawn_path="../Players"`), `WorldEnvironment`,
  `DirectionalLight3D` and `Sfx`.
- Spawn function uses peer id as data, configures each `Climber` from
  `Net.player_data(peer_id)`, sets multiplayer authority to that peer and places
  it at `level.get_spawn_point(slot)`.
- Host owns countdown, timer, altitudes, checkpoints, scores, winner, chat
  relay, item pickups and prop state. Falls add a time penalty; there are no
  lives.
- Phases: `PHASE_COUNTDOWN = 0`, `PHASE_ACTIVE = 1`, `PHASE_ENDED = 2`.
  Countdown is 3 seconds; `MATCH_DURATION = 300.0`; `STATE_INTERVAL = 0.1`;
  `PROP_STATE_INTERVAL = 0.05`.
- `_update_altitudes()` keeps each racer's highest observed altitude. `_score_for()`
  returns `round(altitude * 10) - round(penalty)`. `_best_player_id()` breaks
  score ties by altitude.
- `_on_summit_for_peer(pid)` accepts a summit from the level hazard or a climber
  signal and immediately calls `_finish_match(pid, "SUMMIT")`.
- `_handle_death(reason, pid)` adds `RESPAWN_PENALTY` during an active phase,
  announces the penalty and respawns the racer at
  `level.get_checkpoint_position(checkpoint_y)` after 1.2 seconds.
- `_finish_match()` freezes the phase, finalises scores, announces the winner,
  plays the summit/go sound and broadcasts state. At timeout it is called with
  `_best_player_id()` and reason `TIME UP`.
- State fields: `phase`, `time_left`, `countdown`, `players`, `winner`,
  `winner_name`, `reason`, `local_peer_id`, `is_host`. Each player entry has
  `peer_id`, `name`, `color`, `highest_y`, `checkpoint_y`, `penalty` and `score`.
- RPCs: `rpc_game_ready`, `receive_state`, `rpc_prop_states`, `rpc_item_taken`,
  `rpc_request_item`, `rpc_event`, `rpc_fx`, `rpc_show_go`, `rpc_chat`,
  `rpc_return_to_menu`.
- HUD shows time, altitude, phase, stamina, jetpack, live altitude leaderboard,
  chat, event feed and a winner overlay. There is no health, effort, bandage,
  carry-slot or mission banner UI.

### Level generator (`scripts/game/level_generator.gd`)

- Deterministic seeded mountain: the host chooses one seed and sends it with the
  start RPC so every peer builds the same heightfield, concave collider, ledges,
  overhangs, hazards, checkpoints, summit, props and pickups.
- `_build_base()` creates a flat start pad named `StartPad` at the exact base
  centre `(0, 2.0, 16)`, with four spawn slots within 2 m of `(0, 3.05, 16)`.
  `_height_at()` carves a `SHAFT_RADIUS = 5` crater so that centre is the lowest
  point (1 m) inside the mountain. `_build_shaft_route()` adds 56 spiral grips
  from 4 m to 141 m so racers climb from the base centre to the summit platform.
  The front-face corridor and its thirteen `_entrance_z_for_height()` grips stay
  as an alternate route; procedural ledges, ribs, overhangs and boulders skip
  `|x| < 8`, `z < 12`, `y < 42`. The camera starts at `START_YAW = PI` with
  `START_PITCH_DEG = 35`, looking up the shaft toward the summit.
- `_build_props()` places four trampolines at 28 m, 68 m, 96 m and 132 m.
  `_build_items()` places two jetpacks at 16 m and 82 m.
- Checkpoints are at 26 m, 64 m and 104 m; `get_checkpoint_position(height)`
  returns the highest checkpoint at or below the requested height, or the first
  spawn point.
- Wind gusts, brittle holds, moving platforms, enemies and the difficult pillar
  scale with altitude. The summit hazard sits at `SUMMIT_Y = 142.0`.
- GLB models are `jetpack.glb`, `trampoline.glb`, `rock.glb` and `enemy.glb`,
  generated by `assets/blender/generate_items.py`. Missing files fall back to
  engine primitives, but validation checks that all four exist and that the
  obsolete plank/crate/bandage/cabin models are gone.

### enemies and hazards

- `scripts/game/enemy.gd` defines `ClimbEnemy`, an `Area3D` drone on a
  deterministic local route. It emits `enemy_hit(body)`; hits are applied
  locally by each peer with `apply_hazard()` / `apply_enemy_strike()`, so no
  replication is required.
- `hazard.gd` exposes hazard kinds for wind, checkpoint and summit. Checkpoints
  and summit forward the touching body to `GameManager`; wind applies a local
  impulse and stamina loss.

## Quality bar

- No TODO/FIXME/placeholder/stub text, no empty source files.
- No class, carry, bandage, water, tail, solo, ball-mode or manual-stretch APIs.
- Godot 4.6 headless import and scripts must parse without errors.
- Gameplay must be understandable from the HUD alone.
- `tests/run_tests.ps1` runs the import, headless regression harnesses and static
  checks. Expected result: `RESULT PASSED` with all `failures=0`, `STATIC BAD: 0`
  and `EMPTY FILES: 0`.
