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

## 12. Web export and the "Unable to host on port 7777" demo error

Godot cannot export Web from the command line without a preset. The repository
contains `export_presets.cfg` with a `Web` preset.

**Symptom in the first Web build**

Clicking **HOST** in the browser produced:

```text
Unable to host on port 7777: ...
```

**Cause**

ENet uses UDP sockets, which browsers do not expose. The button was still
available in the Web menu, so Godot tried to create a UDP server and failed.

**Fix**

`scripts/ui/main_menu.gd` checks `OS.has_feature("web")` and exposes only
**HOST ROOM** / **JOIN ROOM** on WebRTC; the old offline solo entry point was
removed. `scripts/network/network_manager.gd` still rejects direct
`create_server()` and `join_server()` calls on Web, now pointing players to a
WebRTC room. Desktop builds keep the ENet host/join flow and port `7777`. The
WebRTC fix is documented below.

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

## 14. Long arm silhouettes looked like a giant shadow

**Symptom**

The first-person grapple arms cast long shadows that read as a strange creature
on the ground.

**Fix**

`_setup_shadow()` creates a dedicated `GroundShadow` plane parented to the scene
root with `top_level = true`. A downward ray finds the ground, and the plane is
scaled/faded by height. Both arm meshes use
`SHADOW_CASTING_SETTING_OFF`, so only the blob remains.

## 15. Carrying an awake climber bypassed the rule

**Symptom**

`_check_carry_links()` dropped a climber link when the target recovered, but the
host still accepted a fresh carry request for a non-ragdolling target.

**Fix**

`GameManager._authorize_carry()` now rejects `kind == 1` unless the target has
`ragdoll_active == true`, and emits
`ONLY UNCONSCIOUS CLIMBERS CAN BE CARRIED`. `GAME SMOKE` also asserts that an
awake climber cannot be grabbed. **This restriction was later removed on
purpose; see section 21 for the current rule that any teammate can be carried.**

## 16. Fall damage needed to persist without extra state replication

**Problem**

Injury had to affect stamina regeneration on the owning peer without adding a
new replicated property to every snapshot.

**Fix**

`injury`, `bandages` and fall damage are local simulation state on the climber.
`apply_fall_impact()` runs on landing, `use_bandage()` is a local action, and the
existing signals update the HUD. Only stamina, stretch and ragdoll remain in the
replication config; no RPC was added for healing.

## 17. New pickups and models broke the old validation counts

**Symptom**

`GAME SMOKE` expected exactly two `climb_items` nodes and `CLIMB VALIDATION`
listed only four GLB files. Adding five bandage pickups and four new models made
both checks fail.

**Fix**

- The smoke test now checks `items.size() >= 7`, at least five bandage pickups
  and at least six `climb_enemies`.
- The validation test checks all eight model paths, the `bandage` and
  `drop_jetpack` actions, and the new climber methods/properties/signals.
- `assets/blender/generate_items.py` exports `bandage.glb`, `cabin.glb`,
  `rock.glb` and `enemy.glb` alongside the original four models.

## 18. Online Web multiplayer needed a transport other than ENet

**Problem**

Browsers expose no UDP sockets, so `ENetMultiplayerPeer` cannot be used in a Web
export. Hiding HOST/JOIN solved the crash but removed the requested online coop.

**Fix**

`scripts/network/web_rtc_room.gd` adds a second transport:
`WebSocketPeer` carries only signaling JSON and `WebRTCMultiplayerPeer` carries
game packets. The signaling relay (`tools/signaling_server.js`, Node.js + `ws`)
assigns id `1` to the host and `2`–`4` to joiners, then forwards SDP and ICE
messages. Only the host creates offers; clients answer. ICE candidates are
buffered until the remote description exists, which avoids the race where a
candidate arrives before the offer or answer is applied.

`Net.create_web_room()` / `Net.join_web_room()` start this transport, while the
old ENet methods keep their original Web rejections. The Web menu exposes the
signaling URL and room code and saves them in `user://web_room.cfg`. An HTTPS
page rejects `ws://` URLs because browsers block mixed content.

The relay is external infrastructure: GitHub Pages serves only static files, so
the published demo still needs a hosted signaling URL for online rooms.

## 19. Props could not become stable coop platforms

**Symptom**

