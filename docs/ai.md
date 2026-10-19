# CPU players (AI)

How the computer players work, what's ported from *Super Smash Bros.* and what's our own design, and the numbers behind each level.
The design and its reasoning are in [plans/cpu-ai.md](../plans/cpu-ai.md); this page records what was built and the values it ended with.

## What's ported from Smash

| Smash feature | Here |
|---|---|
| Levels 1-9, default 3 | `CpuController.level`, `PlayerSlot.cpu_level` (default 3). |
| Brawl-on internal value per level: 0, 15, 21, 31, 42, 48, 60, 75, 100 | `CpuDifficulty.LEVEL_VALUES`. Skill = value / 100, and every parameter is a `Curve` sampled at that skill, so the uneven steps carry over and any skill in between works (`set_skill()`). |
| The level mainly changes how often a decision is followed through and how fast it reacts | `follow_through` and `reaction_frames` are the two main levers. |
| The level unlocks options, not just timing (Smash 4 Luigi's recovery) | `move_pool`, `recovery_options` and `edgeguard_appetite` are tiers that unlock moves, recovery tools and edgeguard behaviour. |
| Training CPU modes: Stand, Walk, Jump, Run/Evade, CPU, plus the shield dummy | `CpuController.Mode`: FIGHT, STAND, SHIELD, JUMP, WALK, EVADE. Every mode still DIs, techs, recovers, gets up and leaves ledges, as Smash's Stand CPU does. STAND/SHIELD/JUMP keep the old training dummy's behaviour and its DI setting (none / survival / combo). |
| Shared default behaviour, per-move reach data, per-character overrides (Brawl's AIMain / ATKD / AIPD) | Situations (`ai/situations/`) are the shared routines, `MoveProfile`/`MoveBook` is the reach data, built automatically from each `MoveData`, and `CpuProfile` is the optional per-character override. |

## What's our own (the fairness rules)

Each rule fixes a documented Smash CPU flaw (plans/cpu-ai.md §1.5).

| Rule | How it's enforced |
|---|---|
| **R0 Same input path** | `CpuController.poll()` returns an `InputFrame` that goes through the same `InputTracker` as a pad. `InputPlan` macros respect its thresholds (walk under the flick threshold, tilts never flick, a single shield press to tech). A test wraps the CPU and fails if a poll changes anything about the fighter. |
| **R1 Delayed perception** | `AiWorld.capture()` snapshots every fighter after each frame resolves. A CPU reads the other fighters only through `AiWorld.view()`, `reaction_frames` (+ up to `reaction_jitter`) frames old, then extrapolates by `extrapolation × delay`. It knows its own fighter immediately. `FighterSnapshot` holds no input. |
| **R2 No fixed response** | Every choice is a softmax over tactic utilities whose temperature drops with skill, minus a decaying penalty for recent use. Spacing and timings are jittered. |
| **R3 Never give up a recoverable stock** | `RecoveryPlanner` simulates recoveries frame by frame. Every aerial the CPU considers is checked first: where does it leave the fighter (drifting at the target until its hitboxes end, then home), and can it still get back from there with what's left (`CpuController.recoverable_after()`)? Dives, fight-backs and ledge drops use the same check. |
| **R4 Defence costs something** | Shield HP, dodge intangibility frames and the air dodge are scored; hitstun cancels are used only against a perceived follow-up. |
| **R5 Frame data, not habits** | Punish windows come from `frames_until_actionable()`; combos check true-combo timing against the predicted launch at the current percent; KOs are estimated by following the launch to the blast zone. |
| **R6 Even targeting** | Targets are scored from snapshots only (distance, threat, percent, alive). Nothing asks who controls a fighter. Offstage dives are claimed in `AiWorld`, so only one CPU dives at a time. |
| **R7 Stage-agnostic** | `StageModel` reads any `Stage`: solid boxes from its collision shapes, soft platforms, ledges, blast zone. No per-stage code. |

**Level 9 vs Smash's level 9.** Smash's level 9 defends with one-frame reactions. Ours reacts in 10-12 frames (human visual reaction is about 15-25), extrapolates and anticipates, so it plays strongly but can be beaten with fast moves and mix-ups.
The hidden **level 10** ("frame-perfect", debug builds only) is the Smash-faithful version: 1-frame reactions, no errors.

## Architecture

`Match._physics_process` ticks fighters; each `Fighter.tick()` polls its controller. After hits resolve, `AiWorld.capture()` records the frame.
`CpuController.poll()` then:

1. **Perceives**: its own state now, the target's delayed view extrapolated to now, and whether a perceived opponent hitbox will reach it (`threat_in`). The target's predicted path is computed on first use each frame.
2. **Picks a situation**, the first whose `applies()` holds, in priority order:
   HitReaction > Recover > Ledge > GroundedDown > Respawn > Defend > Punish > Advantage > Edgeguard > Neutral (FIGHT mode). The training modes end with TrainingMode instead of the fighting situations.
3. **Updates the situation**, which scores tactics and fills the `InputPlan`.
4. **Plays the plan**: one `InputFrame` per frame.

Entering a situation about the fighter's own state (Recover, Ledge, GroundedDown, Respawn) drops plans made by other situations, except those marked `carries_over` (dives, ledge drop-aerials, ledge steals, fight-backs). Getting hit clears the plan.

| File | Role |
|---|---|
| `ai/cpu_controller.gd` | Level, mode, RNG, perception, shared helpers (hit queries, the R3 check, softmax pick, follow-through), debug lines. |
| `ai/ai_world.gd`, `ai/fighter_snapshot.gd` | Snapshot ring buffer (64 frames) and what a snapshot holds. |
| `ai/move_profile.gd`, `ai/move_book.gd` | Per-move timing, reach, motion, safety, knockback and KO estimates; the hit query (`moves_hitting`) for each way of starting a move (standing, turning, dashing, short hop, full hop, in the air, out of shield). |
| `ai/stage_model.gd` | Stage geometry and queries, including `home_direction()`, the recovery drift rule shared by the planner and the inputs. |
| `ai/predict.gd` | Trajectories with the fighter's own gravity, fall speed, drift and launch decay. |
| `ai/recovery_planner.gd` | Anytime search over recovery plans, frame by frame, with the game's ledge-grab rules. |
| `ai/input_plan.gd` | Input macros. |
| `ai/di.gd` | Dummy DI (moved from the old `DummyController`), simulated best DI, SDI direction. |
| `ai/cpu_difficulty.gd` + `.tres` | The level curves. `ai/tools/build_cpu_difficulty.gd` regenerates the `.tres` from the table. |
| `ai/cpu_personality.gd`, `ai/cpu_profile.gd`, `ai/profiles/*.tres` | Style weights and per-character flavour. `ai/tools/build_cpu_profiles.gd` regenerates the profiles. |
| `ai/habit_model.gd` | Per-match opponent habits (adaptation). |
| `ai/situations/*.gd` | The routines. |
| `ai/ai_debug_draw.gd` | F3 view: perceived-opponent ghost, its predicted path, recovery path, chosen attack's hitboxes. |

Gameplay additions for the AI: `FighterState.frames_until_actionable()` and `intangible_frames_left()` in every state with a fixed length (also shown as frame advantage in the training overlay), `Fighter.get_pending_knockback()` and `get_ledge_cooldown()` (the CPU's own state), and `FighterData.cpu_profile`.

## Situations

- **HitReaction.** In hitlag: DI on the last hitlag frame, and SDI pulses every 4 frames from `di_quality` 0.85. DI by quality: none → random → survival DI some of the time → situational (combo DI away from the attacker at low percent, survival when the launch threatens a KO) → simulated best DI (`AiDi.best`). In hitstun: drift home when offstage, tech (one press about 5 frames before the predicted landing ± timing error, in place / toward / away by `tech_mixup`, never rolling off), air dodge cancel only under a perceived threat.
- **Recover.** An anytime search (160 simulated frames on the first poll, 120 per poll after) over plans: when to double jump, when to up special (steering to the ledge, or high over the stage), whether to air dodge, and an optional delayed drift. Low tiers take the first success of a fixed pattern; high tiers keep a few, score them (sooner, height preference, keep the air dodge, avoid repeats, stay away from the edgeguarder) and pick with randomness. Plans are re-checked every 10 frames while free; mid up special or helpless the plan's own steering is followed. If nothing works, it jumps and up specials straight away. Level 9 fights back with an aerial near ledge height when R3 allows.
- **Ledge.** Waits (low levels a long predictable time, high levels inside the 40-frame intangibility, sometimes late), then climbs, rolls, jumps, or (high levels) drops and jumps back with an aerial, by where the opponent is. With high edgeguard appetite it holds the ledge while an opponent needs it.
- **GroundedDown.** Get up in place or roll toward or away (never off the stage), mixed by level.
- **Respawn.** Waits 20-240 frames (shorter at high levels), drops away from the opponent; high levels wait while the opponent attacks below.
- **Defend.** Rolls `defend_chance` once per perceived threat, then picks among options that actually cover the threat's frames: shield (cost: shield HP), spot dodge, roll away (room permitting), jump away, beating it out with a faster move; in the air, air dodge, drift away, double jump, aerial. `defend_quality` decides between the best-scored and a random option. Anticipation: pre-emptive shield when an opponent runs in inside its reach.
- **Punish.** Rolls `punish_chance` once per window. Any option that lands after the target's intangibility and before it can act, KO moves and charged smashes (by `smash_charge`) preferred; dashes in for long windows.
- **Advantage.** After its own hit, true-combo follow-ups up to `combo_depth`; otherwise waits under the landing spot.
- **Edgeguard.** Hits returning opponents from the stage, times smashes for the end of ledge getup intangibility, waits at the spot the opponent's likely getup ends (habit model), steals the ledge from a standstill (appetite ≥ 0.7), and dives with an aerial (appetite ≥ 0.35) only when R3 passes and no other CPU is diving.
- **Neutral.** Every `decision_interval` frames: attacks the hit query finds (low levels favour dash attacks, like Melee CPUs), otherwise works toward a preferred range (outside the opponent's quick reach, inside its own, with spacing error), with walk/run/back off/shield bait/dash dance/wait and platform jumps and drops. Runs and walks are limited by the room to the edge.

## Levels

Tuned with the ladder (below). Values at each level; the curves interpolate between them.
Changed from the plan's starting table: level 3 (reaction 34→32, follow-through 0.37→0.42, defend 0.16→0.20, punish 0.16→0.22), level 4 (reaction 31→30, punish 0.25→0.28) and level 6 (reaction 26→25, follow-through 0.64→0.68, defend 0.42→0.45, punish 0.45→0.50), because levels 2→3 and 5→6 (Smash values 15→21 and 42→48) were too close to tell apart.

| Lv | Value | Reaction (+jitter) | Decide every | Follow-through | Defend | Punish | Tech | DI quality | Move tier | Recovery tier | Edgeguard |
|----|-----|---------|----|------|------|------|------|------|---|---|------|
| 1 | 0   | 40 (+8) | 30 | 0.15 | 0.05 | 0.05 | 0.00 | 0.00 | 0 | 0 | 0.00 |
| 2 | 15  | 36 (+7) | 26 | 0.30 | 0.12 | 0.12 | 0.05 | 0.00 | 1 | 1 | 0.00 |
| 3 | 21  | 32 (+7) | 24 | 0.42 | 0.20 | 0.22 | 0.10 | 0.20 | 2 | 2 | 0.00 |
| 4 | 31  | 30 (+6) | 20 | 0.48 | 0.25 | 0.28 | 0.20 | 0.35 | 3 | 3 | 0.10 |
| 5 | 42  | 27 (+5) | 16 | 0.58 | 0.35 | 0.38 | 0.35 | 0.50 | 4 | 4 | 0.25 |
| 6 | 48  | 25 (+5) | 14 | 0.68 | 0.45 | 0.50 | 0.45 | 0.70 | 5 | 5 | 0.35 |
| 7 | 60  | 22 (+4) | 10 | 0.75 | 0.55 | 0.60 | 0.60 | 0.80 | 6 | 6 | 0.50 |
| 8 | 75  | 18 (+3) | 7  | 0.87 | 0.70 | 0.78 | 0.75 | 0.90 | 7 | 7 | 0.70 |
| 9 | 100 | 10 (+2) | 4  | 0.98 | 0.85 | 0.95 | 0.90 | 1.00 | 8 | 8 | 0.90 |

Also per level (see `CpuDifficulty.STARTING_VALUES`): extrapolation 0 → 1, spacing error 8 → 0.5 units, timing error 6 → 0.5 frames, combo depth 0/0/0/1/1/1/2/2/4, smash charge from level 5, tech mix-up, ledge mix-up, anticipation from level 5 and adaptation from level 6.

**Move tiers.** 0: jab, tilts, dash attack. 1: + smash attacks. 2: + aerials when either fighter is airborne, full-hop aerials. 3: + short-hop aerials. 4: + charged smash punishes. 5: + out of shield (jump-cancelled up smash, up special, aerials). 6-8: deeper combos, dash dancing; everything at 8.
**Recovery tiers.** 0-1: one fixed pattern. 2: + other jump timings. 3: + steering high over the stage. 4: + air dodges. 5: + delayed drift, up to six candidate plans. 6+: + jumping straight away, avoiding the edgeguarder. 8: fights back.
**Edgeguard appetite.** ≥ 0.1 covers the ledge from the stage, ≥ 0.25 times hits on ledge getups, ≥ 0.35 dives offstage (more often higher up), ≥ 0.7 steals and holds the ledge.

## Personalities and profiles

`CpuPersonality` weights (-1 to 1) bias tactic scores: aggression (approach vs wait), air preference, risk (smashes), defence style (shield vs dodge), edgeguard appetite and patience (ledge, getup and respawn timing).
Each CPU copies its character's personality with ±0.15 random variation per match, so two CPU Cats don't play alike.

| Profile | Characters | Style |
|---|---|---|
| `all_rounder` | Cat, Husky | Likes aerials, a little aggressive. |
| `bear` | Bear | Grounded, smash-happy, shields; kill moves forward and up smash; never down airs offstage. |
| `speedster` | Fox, Shiba Inu | Rushes in, dodges rather than shields, impatient, recovers low. |
| `rushdown` | Wolf, White Horse | Pressure and risky kills. |
| `floaty` | Deer, Alpaca | Fights in the air, waits, recovers high. |
| `heavy` | Donkey, Stag, Horse, Cow, Bull | Patient, shields, big punishes; never down airs offstage. |

A CPU plays fine without a profile: everything else comes from the moveset, stats and stage.

## Determinism

Each CPU has its own `RandomNumberGenerator`, seeded from the match seed and its slot (`CpuController.seed_for`). The match seed is new at every start and reset, and shown in the training overlay.
Nothing reads the clock or global randomness; a test checks that two CPU-vs-CPU runs with the same seed give identical inputs for 1,200 frames.
Rollback support (`save_state`/`load_state` for the RNG, plan and situation state) is not implemented yet; the plan lists it as future work.

## Tests and the ladder

`tests/run_tests.gd` covers (§2.14): every input macro and its gotchas, the perception delay, move profiles against the moveset data, `Predict` against a real launch, the hit query against `HitResolver` (≥ 95% agreement), determinism and input validity, reaction timing (level 3 slower than 9, never sooner than the reaction time), punishes (level 9 ≥ 90%, level 1 ≤ 20%), no self-destructs in 60 s per level against a stand dummy, the recovery grid (level 9 ≥ 98%, level 1 ≥ 80% of starts the planner says are recoverable), recovery plans playing out in the game as simulated, and level 9 DI surviving a hit that kills a dummy without DI.

A **self-destruct** is a KO after the fighter stood on the stage (or held a ledge) since the last hit it took: it went offstage on its own. Failing to come back from a launch is a KO by the opponent.

`tests/ai_ladder.gd` plays first-to-3-KO matches (Cat and Bear, alternating sides) and prints the win-rate matrix and telemetry per level; `--bench` times `poll()`. Several processes can split the pairs (see the script's header).
Last run, 96 matches per adjacent pair (seeds 41, 42, 51, 52):

| Pair | 2>1 | 3>2 | 4>3 | 5>4 | 6>5 | 7>6 | 8>7 | 9>8 |
|---|---|---|---|---|---|---|---|---|
| Higher level wins | 100% | 74% | 66% | 77% | 58% | 66% | 67% | 76% |

6>5 sits just under the 60% target, within the ±10% noise of 96 matches; it's the closest pair in Smash's scale (42 vs 48). No self-destructs in those 768 matches (six KOs happened while failing to come back from launches). Average perceived reaction (move start to defensive input) went from 49 frames at level 1 to 15 at level 9.

## Performance

Desktop (Apple silicon, macOS), level 9 vs level 9 for 10,000 frames: `poll()` averages about 73 µs (median 39 µs, 99th percentile about 1 ms, worst about 5 ms). The recovery search is spread over polls with budgets, and the R3 checks share 600 simulated frames per poll.
The Web build hasn't been benchmarked yet; GDScript on the web is expected to be a few times slower.

## Known limitations

- `StageModel` treats solid ground as boxes; corners count as floor only near the edge (0.3 × the body radius), which is conservative.
- Specials other than up special, grabs, throws, ledge attacks and getup attacks don't exist yet. When they're added to a moveset, the hit query picks them up, but their macros and any special handling still need adding.
- Habit adaptation drives ledge-trap positioning only.
- No rollback state save/load.
