# Climb Together

**Demo:** <https://peakbuild112000.github.io/Project1/>  
**Repository:** <https://github.com/peakbuild112000/Project1>  
**Engine:** Godot 4.6.1 stable

A hard, fast, physics-driven 3D climbing game for 1–4 players. Climb a tall
procedural mountain, bring a huge water bucket back to your cabin without
spilling it, survive falls, use the environment and your friends as stepping
stones, and try not to ragdoll in front of everyone.

> The Web build supports online multiplayer through WebRTC. Browsers do not
> allow ENet/UDP sockets, so Web rooms need a small WebSocket signaling server
> (included in `tools/`). Online play always uses a room; there is no offline
> solo mode.

## Contents

- [Demo](#demo)
- [Features](#features)
- [Run from source](#run-from-source)
- [Controls](#controls)
- [Rules](#rules)
- [Objects and strategy](#objects-and-strategy)
- [Multiplayer architecture](#multiplayer-architecture)
- [Web export](#web-export)
- [Project layout](#project-layout)
- [Validation](#validation)
- [Errors encountered](#errors-encountered)
- [License](#license)

## Demo

The GitHub Pages build is published at:

<https://peakbuild112000.github.io/Project1/>

Recommended browser: a recent Chrome, Edge, Firefox or Safari with WebGL2
enabled. Use **HOST ROOM** / **JOIN ROOM** with a signaling URL and a shared
room code for online play. Desktop builds keep the original ENet host/join flow
on UDP port `7777`.

## Features

- Two independent grappling hands with ropes, winch, swing, rappel and mantle.
  Arm reach is deliberately short (14 m), so holds must be earned one by one.
- Stamina with no separate health bar. All damage is paid directly with stamina;
  there is no effort bar on the HUD. Heavy loads still build internal effort and
  overload drops every anchor and starts a full ragdoll.
- Fall damage is permanent: hard landings turn part of the stamina bar red and
  unusable until a bandage is spent. The longer you fall, the faster gravity
  pulls, the wider the camera FOV gets, and the worse the impact is. A fall that
  empties an already badly injured climber's bar knocks them unconscious. Enemy
  strikes lock their stamina damage permanently too; wind gusts drain the usable
  part only. Stamina regenerates on solid ground only.
- Total carried weight slows walking, jumping and winching. The jetpack itself
  counts toward the load and can be removed when empty.
- Coop scaffolding: one climber carries a crate or plank with `F` while a
  teammate presses `E` to anchor it as a temporary platform. `E` again releases
  it. The carrier cannot anchor the object they are holding.
- Physics-driven crates, planks, trampolines and a large water bucket.
- The bucket can be carried with `F`, pushed with the body, or hooked with either
  hand. Pulling it sideways tips it and spills water. Carrying it uses both
  hands visibly.
- Two character classes are assigned automatically: **Strong** and **Elastic**.
  The host is always Strong; guests alternate Elastic, Strong, Elastic in the
  order they join, so a two-player lobby always has both. A Strong climber can
  grab an awake Elastic teammate with `F`, carry them in both hands and press
  `Q` (QWERTY) to throw them forward and high toward the direction the Strong
  climber is looking; `F` puts them down gently. A nearby rope tail never steals
  that `F` grab. Any class can carry a
  downed teammate to safety, but an awake climber can only be lifted by a Strong
  carrying an Elastic.
- The **Elastic** climber owns a rope tail. Hold `Q` to stretch it into a long
  grappling line toward the camera; a Strong teammate can hook that line with a
  hand and climb it. The Elastic pays stamina while the rope is stretched, and
  the rope stops at the first wall instead of passing through it. Releasing `Q`
  drops any teammate grappling the rope, so slack cannot yank them through
  walls. The tail can also be grabbed with `F`, carried and thrown; it collides
  with the world (with swept collision) and flies briefly before returning to
  its owner. Strong climbers have no usable rope tail.
- A downed teammate has a death countdown, which pauses while carried, but they
  stay down until someone spends a bandage on them. Feet are animated, and
  walking and jumping work even when both hands are occupied. The bucket is held
  with two hands.
- One jetpack slot only. Fuel can be refilled, but the item never duplicates.
- Starting cabin with control pictograms and a large
  **BRING WATER TO YOUR HOUSE** mission sign in the world.
- A seeded procedural mountain with a real sloping rock/snow surface, narrow
  irregular holds, overhangs and a steep summit cap.
- Checkpoints, wind gusts, brittle holds, moving platforms and patrolling enemy
  drones get harder near the summit. There are no lives: falls cost time.
- A narrow alternate spire with small sloped holds, wide gaps and sharp
  overhangs for expert climbers.
- Low-poly GLB models (jetpack, trampoline, plank, crate, bandage, cabin, rock,
  enemy) generated by a Blender / bforartists script. Procedural sound effects.

## Run from source

Install Godot 4.6.1 or newer, then open the project folder.

PowerShell example:

```powershell
$godot = "C:\Users\PC\Desktop\Godot\Godot_v4.6.1-stable_win64_console.exe"
$project = "C:\Users\PC\Documents\project-1"

& $godot --headless --path $project --editor --quit
& $godot --path $project
```

The main menu opens first.

- **HOST** opens an ENet server. Ask friends to join your IP on the chosen port.
- **JOIN** connects to a host. Clients click **READY**; the host clicks
  **START MATCH** directly.
- LAN works out of the box. Online play needs port forwarding or a tunnel for
  UDP port `7777`, or any port selected in the menu.
- The match needs both classes at the table: at least one **Strong** and one
  **Elastic**. Classes are automatic, so START MATCH unlocks as soon as a second
  player joins; the host is told why if a lobby is still too small.

## Controls

| Input | Action |
| --- | --- |
| Mouse | Look / aim |
| W A S D | Move, swing, walk |
| Left mouse | Fire left grappling hand |
| Right mouse | Fire right grappling hand |
| Space | Jump, release, mantle near a ledge |
| Mouse wheel | Winch in / let out rope |
| F | Grab or release the nearest free object, teammate or grappling tail |
| Q (hold, Elastic only) | Stretch the rope tail toward the camera for a teammate to climb |
| E | Fix or release a nearby crate/plank (coop scaffolding) |
| Shift (hold) | Use the equipped jetpack |
| B | Use a bandage on yourself, or on a nearby/carried downed teammate |
| G | Remove an empty jetpack (also available as a HUD button) |
| T | Chat |
| Tab | Scoreboard |
| Esc | Release / capture the mouse |

## Rules

- There are no lives. A fall respawns you at your checkpoint and adds
  5 seconds to your time.
- Checkpoints at 26 m, 64 m and 104 m save your respawn point.
- Hard landings and enemy strikes lock part of the stamina bar permanently (red,
  unusable) and add injury; wind gusts drain what is left. Stamina refills only
  while standing on solid ground, never in mid-air. Injury slows regeneration.
  Bandages are the only way to unlock red stamina, and nobody starts with one.
- If a badly injured climber empties their bar in another fall, they collapse
  and become unconscious. A countdown starts: being carried by a teammate pauses
  it, but only a bandage stops it for good. If it runs out, the climber is out
  and respawns at their checkpoint with the usual time penalty.
- Wind gusts, brittle holds and enemy drones get harder near the summit.
- Everyone spawns inside the cabin. The mission is written on the cabin sign;
  no extra HUD banner appears when you leave.
- Bring the full bucket from the summit back to the cabin. Delivering any water
  wins the match. Emptying the bucket fails the delivery.
- The bucket stays physical. Hook it, drag it, push it, or carry it with both
  hands. Tilting, spinning and hard landings spill water.
- If nobody delivers water within 300 seconds, the highest score wins:
  `altitude × 10 − penalties`.
- Holding crates, planks, trampolines, the bucket or another climber drains
  stamina every second. Heavier loads drain more and slow movement.
- Hard landings below the safe fall speed lock stamina and add injury; injury
  reduces regeneration. Longer falls accelerate, widen the camera view and lock
  more stamina on impact. A bandage unlocks red stamina, eases injury and can
  revive a teammate. The HUD shows the locked slice in red and tints the rest
  when injured; there is never a separate health bar.
- Teamwork tip: a teammate can anchor a carried crate or plank with `E`, making a
  stable step or bridge; anyone nearby can release it again with `E`.
- If internal effort stays in the red zone, your hands let go and you ragdoll,
  dropping every anchor and carried object. There is no effort bar or carry slot
  readout. A downed teammate can be carried, dropped with `F`, and revived with
  `B` while holding a bandage. A Strong climber can also carry an awake Elastic
  teammate and throw them high by pressing `F` again.
- There is no manual arm-stretch button and no ball mode. `Q` is not an arm
  stretch: it tensions the Elastic rope tail only. The camera stays at head
  height and does not roll. A soft ground blob shadow replaces the long arm
  silhouette.

## Objects and strategy

- **Crates** are heavy, stackable stepping stones. Stable, but exhausting.
- **Planks** are long physical bridges. Drop one across a gap, then climb it, or
  have a teammate anchor it mid-air while you carry it.
- **Fixed objects** glow cyan. They are static until someone presses `E` nearby
  to release them; the water bucket cannot be anchored.
- **Trampolines** are heavy but launch climbers who land on them.
- **Jetpack** is the only equippable item. Pick it up once, hold `Shift` to fly
  briefly, and refill the same slot later. Press `G` to drop an empty one.
- **Bandages** are consumables placed along the route. Nobody starts with one.
  Press `B` to unlock red fall-damage stamina, reduce injury, or revive a
  nearby/carried downed teammate.
- **Enemy drones** patrol fixed local loops. Each peer applies its own hit
  locally, so no network RPC is needed for them.
- **Difficult pillar** is a narrow alternate spire with tiny brittle holds and
  sharp overhangs for players who want a harder route.
- **Other climbers** can be grabbed while awake or unconscious; their movement is
  disabled while carried. Unconscious teammates wait for a bandage in multiplayer
  and can be dropped and revived anywhere on the mountain.
- **Water bucket** is the heaviest carryable object. Keep your body upright on
  the way down, or use two hands and let the ropes absorb the swing.

Every free prop is simulated by the host. The host arbitrates grabs, drops,
pickups, carry links and hand forces, then broadcasts compact state to peers.

## Multiplayer architecture

- `Net` wraps two transports: `ENetMultiplayerPeer` on desktop and
  `WebRTCMultiplayerPeer` on Web. Both expose the same authoritative RPC flow.
- Web rooms use `scripts/network/web_rtc_room.gd`: a WebSocket signaling client
  assigns ids, relays SDP offers/answers and ICE candidates, then game packets
  travel directly between browsers. The host is always peer id `1`.
- One authoritative controller per player: each peer simulates its own
  `RigidBody3D`.
- Remote climbers are frozen kinematic bodies. They receive
  `replicated_position` and `replicated_yaw`, then interpolate locally. Physics
  transforms are never written directly by the synchronizer.
- The host owns the countdown, timer, checkpoints, winner, chat relay,
  item pickups, prop states, carry links, bandage revives and fixed/unfixed
  props. Item pickups include bandages as well as jetpacks.
- Hand pulls on the bucket use `rpc_report_prop_pull`; the host validates the
  sender and applies a capped impulse with torque.
- Enemy drones follow deterministic local patrol routes; each climber applies
  its own hit locally, so they need no network state.
- `MultiplayerSpawner` uses `spawn_path = NodePath("../Players")`.
- Replication paths use `NodePath(".:property")`.

See `docs/DESIGN.md` for the full contract.

## Web export

The repository includes `export_presets.cfg` with a `Web` preset. Export command:

```powershell
$godot = "C:\Users\PC\Desktop\Godot\Godot_v4.6.1-stable_win64_console.exe"
$project = "C:\Users\PC\Documents\project-1"
$out = "$env:TEMP\opencode\web-demo\index.html"

& $godot --headless --path $project --export-release "Web" $out
```

The published demo lives on the `gh-pages` branch. Rebuild and publish it with:

```powershell
$demo = "$env:TEMP\opencode\web-demo"
git worktree add "$env:TEMP\opencode\gh-pages" gh-pages
Copy-Item "$demo\*" "$env:TEMP\opencode\gh-pages" -Recurse -Force
New-Item "$env:TEMP\opencode\gh-pages\.nojekyll" -ItemType File -Force | Out-Null
```

ENet is desktop-only. Online Web rooms need the included signaling relay,
because browsers cannot open UDP sockets:

```powershell
cd tools
npm install
npm start
```

The relay listens on port `9080` by default (`PORT` and `HOST` can be changed
through environment variables). Enter its public URL in the Web menu, for
example `ws://localhost:9080` for local testing or `wss://your-host/signal`
behind an HTTPS reverse proxy. An HTTPS page must use a `wss://` URL because
browsers block mixed content.

One player clicks **HOST ROOM** with a room code (3–12 letters or digits).
Friends enter the same code and click **JOIN ROOM**, up to 4 players. The
**READY** and **START MATCH** flow is unchanged. The signaling server never sees
gameplay packets; it only forwards WebRTC offers, answers and ICE candidates.
It is not bundled with GitHub Pages, so you need to host it separately to play
online from the published demo. The included transport uses public Google STUN
servers; players behind very restrictive NATs may need a TURN server added to
`ICE_SERVERS` in `scripts/network/web_rtc_room.gd`.

## Project layout

```text
scenes/
  main_menu.tscn        menu, lobby, chat, host/join
  climber.tscn          player body, arms, feet, tail, camera, ragdoll
  game.tscn             arena, HUD, spawner, match controller
scripts/
  network/              ENet + WebRTC transports and lobby state
  player/               climbing, camera, arms, ragdoll
  game/                 level, props, hazards, items, match rules
  ui/                   HUD and menu
  audio/                procedural SFX
assets/
  models/               generated GLB models
  blender/              bforartists/Blender generator script
docs/
  DESIGN.md             implementation contract
  ERRORS.md             errors encountered and fixes
tests/                  headless validation and ENet harnesses
tools/                  WebSocket signaling relay for WebRTC rooms
export_presets.cfg      Web export preset
```

## Validation

Run every local check:

```powershell
.\tests\run_tests.ps1
```

Expected summary:

```text
NO SOLO failures=0
REMOTE VISUAL failures=0
UPRIGHT failures=0
CAMERA YAW failures=0
CLIMB VALIDATION failures=0
GAME SMOKE failures=0
STATIC BAD: 0
EMPTY FILES: 0
```

The two-process ENet harnesses additionally verify host/join, carry links and
smooth remote movement:

```powershell
$exe = "C:\Users\PC\Desktop\Godot\Godot_v4.6.1-stable_win64_console.exe"
$proj = "C:\Users\PC\Documents\project-1"
$tmp = "$env:TEMP\opencode"

$serverProc = Start-Process -FilePath $exe -ArgumentList @("--headless", "--path", $proj, "--script", "$tmp\climb_net_host_test.gd") -PassThru -NoNewWindow
Start-Sleep -Seconds 2
$clientProc = Start-Process -FilePath $exe -ArgumentList @("--headless", "--path", $proj, "--script", "$tmp\climb_net_client_test.gd") -PassThru -NoNewWindow
Wait-Process -Id $serverProc.Id, $clientProc.Id -Timeout 90
```

Do not replace those precise PIDs with a wildcard `Stop-Process` call.

## Errors encountered

All real issues found during development are documented in
[`docs/ERRORS.md`](docs/ERRORS.md). It covers the replication path bug, the
remote-avatar teleport, stuck arm visuals, camera roll, spawner paths, offline
authority, the bucket/hands issue, fall injuries, unconscious-only carries,
ground-only stamina, permanent enemy damage, the blocked cabin door, grapple
tails, the downed death clock, Web hosting, WebRTC signaling, coop anchoring,
harmless headless warnings, and PowerShell harness pitfalls.

## License

See [`LICENSE`](LICENSE).