A carried plank followed the carrier's hands and stayed dynamic. Teammates had
no way to hold it in place, so cooperative bridging was impossible.

**Fix**

`E` (`fix_prop`) asks the host to toggle `ClimbProp.is_fixed`. `set_fixed()`
switches the body to `FREEZE_MODE_STATIC`, clears its carrier and applies a cyan
emissive overlay. The host rejects the water bucket, the carrier of the held
prop and fixers outside `FIX_REACH`; `rpc_apply_prop_fixed()` and the sixth field
of `pack_state()` keep remote peers in sync. `find_fix_target()` prioritises
props held by another player, and the HUD shows the contextual `E` prompt.
`GAME SMOKE` now checks that a carrier cannot anchor their own object, that a
fixed prop freezes and resists grabbing, and that `E` releases it.

## 20. The tower was too forgiving and lives hid stamina pressure

**Problem**

The old level was a stack of wide ledges around a square core, and a death only
cost one of three lives. That made falls cheap and removed the need to manage
stamina or spend bandages. Separate clients also generated different obstacle
layouts because each used `Time.get_ticks_msec()` as the seed.

**Fix**

`level_generator.gd` now generates a real seeded mountain: a grid heightfield
with radial profile, ridged noise and a concave collision shape, plus narrow
irregular holds, overhangs, hazards and pickups placed relative to the slope.
The host now chooses one seed per match and sends it with the start RPC, so host
and clients build the same route. GameManager no longer stores lives or spectators; a fall respawns at the
checkpoint and adds five seconds. Hard landings, enemy strikes and wind gusts
drain stamina and add injury, which slows regeneration. The HUD removes the
effort bar and carry slot; injury only tints the single stamina bar. Tests now
assert that no `lives`/`spectator` state exists and that the procedural mountain
and its collider are present.

## 21. Cross-scene shadow error and unreachable teammate carries

**Problem**

Changing scenes queued the root-level `GroundShadow` for deletion while other
climbers still ran `_physics_process()`. Assigning `_shadow.global_position` on a
node outside the tree flooded the console with
`Condition "!is_inside_tree()" is true. Returning: Transform3D()`.
Teammate carries were also restricted to ragdolling targets, and the carried
climber's ragdoll branch ran before `_process_carried()`, so the passenger never
followed the holder. Fall damage only reduced current stamina and healed back
through regeneration, so it never created lasting pressure. Players also begun
with a bandage, making the first fall free.

**Fix**

`_update_shadow()` now returns early unless both the climber and the shadow are
inside the tree. Carry detection and `_authorize_carry()` accept awake climbers;
`set_carried_by()` recovers an active ragdoll, releases arms and lets
`_process_carried()` spring the passenger to the hold point. The watchdog checks
the `carried_by_peer` link instead of ragdoll state. `apply_fall_impact()` adds
the lost amount to `stamina_lock`; `usable_max_stamina()` excludes it from
clamping and regeneration, respawn keeps it, and only `use_bandage()` restores
it. The HUD draws that slice as a red overlay on the right of the stamina bar.
`starting_bandages` is `0` and `harpoon_reach` is `14.0`. Validation and smoke
tests check the new property, signal, methods, locked-stamina behaviour,
teammate carry and short arm reach.

## 22. Procedural mountain crash and prop drift after the gameplay changes

**Problem**

`LevelGenerator._build_mountain_surface()` called `SurfaceTool.add_color()`,
which does not exist in Godot 4 (`set_color()` must be called before each
`add_vertex()`), so startup aborted with `Nonexistent function 'add_color'`.
`_build_enemies()` also called `enemy.setup()` before adding it to the tree,
which made `setup()` write `global_position` on a node outside the tree. The
root-level ground shadow was added during `_ready()`, which Godot rejected
because the parent was busy setting up children. Finally, a fixed crate kept
interpolating towards a stale carried transform and drifted out of reach, so
the coop anchor test failed.

**Fix**

Vertex colours now use `SurfaceTool.set_color()`. Enemies are added to the tree
before `setup()`. The `GroundShadow` is parented to the climber with
`top_level` enabled, so no root child is added during `_ready()`. Fixed props
skip remote transform interpolation in `_physics_process()`, keeping an anchor
static. The smoke test uses physics frames and explicitly drops the crate next
to the fixer so it validates coop anchoring independently of physics timing.
All four previously missing GLB models are generated and imported again.

