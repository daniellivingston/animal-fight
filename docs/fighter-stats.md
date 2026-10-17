# Fighter stats

Each character is a `FighterData` resource (`fighters/roster/<name>/<name>.tres`) with three parts: a model scene, `FighterStats` (attributes) and a `Moveset` (attacks).
Stats use *Super Smash Bros. Ultimate* units (see [physics.md](physics.md#units-and-timing)), so you can compare them with [ultimateframedata.com/stats](https://ultimateframedata.com/stats) and copy values from it.

`FighterStats` defaults to **Mario's Ultimate values**. Godot only saves values that differ from the defaults, so a `.tres` file lists what makes that character different from Mario.
Changing a default in `fighter_stats.gd` therefore changes every character that relies on it.

## Attributes

Ranges are the extremes across Ultimate's cast (holder in brackets), from ultimateframedata.

| Stat | What it does | Ultimate range | Cat | Bear |
|---|---|---|---|---|
| `weight` | Knockback resistance (`200/(w+100)` in the formula). | 62 (Pichu) – 135 (Bowser) | 98 | 130 |
| `height`, `radius` | Hurtbox and collision capsule (units). Bigger is easier to hit. | — | 15 × 4 | 20 × 6.2 |
| `crouch_height_ratio` | Hurtbox height while crouching. | — | 0.6 | 0.6 |
| `walk_speed` | Max walk speed at full tilt. | 0.62 (Incineroar) – 1.575 (Marth) | 1.155 | 1.0 |
| `walk_acceleration` | How fast walking reaches its target speed. | — | 0.15 | 0.12 |
| `initial_dash_speed` | Speed on the first dash frame. | 1.45 (Steve) – 2.45 (Mythra) | 1.936 | 2.1 |
| `dash_frames` | Initial dash length; shorter means snappier dash dances. | 7 (Sheik) – 16 (Robin) | 10 | 14 |
| `run_speed` | Max run speed. | 1.18 (Incineroar) – 3.85 (Sonic) | 1.76 | 1.85 |
| `run_acceleration` | Dash speed → run speed per frame. | — | 0.1 | 0.09 |
| `run_turn_frames` | Run turnaround length. | — | 14 | 18 |
| `traction` | Ground deceleration; low traction slides further. | 0.076 – 0.138 (Sonic) | 0.102 | 0.11 |
| `jumpsquat_frames` | Frames before leaving the ground. | 3 for everyone | 3 | 3 |
| `full_hop_height` | Full hop peak (units). | 16.5 (Steve) – 50.51 (Falco) | 36.33 | 33 |
| `short_hop_height` | Short hop peak. | 10 (Steve) – 22.11 (Greninja) | 17.54 | 15.7 |
| `air_jump_height` | Each mid-air jump. | 19.79 (Jigglypuff) – 57.35 (Mewtwo) | 36.33 | 33 |
| `jump_count` | Total jumps including the ground jump. | 2 (most) – 6 (Jigglypuff) | 2 | 2 |
| `jump_momentum`, `jump_initial_x`, `jump_max_x` | Horizontal speed when leaving the ground: ground speed kept, stick boost, cap. | — | 0.85 / 0.35 / 1.5 | 0.85 / 0.3 / 1.4 |
| `air_jump_x` | Air jump horizontal speed (× air speed × stick). | — | 1.0 | 1.0 |
| `air_speed` | Max horizontal air speed. | 0.735 (Dedede) – 1.344 (Yoshi) | 1.208 | 1.1 |
| `air_acceleration_base` / `_additional` | Air accel = base + additional × tilt. | max 0.03 (Snake) – 0.13 (Jigglypuff) | 0.01 / 0.07 | 0.01 / 0.045 |
| `air_friction` | Air deceleration without input. | 0.00375 – 0.05 (Mega Man) | 0.015 | 0.0075 |
| `gravity` | Downward acceleration; high gravity means short, snappy jumps. | 0.053 (Jigglypuff) – 0.23 (Fox) | 0.087 | 0.11 |
| `fall_speed` | Terminal velocity; fast fallers escape juggles but die earlier to vertical hits and combos. | 0.98 (Jigglypuff) – 2.1 (Fox) | 1.5 | 1.75 |
| `fast_fall_multiplier` | Fast fall speed = fall speed × this. | 1.6 for everyone | 1.6 | 1.6 |
| `hard_landing_frames` / `soft_landing_frames` | Landing lag after a normal / light landing. | 4–6 / 2 | 4 / 2 | 6 / 2 |
| `shield_radius` | Bubble size at full HP (units). Bigger characters need a bigger shield. | — | 10 | 13.5 |
| `spot_dodge_*`, `*_roll_*`, `air_dodge_*` | Intangible window (first, last frame) and total frames. | per character | Mario's | Bowser-like |
| `roll_distance`, `air_dodge_speed` | Roll distance (units) and directional air dodge speed. | — | 28 / 2.6 | 32 / 2.3 |
| `ledge_*` | Ledge getup / roll / jump: intangible-until frame and total frames. | mostly universal | 33/34, 25/45, 12/14 | 33/34, 24/45, 12/14 |

Ultimate stats with no ultimateframedata figure (walk/run acceleration, jump momentum, run turnaround) are reasonable starting values. Tune them in playtests.

## How the two characters differ

**Cat (all-rounder, Mario-like):** every stat is Mario's. Its moves start quickly (jab on frame 2, tilts on 5, nair on 3) and do modest damage, with tilts that combo into each other.
It has a spiking forward air and a mostly vertical up special (*Skyward Pounce*).

**Bear (heavyweight, DK/Bowser-like):** heavy (130), big (20 × 6.2 hurtbox), falls fast (1.75, gravity 0.11) and has low air acceleration and air friction, so it's slow to change direction in the air.
Its moves come out later (jab frame 5, forward smash frame 19) but hit much harder (22% forward smash) with bigger hitboxes. Its down air is a meteor smash.
Its recovery (*Spinning Heave*) goes far sideways but barely up. That's the classic heavyweight trade: lives long, hits hard, gets comboed and edge-guarded.

## Moves

Each `MoveData` follows ultimateframedata conventions:

- `total_frames`: the move's length; the fighter acts again on `total_frames + 1`.
- `hitboxes`: `HitboxData` spheres with `start_frame`/`end_frame`, `offset` (units from the feet; +x is forward), `radius`, `damage`, `angle` (361 = Sakurai), `base_knockback`, `knockback_growth`, optional `set_knockback`, `reverse` (send backward), `hitlag_multiplier`, `sdi_multiplier`, `shield_damage` and `shieldstun_multiplier`.
- **Aerials**: `landing_lag`, `autocancel_before` and `autocancel_after`.
- **Smash attacks**: `charge_frame`.
- **Movement**: `motion_start`/`motion_end`, `motion_velocity`, `motion_steer` and `gravity_during_motion`.
- **Recovery**: `ends_in_helpless`, `ledge_grab_frame` and `reverse_frame` (B-reverse).

## Adding a character

1. Duplicate a roster folder, e.g. `fighters/roster/bear/` → `fighters/roster/fox/`.
2. Build the model scene. Its root needs the `FighterModel` script and a `%Pivot` node, with the origin at the feet and the nose toward +X. Match its size to `height` and `radius`.
3. Edit the stats and moves in the inspector, using ultimateframedata for reference values.
4. Add the `.tres` to `Match.roster` in `match/match.tscn`. It then shows up in the pause menu.
5. Run the tests. They measure jump heights and speeds for the characters they load (add new ones in `tests/run_tests.gd`).
