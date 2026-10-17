# Physics and combat

What's ported from *Super Smash Bros. Ultimate*, how it works here, and what isn't ported yet.
The main sources are SmashWiki's [game physics](https://www.ssbwiki.com/Category:Game_physics) pages and [ultimateframedata.com](https://ultimateframedata.com/stats).

## Units and timing

Everything runs in Ultimate's own units, so you can copy community data without converting it:

| Quantity     | Unit           | Godot conversion                         |
|--------------|----------------|------------------------------------------|
| Distance     | unit           | 10 units = 1 m (`Units.PER_METER`)       |
| Speed        | units/frame    | × 60 / 10 → m/s (`Units.velocity_to_godot`) |
| Acceleration | units/frame²   | —                                        |
| Time         | frame (1/60 s) | one physics tick                         |

Physics runs at a fixed 60 Hz (`physics/common/physics_ticks_per_second`), and one tick is one Smash frame.
Physics interpolation is on, so rendering stays smooth at any refresh rate. Call `reset_physics_interpolation()` whenever you teleport something.

The simulation is **frame-exact and ordered**: `Match._physics_process` ticks every fighter, then calls `HitResolver.resolve`, then separates overlapping fighters, then checks blast zones. Fighters never run their own physics callbacks.
That keeps hits, trades and hitlag deterministic. It's also the shape you need for rollback netcode later.

## Movement

Each fighter has three velocities. They're added together each frame and moved with `CharacterBody3D.move_and_slide` on the XY plane:

- `velocity_self`: the fighter's own motion (walking, jumping, gravity, drift).
- `velocity_knockback`: launch velocity, which decays separately (see Knockback).
- `velocity_push`: a one-frame push from overlapping fighters.

| Mechanic | Implementation |
|---|---|
| Walk | Speed follows stick tilt: `walk_speed × tilt`, approached at `walk_acceleration`. |
| Dash | A flick (stick from < 0.3 to ≥ 0.8 within 3 frames) starts a dash at `initial_dash_speed` for `dash_frames`. Flicking back re-dashes (dash dance). |
| Run | After the dash, accelerates to `run_speed` at `run_acceleration`. Releasing skids to a stop with traction; reversing does a run turnaround (`run_turn_frames`). |
| Traction | Grounded deceleration of `traction` units/frame². |
| Jumpsquat | `jumpsquat_frames` (3) on the ground before leaving it. |
| Short hop / full hop | Releasing jump before jumpsquat ends gives a short hop. So does pressing attack during jumpsquat (short hop aerial). |
| Jump height | Initial velocity is solved from the height: `v₀ = (−g + √(g² + 8gh)) / 2` (`SmashFormulas.jump_velocity`). Tests check the measured peaks. |
| Air jumps | `jump_count` includes the ground jump. Leaving the ground without jumping uses up the first one, as in Smash. Air jumps reset horizontal speed to `stick × air_speed`. |
| Gravity / fall speed | `vy -= gravity` per frame, capped at `−fall_speed`. |
| Fast fall | Tapping down at or after the peak sets `vy = −fall_speed × 1.6`. |
| Air drift | Accelerates toward `air_speed × stick` at `air_acceleration_base + air_acceleration_additional × |stick|`. With no input, or above the cap, air friction slows the fighter. |
| Landing lag | Hard landing (`hard_landing_frames`) or light landing below half the fall speed (`soft_landing_frames`). Aerials use their own `landing_lag` unless they land inside an autocancel window. |
| Soft platforms | Solid only while falling onto them from above. Flick down to drop through; hold down in the air to fall through. Godot 3D has no one-way collision, so fighters toggle per-platform collision exceptions every frame. |
| Edges | Idle, attacks, shield, landing, crouch, jumpsquat and dodges stop at platform edges. Walk, dash, run and hitstun can go off. |
| Ledges | `StageLedge` markers are grabbed when falling near them (not while holding down). The first grab since touching the ground gives 40 frames of intangibility; a new grabber trumps the current one. From the ledge: climb (toward the stage or up), jump, roll (shield) or drop (away or down). Getup frame data comes from the stats. |

## Knockback

Ultimate's formula, `SmashFormulas.knockback`:

```
KB = ((((p/10 + p·d/20) · 200/(w+100) · 1.4) + 18) · s + b) · r
```

- `p`: target's percent **after** the hit's damage.
- `d`: damage as knockback sees it. That includes the smash charge, plus 0.3× of the stale/fresh change (Ultimate rule).
- `w`: target weight.
- `s`: knockback growth / 100.
- `b`: base knockback.
- `r`: ratio. Currently only rage: 1.0 at ≤ 35% up to 1.1 at 150% of the attacker's damage.

With **set knockback** (`set_knockback > 0`), `p = 10` and `d = set_knockback`, so percent and damage don't matter but weight still does.

Then:

| Step | Rule |
|---|---|
| Crouch cancel | Knockback × 0.85 and hitlag × 0.67 when the target is crouching. |
| Angle | Degrees relative to the attacker's facing; `reverse` sends the target backward. **361 (Sakurai angle)**: grounded targets launch at 0° up to 60 KB, then lerp to 38° at 88 KB; aerial targets launch at 38°. |
| Launch speed | `KB × 0.03` units/frame, decaying by 0.051 per frame along the launch direction. Air friction doesn't apply while launched; gravity does. |
| Hitstun | `floor(KB × 0.4) − 1` frames. |
| Tumble | KB ≥ 80. Tumbling fighters spin, bounce off walls and ceilings (× 0.8), and must tech or get knocked down on landing. |
| Hitstun cancel | After 40 frames an air dodge can cancel hitstun if launch speed < 2.5; after 45 frames an aerial can if < 2.0. |
| Grounded launches | A downward launch on a grounded target bounces (× 0.8) if it tumbles, otherwise it slides. |
| Damage | `damage × charge × staleness × 1.2` (Ultimate's 1v1 multiplier). |

## Hitlag, DI and SDI

- **Hitlag**: `floor((d·0.65 + 6) · hitlag_multiplier)` frames, capped at 30. Both fighters freeze; shield hits use × 0.67.
- **DI**: on the last hitlag frame, the stick component perpendicular to the launch rotates it by up to 0.17 rad (~9.74°).
- **LSI**: on tumble launches, holding up multiplies launch speed by up to 1.095 and holding down by 0.92. No effect between 65°–115° and 245°–295°.
- **SDI**: during hitlag, each new stick direction (at most every 4 frames) moves the victim 2 units × the hitbox's `sdi_multiplier`.

## Hit detection

Hitboxes are spheres (`HitboxData`) and hurtboxes are vertical capsules from the fighter's stats (shorter while crouching or lying down).
Each active hitbox sweeps from last frame's position to this frame's, so fast moves can't tunnel through a target. A move hits each target once.
When several of its hitboxes touch the same target on one frame, the lowest `id` wins. All hits on a frame are found before any is applied, so simultaneous hits trade.

## Shield, dodges, techs

| Mechanic | Values |
|---|---|
| Shield HP | 50. Decays 0.15/frame while held, regenerates 0.08/frame otherwise. Bubble scale is `hp/50 × 0.85 + 0.15`. |
| Shield damage | `(damage + shield_damage) × 1.19`. |
| Shieldstun | `floor(d × 0.8 × shieldstun_multiplier + 2)`. |
| Pushback | `min((stun + 1) × 0.09, 1.3)` units/frame, then traction. |
| Shield drop | Held at least 3 frames; dropping takes 11 frames. |
| Out of shield | Jump, up special, jump-cancelled up smash, roll (flick sideways), spot dodge (flick down). |
| Shield break | Pops the fighter up, then dizzy (placeholder: `max(120, 400 − 2×percent)` frames); shield resets to 37.5. |
| Spot dodge / rolls | Per-character frame data in the stats (values from ultimateframedata). |
| Air dodge | One per airtime, restored on landing, ledge grab or getting hit. Neutral: keeps falling. Directional: a burst at `air_dodge_speed` that ignores gravity, then slows. Landing lag 11 / 19. |
| Tech | Press shield within 11 frames before landing while tumbling; the press locks teching out for 40 frames. Tech in place, or tech roll with the stick. Missing the tech knocks the fighter down; getup / getup roll from there. |

## Stale moves

The last 9 moves that connected, newest first. Each occurrence of a move reduces its damage by `0.09, 0.08545, 0.07635, 0.0679, 0.05945, 0.05035, 0.04255, 0.03345, 0.025`.
A move not in the queue gets a 1.05× freshness bonus. Shield hits count 0.85×.

## Input

- **Buffer**: presses stay buffered for 9 frames (Ultimate) until a state can use them.
- **Flicks** (3-frame window) drive dash, smash attacks (attack within 4 frames of a flick), tap jump, spot dodge and platform drops.
- **Smash attacks** also come from the C-stick (right stick) or the keyboard smash key.
- **Smash charge**: holding attack at the move's `charge_frame` charges for up to 60 frames, up to 1.4× damage.

## Not ported yet

Listed so nobody assumes they exist:

- Grabs, throws and pummels.
- Neutral/side/down specials (the slots exist; the data is empty), jab combos and rapid jabs.
- Perfect shield (parry), shield tilting and shield poking accuracy.
- Ultimate's "balloon knockback" (launch speed-up when hitstun > 32 frames). Strong hits currently fly at Smash 4 speed.
- Ultimate's fixed 1.8 fall speed during hitstun for 70°–110° launches.
- Ledge regrab limits, ledge attack and ledge intangibility scaling.
- Wall/ceiling techs, jab locks, footstools, crouch-walk, teetering, items.
- Hitbox types (projectiles, windboxes, electric/flame effects), armor and per-move intangibility.

## Known differences from Ultimate

- **Full-hop airtime**: jump heights match the stats exactly (tests measure them) and short-hop airtime matches ultimateframedata (Mario 40 frames).
  But constant gravity gives longer full hops than Ultimate lists, 61 vs 56 frames for Mario's stats (the test suite prints it).
  Ultimate seems to treat full hops differently. Revisit this if full hops feel floaty.
- Shield break stun, tech/getup timings, air dodge landing lag and directional air dodge speed are approximations; SmashWiki doesn't list exact Ultimate values.
- The 1v1 damage multiplier applies to damage dealt (and so to percent), not to the knockback formula's `d`.