## 23. Cabin-exit banner, flat fall damage and no teammate revive

**Problem**

The HUD created a `BRING WATER TO YOUR HOUSE` banner and toggled it when the
local climber left the cabin; the user found that repeated text ugly. Fall
damage depended only on impact speed, so stepping off a ledge and falling for
many seconds felt the same as a short drop. An unconscious teammate could be
carried, but there was no way to spend a bandage on them after dropping them:
`use_bandage()` was self-only and refused to run during ragdoll.

**Fix**

The mission banner node and its visibility logic were removed from `hud.gd`;
the active phase label now says `CLIMB` instead of repeating the mission phrase,
and the in-world cabin sign remains. `climber.gd` now tracks `fall_time` only while
the climber is airborne, descending and unanchored. `_update_fall_dynamics()`
raises `gravity_scale`, lowers `linear_damp`, caps fall speed and lets
`PlayerCamera` widen FOV. `apply_fall_impact()` accepts a duration, adds it to
the effective impact speed, lowers the safe threshold and scales injury/stun,
so long falls are faster and more punishing. A `LONG FALL ...` event is pushed
to the HUD feed.

`unconscious` is now distinct from `ragdoll_active`. In multiplayer
`persistent_unconscious` stops the ragdoll timer from reviving a downed climber
for free. Carrying a downed teammate folds the ragdoll away but keeps them
unconscious; dropping them reopens the ragdoll. `find_bandage_target()`,
`use_bandage_on_target()` and `revive_with_bandage()` implement the carry →
drop → bandage flow. `GameManager` adds `request_bandage_revive` /
`rpc_request_bandage_revive` / `rpc_apply_bandage_revive` with distance and
ownership checks. A downed player can also spend their own bandage with `B`.
The ragdoll banner now says `UNCONSCIOUS - NEEDS A BANDAGE`. Validation checks
the new API, duration-scaled damage and fall acceleration; the smoke test
carries, drops and revives a teammate. All Godot headless suites pass with
`failures=0`.

## 24. Solo mode, blocked cabin door, hands-full movement and death countdown

**Problem**

The menu exposed a **PLAY SOLO** button and `Net.start_solo()` opened an
offline match, which the user no longer wanted. The mountain center sat at
`z = 9.0`, so the procedural foot rose several metres immediately in front of
the cabin door and a random boulder could land in the same corridor. Grounded
movement was disabled whenever two hands were anchored, so a carrier or a
climber holding the bucket with both hands could not walk or jump. Enemy hits
only drained the refillable part of the bar. An unconscious teammate had no
death pressure, and a badly injured climber could survive another fall at zero
stamina.

**Fix**

The solo button, its handler, the `start_solo()` transport and the old solo test
were removed; `solo_test.gd` now asserts that no solo entry point exists. The
mountain center moved to `z = 16.0` and `_build_rocks()` skips
`abs(x) < 4.5 && -12 < z < -2.5`, leaving flat ground at the door (verified in
the smoke test). `_update_stamina()` regenerates only in the grounded branch,
`apply_enemy_strike()` locks the lost stamina red until a bandage, and
`_update_arm_visuals()` animates new `LeftFoot` / `RightFoot` meshes. Walking
and jumping no longer check `count_anchors()`, and the bucket releases anchors
and blocks new ones. Each climber owns a `TailRope` that teammates can grapple
or carry with kind `2` and fling before it returns home.

`is_critically_damaged()`, `_collapse_from_fall()`, `unconscious_time`,
`death_progress` and `get_death_time_left()` implement the downed death clock.
The timer advances only while ragdolled and uncarried, warns at 25/50/75%, and
ends in `died("unconscious")`; being carried pauses it but still requires a
bandage. The HUD banner shows the remaining seconds. Validation and smoke
tests cover the removed solo API, feet/tail nodes, door clearance, critical
collapse, timer death and carry pause.

## 25. Two character classes were missing from the climb mechanics

**Symptom**

Every climber was identical: any awake teammate could be carried, and every
climber had a usable grappling tail. The requested Strong/Elastic duo could not
perform its signature moves: a Strong throwing an Elastic teammate higher,
and an Elastic tensioning its tail into a rope for the Strong to climb.

**Cause**

