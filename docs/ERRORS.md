# Errors encountered and how they were fixed

This log is kept in English on purpose. It records the real problems found while
building, testing and publishing the project, not a hypothetical bug list.

## 1. `Node 'global_position' not found` during replication

**Symptom**

The host printed this every sync tick:

```text
ERROR: Node 'global_position' not found.
ERROR: Parameter "obj" is null.
ERROR: Unable to retrieve sync state.
```

**Cause**

`SceneReplicationConfig.add_property()` was called with plain property names.
Godot expects paths relative to the synchronizer root, such as
`NodePath(".:global_position")`.

**Fix**

Every replicated property is now registered as `NodePath(".:" + property_name)`
in `scripts/player/climber.gd`. Do not shorten these paths to bare names.

## 2. Remote avatar teleported back to spawn and appeared to disappear

**Symptom**

The local host moved normally, but other peers saw the remote climber snap back
to its spawn point and visually vanish.

Observed on a client:

```text
VIS y=1.735 x=-3.400 vel=0.00,0.00 yaw=0.00 local=false freeze=true
```

while the host was at `x=-4.6`.

**Cause**

`MultiplayerSynchronizer` was writing `global_position` and `linear_velocity`
directly onto a remote `RigidBody3D` that was frozen in kinematic mode. The
local upright correction then rewrote the transform with the last yaw/position,
so replicated packets were overwritten every frame.

**Fix**

- Added `replicated_position` as a plain exported `Vector3`.
- Replicated `replicated_position` and `replicated_yaw` instead of physics
  transforms.
- Added `_apply_remote_transform()` in `scripts/player/climber.gd`; remote bodies
  interpolate toward the replicated target and snap only on large drift such as
  a respawn.
- Removed `linear_velocity` and `angular_velocity` from the synchronizer because
  they caused visible stutter.
- Kept remote bodies frozen in kinematic mode, including after `respawn_at()`
  and `recover()`.

**Verification**

```text
UPRIGHT failures=0
REMOTE VISUAL failures=0
CLIMB VALIDATION failures=0
```

A two-process ENet movement test now shows the client following the target
smoothly:

```text
VIS x=-4.063 tgt=-4.390
VIS x=-4.311 tgt=-4.390
VIS x=-4.363 tgt=-4.390
VIS x=-4.388 tgt=-4.390
```

## 3. Grappling arms stayed stuck in walls on other peers

**Symptom**

A released arm remained drawn in the wall on remote clients.

**Cause**

Only anchored arm states were sent. The released state was never transmitted.

**Fix**

`get_arm_visual_state()` is sent every `0.05 s`, including released state, via
`receive_arm_visual`. Ragdoll poses use the same unreliable remote RPC path.

## 4. First-person camera rolled when looking down

**Symptom**

Looking down rotated the whole body visually, which made the camera roll.

**Fix**

`PlayerCamera.yaw_rad` holds the heading. `_process()` must not reset camera
rotation. Remote bodies are kept upright from `replicated_yaw`, never from a
full replicated basis.

## 5. `MultiplayerSpawner` did not spawn players

**Cause**

The spawner path did not match the actual `Players` node location.

**Fix**

`scenes/game.tscn` keeps:

```text
spawn_path = NodePath("../Players")
```

Changing it to `Players` or `res://Players` breaks spawning.

## 6. Authority was wrong in offline tests

**Symptom**

Headless tests using `OfflineMultiplayerPeer` were treated as networked and
tried to send RPCs to an empty peer.

**Fix**

`GameManager._has_network()` returns `false` for `OfflineMultiplayerPeer`. Only
a real ENet peer counts as network authority.

## 7. Clients could enter the match before the game scene was ready

**Fix**

`GameManager` keeps the `rpc_game_ready` handshake. Clients wait until the host
scene is fully instantiated before applying lobby/start state.

## 8. The water bucket ignored the grappling hands

**Symptom**

The bucket was a `RigidBody3D` and collided with the body, but both hands skipped
it. `_fire_arm()` explicitly rejected every `RigidBody3D` collider.

**Fix**

- Added `can_be_grappled()` to `scripts/game/prop.gd`; only `Kind.BUCKET` returns
  `true`.
- The arm raycast now includes collision layer 4 while still rejecting normal
  rigid bodies.
- The hook point follows the moving bucket through a local-space offset.
- The reaction force is sent to the host through `rpc_report_prop_pull`.
- The host applies a capped impulse plus torque with `apply_pull_impulse()`, so
  pulling sideways tips the bucket and spills water naturally.

**Verification**

`GAME SMOKE failures=0` includes a hook test and a real pull test.

## 9. `No multiplayer peer is assigned. Unable to get unique ID.`

**Where**

This appeared in some headless harnesses that instantiated `game.tscn` directly
without assigning a `MultiplayerPeer`.

**Status**

Harness-only warning, not a game failure. The gameplay code is already guarded
by `_has_network()`. The two-process ENet harnesses do not show this warning for
the real game nodes.

## 10. `ObjectDB instances leaked at exit`

**Where**

Printed by Godot when a headless `--script` test exits after loading a scene.

**Status**

Harmless shutdown warning from the test harness. It does not mean a gameplay
leak. `GAME SMOKE failures=0` is the authoritative result even when PowerShell
wraps this warning as a native command error.

## 11. PowerShell `$host` is a reserved automatic variable

**Symptom**

Early ENet test scripts used `$host` for the server process. PowerShell replaced
it with the console host object, so `Wait-Process` targeted the wrong thing.

**Fix**

All harnesses use `$serverProc` and `$clientProc`. Never stop every Godot
console process with `Get-Process ... | Stop-Process -Force`; track the exact PIDs
returned by `Start-Process -PassThru`.

## 12. Web export needed an explicit preset

Godot cannot export Web from the command line without a preset. The repository
now contains `export_presets.cfg` with a `Web` preset. ENet uses UDP and is not
available in browsers, so the web demo uses the new `SOLO` button, which starts
an `OfflineMultiplayerPeer` match. Desktop builds keep the full host/join flow.

## 13. Static quality checks

The following patterns are rejected anywhere in source files:

```text
TODO
FIXME
placeholder
stub
ball_mode
is_ball
BallVisual
ball_mesh
toggle_ball_mode
Input.is_action_pressed("stretch")
CheckButton
```

Current result:

```text
STATIC BAD: 0
EMPTY FILES: 0
```