`Climber.configure()` carried no type information, `Net.players` entries stored
only name/colour/ready, and `_authorize_carry()` accepted any awake climber as a
passenger. `TailRope.can_be_grappled()` only checked for a live owner, so all
tails behaved the same. Dropping a passenger called `set_carried_by(0)` with no
throw impulse.

**Fix**

`scripts/game/character_type.gd` defines `STRONG` and `ELASTIC`. The lobby adds
a class selector; `Net.set_character_type()` and `_rpc_register_character()`
transport the choice into every lobby entry, and `_spawn_climber()` passes it to
`Climber.configure()` and `get_state()`. `can_carry_climber()` and
`_authorize_carry()` allow anyone to carry a downed teammate but restrict awake
passengers to a Strong carrying an Elastic. `_clear_carry_link()` calls
`Climber.launch_from_carry()` with forward + upward velocity when that pair is
released, so the Elastic is thrown high toward the carrier's camera direction.

`TailRope` now takes an `elastic` flag: a Strong tail is hidden, has no
collision and cannot be grappled. An Elastic holds `Q` to call `set_tension()`,
which stretches a kinematic rope body toward the camera and replicates through
`rpc_apply_tension`; the HUD shows `Q: ROPE TAIL`, and stamina drains while the
rope is out. The full validation and gameplay smoke suites were extended to
check type APIs, gating, the throw impulse and tail gating, and they pass with
`RESULT PASSED`.

## 26. Rope tail crossed walls and same-class lobbies could start

**Symptom**

The Elastic rope stretched straight through walls and the mountain. A thrown
tail also flew through solid rock. Separately, a lobby where every player had
picked the same class could still start a match, even though neither signature
move works without both Strong and Elastic.

**Cause**

The tensioned rope is a frozen kinematic body whose `global_transform` is
written directly each frame, so Godot never ran a collision query for it. The
released tail was on collision layer 4 with mask 1, while world bodies are on
layer 1 with mask 1; Godot requires both directions to match, so no contact was
registered. `start_match()` had no roster validation at all.

**Fix**

`TailRope._clamp_length_to_walls()` raycasts from the owner origin along the
tension direction against layer 1, excludes the owner and the rope itself, and
shortens the rope to the first hit minus `WALL_MARGIN`. The clamped length is
then replicated, so every peer draws the same stopped rope. On release the tail
temporarily joins layer 1 with mask 1 so it physically bounces off the world,
and `_reset_to_owner()` restores layer 4 / mask 0.

`Net.has_both_classes()` now checks the roster for at least one Strong and one
Elastic. `start_match()` rejects smaller or single-class lobbies through the
new `match_start_rejected(reason)` signal, and the menu disables START MATCH
with a clear requirement message. Validation checks both the class gate and the
wall clamp; the two-process ENet harness confirms that a solo start is rejected
and that the match starts once the Elastic guest registers.

## 27. Thrown Elastic lost its launch velocity on frozen remote bodies

**Symptom**

The smoke test sometimes reported a zero upward velocity after a Strong threw
an awake Elastic, even though the host computed the correct impulse.

**Cause**

The passenger is a remote `RigidBody3D` frozen in kinematic mode. Writing
`linear_velocity` on that body is not enough: the physics step can discard it,
and in a real match the host does not simulate the passenger at all — only the
owner peer does. The impulse was never replicated.

**Fix**

`GameManager._clear_carry_link()` now calls
`target.rpc("rpc_carry_launch", velocity)` in addition to the local call.
`Climber.rpc_carry_launch()` accepts only the server as sender and calls
`launch_from_carry()` on the owner peer, where the body is live and the velocity
really moves it. `last_launch_velocity` stores the applied value so validation
is independent of frozen-body physics timing. The throw vector also flattens
camera pitch, and the smoke test zeroes a falling carrier before releasing so
the expected arc is deterministic.

## 28. Slack/yanked rope, missed F grab and manual class selection

**Symptom**

A teammate could pass through a wall when the Elastic let the rope tail go; a
thrown tail could still skip thin rock; a Strong standing next to an Elastic
sometimes grabbed the tail with `F` instead of the teammate, so the high throw
never happened. Players also had to pick their class manually.

**Cause**

The tensioned tail is a frozen kinematic body whose transform snaps back to the
owner when `Q` is released. A grappling teammate's anchor kept pointing at that
body, so the snap applied a huge pull toward the owner through any intervening
wall. The released tail was a thin fast capsule without swept collision. The
`F` raycast scanned layer 4 (tails/props) before layer 2 (climbers), and the
fallback loop checked tails before eligible climbers, so the nearer rope won.
Class choice was a local UI value transported by `_rpc_register_character()`.

**Fix**

`TailRope._release_grapplers()` runs on both the owner and the remote peers
through `rpc_apply_tension()`; `Climber.release_tail_anchor()` drops only arms
anchored to that tail owner before the snap. The final slack is additionally
sent with the reliable `rpc_release_tail_slack(version)` because the throttled
tension stream is unreliable; monotonic versions stop an old packet from
cancelling a newer tension. A thrown tail now keeps layer 4 for
grapples, adds world layer 1 with mask 1, and enables Godot 4.6's boolean
`continuous_cd` for swept shape collision.
`Climber._request_carry()` checks climbers before tails in both the raycast and
fallback paths. Classes are now host-assigned by `Net.assign_character_types()`:
host Strong, guests alternate Elastic/Strong/Elastic by join order; the manual
selector and `_rpc_register_character()` are removed. Validation and gameplay
smoke tests cover the auto roster, slack-rope release, thrown-tail collision,
and `F` priority; the two-process ENet harness confirms auto classes.

## 29. Feet disappeared through the floor

**Symptom**

The climber's shoes visibly sank into the cabin floor and every solid surface,
especially while walking; the whole body looked slightly buried.

**Cause**

`CapsuleShape3D_body.height` was `0.9`, which in Godot is the *total* capsule
height, while `CapsuleMesh_body.height` was `1.7` (verified with both debug
AABBs: `-0.45..0.45` versus `-0.85..0.85`). The physics body therefore rested
0.4 m above the ground while the visual body reached 0.4 m below it. On top of
that, the walk animation used `-0.78 - lift` for the trailing foot, pushing it
another 0.12 m under the visual floor, and foot rotation lowered a toe further.
The seven hidden ragdoll parts were also live kinematic bodies on the world
layer near the origin; they pushed the standing capsule up by ~0.23 m and made
foot/ground contact unreliable.

**Fix**

The body collider height now matches the visible capsule at `1.7`, so the
standing centre is the correct 0.85 m above the floor. Foot visuals use a
`FOOT_GROUND_Y` contact plane just above the collider underside, alternate
upward-only lifts, and add a tilt clearance computed from the shoe box and its
rotation, so every phase of the walk cycle stays above the floor. Ragdoll parts
keep collision layers/masks at zero while inactive and restore them only in
`activate()` / `activate_remote()`. Validation
compares the collider with the body mesh and sweeps 16 walk phases against the
collider underside.

## 30. Strong could not throw the carried Elastic with Q

**Symptom**

`F` grabbed and dropped an awake Elastic, but there was no separate hand-throw
key. `Q` only tensioned the Elastic tail, so a Strong holding a teammate had no
way to launch them deliberately.

**Fix**

The Strong's hand-held passenger is now drawn with two hands, and `Q` calls the
new host-authoritative `request_throw_elastic()` RPC. It validates the carry
link and the Strong/Elastic pair before clearing the link; `_clear_carry_link()`
applies the existing camera-direction `launch_from_carry()` impulse on the
owning peer. `F` remains the gentle drop, the HUD advertises both keys while a
teammate is held, and the Elastic tail ignores `Q` while that teammate is
carried.

## 31. Elastic could climb instead of relying on the Strong's throw

**Symptom**

The Elastic could fire grappling hands and winch up like the Strong, so the
Strong's carry/throw duo mechanic was optional and the throw height felt weak.

**Fix**

`Climber.can_climb()` now gates all grapple, winch and mantle logic and returns
true only for Strong. For an Elastic, `_process_climb()` releases any stale
anchors and skips arm input/wheel/arm forces, while `_fire_arm()` emits an
explicit "ELASTIC CANNOT CLIMB" notice. The Elastic still tensions its tail with
`Q` so the Strong can climb it. `STRONG_THROW_UP` was raised from `11.0` to
`22.0` with reduced forward speed, and the HUD marks the Elastic as
`NO CLIMB`.

## 32. Strong needed an easier way to launch the Elastic

**Symptom**

`Q` only threw an Elastic that was already being carried after a separate `F`
pickup, so the throw was easy to miss in the heat of climbing.

**Fix**

`Q` now also performs a one-key quick throw: `Climber._request_throw_elastic()`
finds the nearest awake Elastic within `carry_reach`, and the host-authoritative
`request_quick_throw()` / `rpc_request_quick_throw()` validate the Strong/Elastic
pair, the sender id and the distance before applying and immediately clearing a
carry link. The existing carry-and-throw path stays unchanged, `F` remains the
gentle drop, and the Strong HUD advertises `[Q: THROW ELASTIC]`. Picking up an
awake Elastic also announces `ELASTIC HELD - Q TO THROW / F TO PUT DOWN`, and the
cabin caption reads `CARRY / Q THROW`.

## 33. Elastic fell as hard as Strong

**Symptom**

A thrown Elastic could lose as much stamina and injury as a Strong climber from
the same landing, even though the Elastic is the rubbery class that depends on
being thrown.

**Fix**

`apply_fall_impact()` now applies `elastic_fall_damage_scale = 0.45` and adds
`elastic_fall_safe_speed_bonus = 3.0` to the safe speed for Elastic, while Strong
keeps the original values. Damage, stamina lock, injury and stun all scale with
the reduced loss.

## 34. Cabin exit blocked and platforms too tight

**Symptom**

Low rock/ledge geometry could sit in the cabin doorway, and several mountain
platforms were too small to land on comfortably.

**Fix**

`_height_at()` now flattens a broad corridor from the cabin door out to the
first climbable slope, and `_build_rocks()` plus low ledge/rib generation skip
that corridor. Ledge width/depth ranges, moving platforms, checkpoint pads and
the summit pad were enlarged. The Strong's simple two-hand lift remains the
`F` pickup; `Q` is only the throw, and a gentle `F` drop never launches the
Elastic.

## 35. F drop still launched the Elastic

**Symptom**

Pressing `F` while carrying an awake Elastic applied the same high throw as
`Q`, because `_clear_carry_link()` launched on every link removal.

**Fix**

`_clear_carry_link()` now takes `launch_elastic: bool = false`. Only
`request_throw_elastic()`, its RPC handler and the quick-throw handler pass
`true`; `F` drops, carry replacement, respawns and watchdog cleanup keep the
default and simply release the passenger.

## 36. Cooperative mode had to become a competitive summit race

**Symptom**

The game was still a cooperative climb: a cabin delivery mission with a water
bucket, three lives, fall damage, bandages, injuries, stamina locks, teammate
carrying, Strong/Elastic classes, grappleable tails, fixed props and a solo
entry point. The requested race had no winner condition, no shared flat start
and no time penalty for falls.

**Cause**

Those mechanics were spread across every layer: `Net` assigned classes and
started solo matches, `GameManager` tracked lives and mission state, `Climber`
owned carry links and bandage/backpack fields, `LevelGenerator` built the cabin
and tutorial signs, and the tests and docs still asserted the old contract.

**Fix**

- `GameManager` now owns a three-phase race: countdown, 300 s active timer,
  ended. The summit hazard calls `_finish_match(pid, "SUMMIT")` immediately.
  Timeout uses `_best_player_id()` with reason `TIME UP` and score
  `altitude * 10 - penalty`. `_handle_death()` adds `RESPAWN_PENALTY = 5.0`
  seconds and respawns at the last checkpoint; lives, spectators and health
  were removed.
- `LevelGenerator` builds a flat start pad at `(0, 0.9, 2)` on the lower shoulder
  of the mountain with four evenly spaced spawn points at `y = 1.95`. The
  mountain profile flattens the same band, so nobody begins on a slope or
  outside the rock. The cabin, mission sign, bucket, crates, planks and control
  drawings were removed. Only four trampolines, two jetpacks, three checkpoints,
  enemies and the summit remain.
- `prop.gd` is a static trampoline-only boost pad with a bounce `Area3D`.
  `item_pickup.gd` only grants jetpack fuel. `Climber` keeps grapple hands,
  stamina, ragdoll stumbles, feet, camera, jetpack and fall dynamics; carry,
  bandage, injury, unconsciousness, stretch and class state are gone. Ragdoll
  always recovers on its own, so a fall never needs a teammate.
- `Net.start_match()` now refuses lobbies with fewer than two players via
  `match_start_rejected`. There is no solo transport and no class assignment.
  Desktop still uses ENet on port `7777`; Web still uses WebRTC with WebSocket
  signaling.
- `scripts/game/character_type.gd` and `scripts/player/tail_rope.gd` were
  deleted, together with the `carry` input action, obsolete GLBs and their
  Blender generator functions.
- The HUD shows race time, altitude, stamina, jetpack, leaderboard and winner
  overlay. It no longer shows health, effort, carry slots, bandages or mission
  banners. The menu title is `SUMMIT RACE`.
- Tests and documentation were rewritten around the race contract. A cleanup
  pass initially left an over-indented `if ragdoll_active:` block in
  `_process_climb()`, which produced `Parse Error: Expected statement, found
  "Indent"` at `climber.gd:793`. The indentation was repaired and headless
  import now completes without script errors.

## 37. Racers spawned outside the mountain and the route was hard to read

**Symptom**

At the start of a race the climbers appeared next to the mountain instead of on
it, and the mountain face was dim enough that the upper route was hard to see.

**Cause**

The start pad sat at `z = -2`, just outside the mountain footprint which begins
near `z = -3`. The first-person camera also started at yaw `0`, looking along
`-Z` away from the summit at `z = 16`. The directional light was angled low
(`-43°`) and the exponential fog density was `0.0045`, so the 142 m route faded
into shadow and haze.

**Fix**

The start pad and spawn points first moved to `z = 2` on the lower shoulder,
with the flatten band extended to `z = -4..8`. That made the pad level but left
a sheer cliff at its far edge. The final layout is described in section 38.
`PlayerCamera.setup_local()` starts at `START_YAW = PI`, so every racer looks
straight at the summit. The sun is placed at `y = 180` with a steep `-86°`
angle, the shadow range was raised to 260 m and fog density dropped to
`0.0025`, making the whole climb visible.

## 38. A sheer wall blocked the entrance to the mountain

**Symptom**

Racers could not leave the start pad: the flattened band ended abruptly and the
procedural height jumped from 1 m at `z = 8` to more than 55 m at `z = 10`.

**Cause**

`_height_at()` forced the terrain to 1 m through the whole pad area, then
blended back into the mountain profile over only 3 m. Because the mountain
profile is very steep near the base, that blend produced a near-vertical face
with no grips, so the route was physically unreachable.

**Fix**

The pad returned to the natural foot of the mountain at `z = -2`, raised to
`y = 2.0` so its top is `2.2` and racers spawn at `y = 3.05`. Its depth was
reduced to 4 m. The flatten band now only covers the pocket under the pad
(`z = -4..0`) and releases by `z = 2`, so heights rise continuously:
1 m at `z = 0`, 12.6 m at `z = 2`, 22.9 m at `z = 4`. Validation now rejects
any height jump over 20 m between consecutive 2 m samples in the entrance. The
generated obstacles on that slope were removed in section 39.

## 39. Generated ribs walled off the entrance and joiners got a random name

**Symptom**

Racers still could not enter the mountain: vertical wall ribs and ledges from
the procedural route sat across the lower front face. Separately, a player who
joined saw the name `Player 41646665` instead of the display name typed in the
menu.

**Cause**

`_build_mountain_routes()` only skipped low holds below `y = 8` near `z < 2`.
Ribs 6.2 m tall and their overhangs were placed from `y = 4` upward, so they
formed a literal barrier in front of the guaranteed holds. The boulder exclusion
zone was equally short. On the network side, only ENet clients called
`_rpc_register_name()`. WebRTC clients never sent the RPC; the host therefore
kept the placeholder `_default_name_for(id)`, which is `Player <peer id>`. A
race between that placeholder entry and a fast-arriving name RPC could also
overwrite the real name.

**Fix**

The whole entrance corridor (`|x| < 8`, `z < 12`, `y < 42`) is now reserved for
the climb: ledges, ribs, overhangs and boulders skip it. `_build_start_holds()`
places thirteen grips with `_entrance_z_for_height()`, spaced 2.5 m in altitude
and alternating around `x = ±1.3`, with rest ledges every third grip. Smoke
validation now checks the grip spacing and rejects any generated wall in that
corridor.

Both ENet and WebRTC clients now call `_register_name_with_host()`. The host
preserves an existing name when `peer_connected` arrives late and broadcasts the
corrected roster, so the lobby, leaderboard and climbers all use the chosen
display name.
