# CPU Players (AI) — Plan

Status: **proposed** · Written: 2026-10-16 at commit `51642fd` · Scope: new `ai/` folder, `match/`, `input/`, `fighters/states/`, `ui/pause/`, `tests/`

This plan adds a second kind of player, the **CPU**, next to the existing human player. CPUs have difficulty levels 1–9, as in Smash.
Part 1 summarizes how the Smash games build their CPUs and which of their flaws to avoid. Part 2 is the design. Part 3 is a phased implementation order with a "Done when" check for each phase.

## How to use this document

- Phases are ordered so that each one gives a CPU that can be played against and tested. Do them in order.
- Follow the rules in `CLAUDE.md`. The ones that matter most here:
  - CPUs drive their fighter **only** through `InputFrame`s, like a human. AI code never changes fighter state directly.
  - All distances and speeds in the AI are Smash units and units/frame, and all times are frames.
  - Fighters are still ticked only by `Match` (or the test world). The AI runs inside `FighterController.poll()` and in one capture step in the match loop.
  - Run the tests after every phase.
- Numbers in the difficulty tables are **starting points** for tuning, not ported values. Smash's real per-level parameters aren't public, apart from the 0–100 scale in §1.2.
- When a phase is done, update its status in the [Phase overview](#phase-overview) table.

---

## Part 1 — How Super Smash Bros. does it

Sources are listed at the end. Most of this comes from SmashWiki's *Artificial intelligence*, *Flaws in artificial intelligence*, *List of CPU modes* and *amiibo* pages.

### 1.1 What the CPU is

- Every game uses hand-written **if-then scripts** ("routines"). There is no learning, apart from amiibo (§1.6).
  Brawl's AI was disassembled. It showed no learning code, and replays store only human inputs, so CPUs must act the same way on every playback. **The AI is deterministic given the game state.**
- Brawl's AI files, as the modding community documents them, come in three kinds:
  - `AIMain`: the character's behaviour, split into numbered routines.
  - `ATKD`: per-move attack data that the routines use to know which move reaches where.
  - `AIPD`: further per-character AI data.
  A common AI in `Fighter.pac` gives the default behaviour, and each character's files override it.
  **Takeaway: shared default behaviour, plus per-move reach data, plus per-character overrides.**
- CPUs **don't read button inputs**. The Brawl "input reading" rumour was disproved: CPUs read the *game state* and react to it, at high levels within one frame.

### 1.2 Difficulty levels

- Levels go from 1 to 9. The Versus default is 3 (1 in Melee), and Ultimate lets the rules change the default.
- From Brawl on, each level maps to an internal value from 0 to 100, which lets events place CPUs between levels:

  | Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
  |-------|---|---|---|---|---|---|---|---|---|
  | Value | 0 | 15 | 21 | 31 | 42 | 48 | 60 | 75 | 100 |

  The steps aren't even: 5→6 is small, 8→9 is huge.
- **The level mainly controls two things: how likely the CPU is to follow through on a decision, and how fast it reacts.**
  Level 1 and level 9 both *decide* to attack, but level 1 waits a long time and usually doesn't do it, while level 9 almost always acts at once.
- **Defence:** low levels rarely shield or dodge, and roll mainly to reposition. High levels nearly always defend. From Brawl on, level 9 defends with one-frame reactions, which gives it inhumanly frequent perfect shields and dodges.
- **Offence:** low levels stand next to the opponent and use jabs and tilts. High levels use aerials, smash attacks and grabs more. In every game, level 9 lands attacks perfectly whenever it's at the right range.
- **Recovery:** low levels recover in a simple, predictable way with only the up special. High levels (Brawl on) combine and alternate recovery options. In Smash 4, Luigi uses only Super Jump Punch at levels 1–5, and adds Green Missile and Luigi Cyclone at 6–9: **the level unlocks options, not just timing.**
- **Mashing** (sleep, shield break) speeds up with level. Level 9 mashes frame-perfectly.
- Ultimate CPUs play well even at level 2. At high levels they use advanced techniques: dash dancing, fast short-hop aerials on shields, B-reversals, reverse aerial rushes.

### 1.3 CPU modes

Training mode exposes the CPU's movement layer without its fighting layer. In Smash these are all CPU behaviours, not separate controllers:

| Mode | Behaviour |
|------|-----------|
| Stand / Stop | Doesn't move or defend. **Still recovers, gets up from the floor and gets off ledges**, and at high levels still air dodges out of tumble. |
| Walk | Walks back and forth and turns at obstacles. |
| Jump | Jumps in place (Smash 4 also fast falls). Always jumps from the ledge. |
| Evade / Run | Runs away from the player. |
| Attack / CPU | Normal play at the chosen level. |
| Neutral special, side smash (Ultimate) | Repeats one move toward the player. |

Melee also has level 0: the CPU moves but never attacks.

### 1.4 How it changed from game to game

- **64 / Melee:** weak at every level. They rarely shield. Recovery is only the up special, done the same way every time, with no attempt to fight edgeguarders. They walk into charged attacks.
  Melee CPUs never dash except for a dash grab or dash attack, never charge smashes, and spam dash grab and jab. Precise powershields only against projectiles.
- **Brawl:** largely rewritten. CPUs shield and dodge properly (one-frame perfect shields at level 9), charge smashes, use full dashes and aerials against grounded foes, use side specials and tethers to recover, and shield grab when it's optimal.
  Still easy to edgeguard: no DI, and they don't fight back offstage. In free-for-alls every CPU targets the human.
- **Smash 4:** better again. CPUs air dodge past edgeguarders, use out-of-shield up smash, and follow throws with aerials.
  But they keep doing a throw combo at percents where it no longer works, ignore character differences (rolling with slow rolls), and air dodge so often that they miss the ledge.
- **Ultimate:** the best so far. Aggressive offstage edgeguarding, aerials thrown while recovering, and **anticipation**: shielding or spot dodging as a player approaches, and waiting out counters to punish them.

### 1.5 Flaws to avoid

These are the documented flaws that make Smash CPUs feel unfair or easy to cheese. Each becomes a design rule in Part 2 (the "Rule" column).

| Smash flaw | Why it's bad | Rule |
|------------|-------------|------|
| One-frame defensive reactions at level 9; constant perfect shields; frame-perfect air dodges against any aerial (Smash 4 / Ultimate 7–9) | Feels like input reading. Makes aerial combos impossible to practise | R1 human-like reaction delay |
| Same response to the same stimulus every time (always shield at about 2 character lengths, always shield grab a jab, always get up after a fixed time, tech only by accident) | Easy to exploit and teaches bad habits | R2 weighted random choice with anti-repetition |
| Recovery uses one option in one pattern; some moves never used; spends a needed recovery move on an attack | Easy gimps; CPUs self-destruct | R3 a reachability-checked recovery planner |
| Doesn't fight edgeguarders (early games); air dodges every attack and misses the ledge (Smash 4) | Both extremes lose stocks | R3, R4 a cost for every defensive resource |
| Throw combos attempted at percents where they don't work; ignores the character's own frame data (slow rolls, slow up smash out of shield) | Visibly dumb | R5 decisions from real frame data and formulas |
| Every CPU edgeguards at once ("flocking"); CPUs target humans over closer CPUs and react slower to CPUs | Unfair free-for-alls and teams | R6 target choice without human bias |
| Walking into hazards and off stages; can't handle unfamiliar stages | Self-destructs | R7 stage queries, never stage-specific scripts |
| Level 9 lands every move at perfect range | Inhuman | R1 plus spacing noise by level |

### 1.6 amiibo: personality and learning

- amiibo (Smash 4 / Ultimate) are CPUs with a saved profile that **changes its tactics in response to opponents**. For example, against a shield-heavy opponent it shields better and grabs more. Ultimate lets you turn learning off.
- Useful ideas for us:
  - A **personality**, separate from skill: aggression, edgeguarding appetite, and so on.
  - Optional **adaptation within a match**: notice an opponent's habits and cover them.
  Both appear in Part 2 as optional layers.

---

## Part 2 — Design

### 2.1 Goals

1. **Two kinds of player per slot: Human and CPU.** Any slot can be either, so CPU vs CPU works (for spectating, the balance harness and tests).
2. **Levels 1–9**, plus Smash's internal 0–100 value for in-between levels (events, tuning). Default level 3, as in Smash.
3. **Fair by construction.** The CPU plays through the same input path as a human, sees only what a human can see, and reacts with human-like delay. There is no stat buffing or rubber-banding: difficulty comes only from decisions and timing.
4. **Data-driven.** A new animal gets a competent CPU with no AI code, because the AI reads `MoveData`, `FighterStats` and the stage geometry. Per-character tuning is an optional resource, like `FighterStats`.
5. **Deterministic.** Same seed and same human inputs give the same match. This is what Smash's replays need, and what rollback netcode would need.
6. **Cheap enough for web and phones:** well under 0.1 ms per CPU per frame on desktop. The web build is single-threaded GDScript with no JIT.

**Non-goals for now:** machine learning, items, teams, stage hazards, more than 2 fighters in a match (the design leaves room for all of them).

### 2.2 Fairness rules

| Rule | Meaning in this codebase |
|------|--------------------------|
| **R0 Same input path** | `CpuController.poll()` returns an `InputFrame`. It then goes through `InputTracker` (9-frame buffer, flick detection, SDI interval, tech lockout) exactly like a pad, so the CPU can't do anything a human can't. CPUs set `tap_jump = false`. |
| **R1 Delayed perception, never input reading** | A CPU sees other fighters through snapshots that are *N frames old* (N = its reaction time). It never reads another fighter's `InputFrame`, `InputTracker` or controller. It knows its own fighter immediately, the way a human knows what they pressed. |
| **R2 No single fixed response** | Every decision point picks from weighted options with seeded randomness. A "recently used" penalty decays over time, and distance thresholds are jittered. |
| **R3 Never give up a recoverable stock** | Before committing offstage (edgeguards, recovering, air dodges, aerials offstage), the CPU checks that it can still get back with the resources it has left. |
| **R4 Defensive actions cost something** | Shield HP, air dodge (one per airtime), rolls (endlag, intangibility frames) and the tech lockout are scored as costs, not used on reflex. |
| **R5 Frame data and formulas, not hard-coded habits** | Punish windows, true combos and kill confirms come from `MoveData` frames and `SmashFormulas` knockback and hitstun at the target's current percent. |
| **R6 Even targeting** | Target choice uses only game state (distance, threat, percent, offstage). It never asks whether a target is human. Reaction delay is the same against every opponent. |
| **R7 Stage-agnostic** | All stage knowledge comes from `Stage` (ledges, soft platforms, blast zone, solid ground found by raycasts). No per-stage scripts. |

### 2.3 Player kinds and slots

Today `Match` has `selections`, `player_two_human` and a shared `dummy`. Replace them with one config object per slot:

```gdscript
class_name PlayerSlot
extends RefCounted
## Who controls one fighter in a match, and with which character.

enum Kind { HUMAN, CPU }

var kind := Kind.HUMAN
## Index into Match.roster.
var character := 0
## Input Map slot for humans (1 or 2; see PlayerActions).
var input_slot := 1
## CPU difficulty 1-9 (Smash default: 3).
var cpu_level := 3
## CPU behaviour mode (Smash's CPU modes); FIGHT is normal play.
var cpu_mode := CpuController.Mode.FIGHT
```

- `Match.apply_controllers()` builds a `PlayerController(input_slot)` for humans and a `CpuController` for CPUs.
- The **training dummy becomes a CPU mode**, as in Smash (§1.3): `Mode { FIGHT, STAND, SHIELD, JUMP, WALK, EVADE }`. The STAND, SHIELD and JUMP modes keep `DummyController`'s exact behaviour and its DI setting, and gain level-based recovery and teching like Smash's Stand mode.
  Phase 0 keeps `DummyController` as the implementation behind those modes, so the existing tests keep passing. Phase 5 merges it.
- Humans need an input slot and there are only 2 (`InputActions.MAX_LOCAL_PLAYERS`). CPUs need none, which is what lets matches grow past 2 fighters later.
- **Mobile default:** a phone has one human, so P2 should start as **CPU level 3** instead of the stand dummy. Training mode keeps the dummy (see Open questions).

### 2.4 Architecture

```
Match._physics_process (one Smash frame)
 ├─ for each fighter: fighter.tick()
 │     └─ controller.poll(fighter)
 │          ├─ PlayerController ── reads the Input Map
 │          └─ CpuController ───── 1. Perception: read delayed snapshots and extrapolate to now
 │                                  2. Situation: classify (neutral, defend, recover, ...)
 │                                  3. Decision: score this situation's tactics (utility + level + personality)
 │                                  4. Execution: InputPlan emits this frame's InputFrame
 ├─ HitResolver.resolve()
 ├─ separate fighters, blast zones
 ├─ ai_world.capture(fighters)   ◄── new: record this frame's snapshot for every CPU to read later
 └─ sync_visuals()
```

The snapshot is captured **after** the frame resolves and read on later frames. Because of that, P1 and P2 see the world the same way no matter which order they tick in.
Without this, a CPU in slot 2 would see slot 1's move on the same frame it started, a free 1-frame advantage.

#### New files (`ai/`, one feature folder like the others)

| File | Class | Role |
|------|-------|------|
| `ai/cpu_controller.gd` | `CpuController extends FighterController` | Holds level, mode, personality and RNG. Runs perception → situation → decision → execution each `poll()`. |
| `ai/ai_world.gd` | `AiWorld` | Owned by `Match`. Keeps a ring buffer of `FighterSnapshot`s (about 64 frames), the stage model and the move books. Gives the CPUs their views. |
| `ai/fighter_snapshot.gd` | `FighterSnapshot` | What a human can see of a fighter: position, velocity, facing, grounded, `Activity` kind, state frame, frames until actionable, percent, shield HP, jumps left, air dodge used, intangible, current move slot, active hitboxes, ledge, tumble/helpless flags. |
| `ai/move_profile.gd` | `MoveProfile` | Our `ATKD`: reach and timing of one `MoveData`, derived automatically (§2.6). |
| `ai/move_book.gd` | `MoveBook` | The `MoveProfile`s of one `Moveset`, cached per resource, with queries such as "moves that hit a target at (dx, dy) within k frames". |
| `ai/stage_model.gd` | `StageModel` | Stage queries: main-ground extents, ledges, soft platforms, "over stage?", distance to ledge, blast-zone margins (§2.7). |
| `ai/predict.gd` | `Predict` (static) | Ballistic trajectories with the fighter's own gravity, fall speed and drift, plus knockback decay and hitstun (`SmashFormulas`). |
| `ai/input_plan.gd` | `InputPlan` | A short queue of timed input steps ("macros"), each one turned into an `InputFrame` (§2.9). |
| `ai/situations/*.gd` | `CpuSituation` subclasses | Our `AIMain` routines: `RespawnSituation`, `NeutralSituation`, `DefendSituation`, `PunishSituation`, `AdvantageSituation`, `EdgeguardSituation`, `RecoverSituation`, `LedgeSituation`, `HitReactionSituation`, `GroundedDownSituation`. |
| `ai/cpu_difficulty.gd` + `ai/cpu_difficulty.tres` | `CpuDifficulty` | Maps skill 0–1 to every tuning parameter with Godot `Curve` resources, editable in the inspector (§2.5). |
| `ai/cpu_personality.gd` | `CpuPersonality` | Style weights, separate from skill (§2.11). |
| `ai/cpu_profile.gd` | `CpuProfile` | Optional per-character overrides: move weights, preferred kill moves, recovery hints. Referenced from `FighterData.cpu_profile`. |
| `ai/di.gd` | `AiDi` (static) | DI, SDI and LSI stick choice. Moved out of `DummyController._di_stick` so the dummy and the CPU share it. |

#### Small gameplay-side additions (no AI logic in gameplay code)

- `FighterState.frames_until_actionable() -> int`, default 0. Overridden in states with a fixed length: `AttackState` (including landing lag), `LandingState`, `DodgeState`, `HitstunState`, `ShieldState` (stun, drop), `KnockdownState`, `LedgeActionState`, `JumpSquatState`, `ShieldBreakState`.
  The perception layer needs it for punish windows. It's also useful in the training overlay as a frame-advantage readout.
- `FighterData.cpu_profile: CpuProfile` (optional export).
- `Match` owns an `AiWorld` and calls `capture()` at the end of each frame. The test world in `tests/run_tests.gd` does the same.

### 2.5 Difficulty model

**Skill value.** `level` 1–9 maps to Smash's 0–100 value (§1.2), and `skill = value / 100`. Every parameter is a `Curve` sampled at `skill`, so the uneven Smash steps carry over automatically, and an event or test can ask for any skill such as 0.55.

**What the level changes.** These are Smash's levers from §1.2, plus human-likeness levers from R1 and R2:

| Parameter | What it does |
|-----------|-------------|
| `reaction_frames` | Perception delay: how many frames old the CPU's view of other fighters is. |
| `reaction_jitter` | Random extra frames per reaction event, so its timing isn't readable. |
| `extrapolation` | 0–1: how well it predicts the present from its delayed view (0 aims at where you *were*). |
| `decision_interval` | Frames between re-plans in neutral. Lower re-thinks faster. |
| `follow_through` | Smash's main lever: the chance of acting on a chosen offensive option when its moment comes. Otherwise it hesitates. |
| `defend_chance` | Chance of responding to a perceived threat at all. |
| `defend_quality` | How well the defensive option is chosen (shield vs dodge vs jump vs out-prioritize) versus picked at random. |
| `punish_chance` | Chance of punishing perceived endlag. |
| `combo_depth` | How many follow-ups it chains after a hit, with true-combo checks. |
| `spacing_error` | Units of random error added to the range it aims for. |
| `timing_error` | Frames of random error on macro timings (short hop, tech press, ledge release). |
| `move_pool` | Which move categories are allowed or weighted: jab/tilts → aerials and smashes → dash dance and short-hop aerial pressure. |
| `smash_charge` | Whether and how long it charges smash attacks on predicted punishes. |
| `tech_chance`, `tech_mixup` | Whether it presses shield in the tech window, and how evenly it picks in place / roll in / roll out. |
| `di_quality` | 0 = no DI, then random, then survival DI, then situational DI (combo DI at low percent, survival DI at kill percent) plus SDI. |
| `recovery_options` | Which recovery tools it may use and mix (unlocks, like Smash 4 Luigi), and how much it varies height and timing. |
| `edgeguard_appetite` | Willingness to go offstage. Gated by R3. |
| `ledge_mixup` | Variety and timing of ledge options; uses ledge intangibility well. |
| `anticipation` | Ultimate-style pre-emptive defence when an opponent enters its threat range, instead of reacting to the hitbox. |
| `adaptation` | Strength of the habit model (§2.12, optional). |

**Starting values** (tune with the ladder harness, §2.14):

| Lv | Value | Reaction (frames) | Decide every | Follow-through | Defend | Punish | Tech | DI | Moves | Recovery | Edgeguard |
|----|-------|-------------------|--------------|----------------|--------|--------|------|----|-------|----------|-----------|
| 1 | 0   | 40 ± 8 | 30 | 0.15 | 0.05 | 0.05 | 0.00 | none | jab, tilts, dash attack | up special, one fixed pattern | never |
| 2 | 15  | 36 ± 7 | 26 | 0.30 | 0.12 | 0.12 | 0.05 | none | + smashes (uncharged) | fixed pattern | never |
| 3 | 21  | 34 ± 7 | 24 | 0.37 | 0.16 | 0.16 | 0.10 | random | + aerials vs airborne | fixed + double jump timing | never |
| 4 | 31  | 31 ± 6 | 20 | 0.48 | 0.25 | 0.25 | 0.20 | random / survival | + short hop aerials | 2 heights | stays onstage |
| 5 | 42  | 27 ± 5 | 16 | 0.58 | 0.35 | 0.38 | 0.35 | survival 50% | + charged smash punishes | + air dodge | ledge trap |
| 6 | 48  | 26 ± 5 | 14 | 0.64 | 0.42 | 0.45 | 0.45 | survival 70% | + jump-cancel up smash out of shield | + drift mixups | ledge trap, rare offstage |
| 7 | 60  | 22 ± 4 | 10 | 0.75 | 0.55 | 0.60 | 0.60 | situational | + 2-hit strings | + high/low mixups | offstage when safe |
| 8 | 75  | 18 ± 3 | 7  | 0.87 | 0.70 | 0.78 | 0.75 | situational + SDI | + dash dance, aerial shield pressure | full mixups | offstage + ledge steal |
| 9 | 100 | 10 ± 2 | 4  | 0.98 | 0.85 | 0.95 | 0.90 | optimal + SDI | everything, 3+ hit strings | full mixups, fights back | aggressive, R3-checked |

Notes:
- Human visual reaction time is about 15–25 frames (250–400 ms). Level 9's 10 frames, plus anticipation and extrapolation, makes it slightly superhuman but beatable. It can't react to a frame-3 jab started up close, which keeps aerial combos and mix-ups viable (fixing the §1.5 complaint).
- **Debug level 10, "frame-perfect"** (reaction 1, no errors): Smash-faithful level 9 behaviour, for the ladder harness, benchmarking and anyone who wants Brawl's level 9 back. It's hidden behind the debug menu and not in normal play.
- Low levels are weak because they are **passive and slow, not suicidal**. Level 1 still recovers from easy positions (its pattern is just predictable and gimpable), so a beginner gets a fair stock rather than a free self-destruct. This differs from 64 and Melee on purpose.

### 2.6 Move knowledge (`MoveProfile`, our ATKD)

`MoveBook` builds a profile for every move in a `Moveset` when first used, and caches it per `Moveset` resource:

- `startup`: first active frame. `active_end`: last active frame. `total`: `total_frames`, plus `landing_lag` for aerials.
- `reach`: the bounding box of all hitbox spheres (offset ± radius) relative to the feet, with +x forward. Also a list of per-frame boxes for the precise check.
- `motion`: displacement from `motion_velocity` over the motion frames (dash attacks, up specials), integrated with or without gravity per `gravity_during_motion`.
- `is_aerial`, `is_smash`, `chargeable` (`charge_frame > 0`), `ends_in_helpless`, `ledge_grab_frame`.
- `damage` and `knockback_at(percent, weight)` from `SmashFormulas` (with the 1v1 multiplier and staleness from the attacker's `stale_queue`). From these: `kill_percent(target, position)`, an estimate using `Predict` to see whether the launch passes the blast zone.
- `safety`: endlag on whiff (`total − active_end`) and on shield (endlag minus shieldstun from `SmashFormulas.shieldstun_frames`). Compared with the opponent's fastest move (its `MoveBook.fastest_startup`), this gives "punishable by".
- `recovery_vector` for up and side specials: the displacement envelope given stick steering (`motion_steer`). `RecoverSituation` uses it.

**Hit query.** `MoveBook.moves_hitting(self_snap, target_prediction, within_frames)` steps the target's predicted hurt capsule forward, using the same segment-capsule test as `HitResolver`, and returns `(move, frames_until_hit, expected_value)`.
Because profiles come from `MoveData`, the specials, grabs and new animals the README lists as next steps get used by the CPU automatically when they land.

### 2.7 Stage knowledge (`StageModel`)

Built once from `Stage`:

- **Main ground:** left and right x and top y, from the two `StageLedge`s (side −1/+1) plus a downward ray to confirm solid ground. Walls below the ledges come from short horizontal rays, so recoveries don't plan through the stage.
- **Soft platforms:** each `SoftPlatform`'s top and x extent (`get_top()`).
- **Blast zone** and **respawn point**.
- Queries: `is_over_stage(x)`, `ground_below(point)`, `nearest_ledge(point)`, `distance_offstage(point)`, `blast_margin(point)` and `edge_distance(x)`, which also prevents self-destruct dashes when edge stops don't apply, for example during dash attack motion.

### 2.8 Perception

Every frame `AiWorld.capture()` stores one `FighterSnapshot` per fighter. A CPU with reaction R reads the opponent snapshot from frame `now − R − jitter`, then **extrapolates** it to now:

- Ballistic flight: velocity, the fighter's gravity, fall speed and launch decay.
- Ground motion: velocity and traction.
- State progress: a move seen on frame f is now on frame f + R. Extrapolation is weighted by `extrapolation`, so a low level aims at the stale position.

This gives the two things that make human reactions feel human: you see a move start late, and you guess where people are now.

**Threat detection** reads the predicted present. A threat is an opponent hitbox that is active or will become active within k frames: its move is known from the snapshot, so `MoveBook` knows when the hitboxes appear and where.
At high `anticipation` the CPU also counts an opponent that is approaching inside its own best reach. This is Ultimate's proximity anticipation, and it lets high levels defend fast moves without frame-1 reactions.

**Own state** is read directly from the `Fighter`: state, frame, jumps, air dodge, shield HP, `frames_until_actionable()`.

### 2.9 Execution (`InputPlan` macros)

Situations output **intents** ("short-hop forward air toward x=40", "shield for 12 frames then jump-cancel up smash"). `InputPlan` turns an intent into timed `InputFrame`s that the current input rules accept. Macros, with the rules they must respect:

| Macro | Inputs | Gotchas in our `InputTracker` / states |
|-------|--------|--------------------------------------|
| Walk | stick x = ±0.5 | Must stay under `FLICK_TO` (0.8) or it dashes. |
| Dash / dash dance | stick 0 for 1 frame, then ±1; alternate sign to dash dance | Flicks need a start below `FLICK_FROM` (0.3) or on the other side within 3 frames. |
| Run, run brake | hold ±1 after `dash_frames` | |
| Full hop / short hop | press jump; for a short hop release before `jumpsquat_frames` end | Jump + attack in jumpsquat gives a short-hop aerial with the attack buffered. **An up flick plus attack in jumpsquat becomes a jump-cancelled up smash**, so a short-hop up air must press attack after leaving the ground, or tilt up below 0.8. |
| Double jump | press jump in the air, stick for drift | `try_double_jump` takes stick x for momentum. |
| Fast fall | stick y crosses below −0.65 while falling | **Holding down in the air also makes soft platforms non-solid and blocks ledge grabs.** Release before the ledge. |
| Drop through | flick down on a soft platform | |
| Tilt | stick ramped to 0.6–0.75, then attack | No flick. Ramp over ≥ 3 frames or go via neutral. |
| Smash / charge | `smash = true` (or C-stick) with direction; hold `attack`/`smash` to charge | Using `smash` avoids flick-timing issues. |
| Aerial | attack with stick ≥ 0.5, or C-stick | Forward and back are relative to facing at press time. |
| Special | special + stick ≥ 0.65 in the direction | Side special sets facing. Up special out of shield and jumpsquat is allowed. |
| Shield / roll / spot dodge | hold shield; flick x to roll; flick down to spot dodge | Shield lasts at least `SHIELD_MIN_FRAMES`; dropping it takes `SHIELD_DROP_FRAMES` (11). |
| Air dodge | shield in the air + stick direction | Once per airtime (`air_dodge_used`). |
| Ledge options | jump / shield (roll) / toward or up (climb) / away or down (drop) | Nothing for the first 6 frames (`GRAB_LAG`). |
| Tech | **one** shield press so that landing falls inside `TECH_WINDOW` (11 frames) | Pressing early triggers `TECH_LOCKOUT` (40 frames). Low levels' timing error makes them miss naturally. |
| DI / LSI | hold the stick on the frame hitlag ends (`_launch` reads it then) | |
| SDI | change octant at most every `SDI_INTERVAL` (4) frames during hitlag | |

Plans can be interrupted: getting hit clears the plan, as `receive_hit` clears the input buffer. Each macro gets a Phase 1 test proving it reaches the intended fighter state.

### 2.10 Situations (routines) and what the level changes

`CpuController` picks the situation from its own activity and the predicted world, in priority order: hit reaction > recovering > ledge > grounded down > respawn > defend > punish > advantage/edgeguard > neutral.
Each situation scores a small set of **tactics**:

```
utility = expected_reward × hit_or_success_probability
          − risk (frames punishable × opponent damage per frame)
          − repetition_penalty
          + personality_bias + profile_bias
```

It then picks one with a softmax whose temperature drops as skill rises: low levels are noisy, high levels near-greedy but never deterministic (R2).
The chosen tactic then passes the `follow_through` roll before its first input; on failure, the CPU idles or wanders for a short time. This is the single biggest Smash-like level lever.

**Respawn.** Wait a random time inside the revival window (`RespawnState` 20–300 frames), shorter at high levels, then drop.
High levels drift toward the side away from the opponent, or use the invincibility (`RESPAWN_INVINCIBILITY` 120) to pressure. They hold off while the opponent is attacking below the platform (Brawl).

**Neutral.**
- Keep a **preferred range**: just outside the opponent's best quick reach and inside its own, both from `MoveBook`, plus `spacing_error`.
- Approach options: walk, dash, run, short-hop aerial, dash attack (heavily weighted at low levels, like Melee), platform drop or jump.
- Waiting options: wait, retreat, shield and wait (bait), dash dance (level 8+, Ultimate).
- When the hit query finds a move landing within the decision horizon, attack.

**Defend** (a threat perceived after the delay, or anticipated).
- Options: shield, spot dodge, roll away, roll behind, jump out, out-prioritize with a faster move (trade check), air dodge (air only), drift away (air).
- Each is scored by: intangibility frames against the threat's active frames (the fighter's own roll and spot dodge stats, so slow rolls score low, R5), shield HP against the move's shield damage, and position (never roll off the stage, R7).
- Shield HP: never hold the shield below a safe value at high levels. Low levels may hold it too long (a Smash 3DS flaw kept on purpose for low levels only).
- **Out of shield**, after shieldstun ends: up special, jump-cancelled up smash, jump aerial, roll, drop shield and attack. Grab joins when grabs are added. Picked by `MoveBook` startup against the attacker's `frames_until_actionable` (R5).

**Punish.** The opponent's predicted `frames_until_actionable` (endlag, landing lag, missed tech, shield break, helpless landing) exceeds the CPU's travel time plus startup.
Pick the move with the biggest expected reward that fits: kill move if `kill_percent` ≤ the target's percent, charged smash if the window allows. Ultimate high levels also wait out a committed move instead of trading into it.

**Advantage / juggle / combo.** After a hit, use `Predict` with the real knockback and hitstun to find the target's path. Follow up if `hitstun_left ≥ travel + startup` (a true combo), up to `combo_depth`.
Above that, cover the landing or air-dodge options (juggle).
This replaces Smash 4's "always down throw into X". The check runs at the *current* percent, so the CPU stops when the follow-up stops working (R5).

**Edgeguard / ledge trap** (opponent offstage).
- Onstage: hold the ledge to steal it (ledge trump is implemented), charge a smash or tilt to cover the ledge getup and roll, or punish the landing.
- Offstage (levels 7+, `edgeguard_appetite`): intercept with an aerial, but only if **R3 passes**: from the intercept point, with jumps and up special left, can the CPU still reach a ledge?
- Only the CPU nearest to the target and best placed may go deep, which avoids Ultimate's flocking.

**Recover** (self offstage). A planner rather than a script:
1. Enumerate a small set of candidate plans:
   - drift now or after a delay;
   - double jump now, later, or not at all;
   - up or side special at a chosen height and steer;
   - directional air dodge;
   - target: ledge (with sweetspot), stage top, or a soft platform.
2. Simulate each with `Predict`, using the fighter's stats and the special's `MoveProfile.recovery_vector` and `ledge_grab_frame`.
3. Drop failing plans. Score the rest by margin, predictability (repetition penalty) and exposure to the edgeguarder's predicted threat.
4. Low levels see few candidates (fixed pattern, up special only). High levels see all of them, delay their jumps, aim high or low, and fight back with aerials when the edgeguarder comes within reach (Ultimate).
- Don't hold down near the ledge (fast fall blocks the grab).
- Don't burn the air dodge early unless it's needed to avoid a hit (fixes Smash 4's habit of air dodging off course).

**Ledge.** Wait a random time, using up to the `LEDGE_INTANGIBILITY` (40) frames well at high levels. Then:
- climb if the opponent is far;
- roll if the opponent is close and standing;
- jump if the opponent is low or committed;
- drop and double jump into an aerial (high levels).
Weighted by the habit model when adaptation is on. Ledge attack joins when it's ported.

**Hit reaction.**
- *In hitlag:* SDI pulses (count by level) away from the attacker's follow-up and toward the stage when near a blast zone. DI with `AiDi` by `di_quality`: survival DI at kill percent, combo DI (away and behind) at low percent.
- *In hitstun:* air dodge or aerial cancel at `HITSTUN_AIR_DODGE_CANCEL`/`HITSTUN_AERIAL_CANCEL` frames only if a follow-up threat is perceived. Ultimate CPUs spend it on reflex; we don't (R4).
- *Tumble landing:* tech by `tech_chance` and `timing_error`, with an even in-place/roll split by `tech_mixup`. This fixes Ultimate's "techs only by accident".

**Grounded down (knockdown).** Mix get-up, roll left/right and a short wait (`MIN_LYING_FRAMES`–`MAX_LYING_FRAMES`) by `ledge_mixup`-like randomness. This fixes Ultimate's "always gets up after a fixed time". Get-up attack joins when it's ported.

**Shield break.** There's no mash mechanic yet. If one is added, the mash rate scales with level (Smash level 9 mashes frame-perfectly).

### 2.11 Personality and per-character profiles

- `CpuPersonality` (amiibo-style), separate from skill. Each weight is −1…+1 and adds to tactic utility:
  - `aggression`: approach vs wait
  - `air_preference`: aerials vs grounded moves
  - `risk`: smash attacks, offstage play
  - `defense_style`: shield vs dodge vs jump
  - `edgeguard_appetite`
  - `patience`: how long it waits at the ledge or in shield
- **Per-character defaults** come from `FighterData.cpu_profile` (`CpuProfile`): for example Bear grounded and smash-happy, Cat aerial. A small seeded variation per match keeps two CPU Cats from playing alike.
- `CpuProfile` can also adjust move weights (e.g. "never use down air offstage") and add recovery hints. **It is for flavour and fixes only.** The CPU must play reasonably with no profile (goal 4), the way Brawl's common AI does before a character override.

### 2.12 Adaptation (optional)

amiibo learn across matches. Ours would be **per match and deterministic**: a habit model that counts the opponent's choices per situation bucket. Buckets:
- ledge option and timing
- tech direction
- get-up option
- shield or attack when approached
- roll direction
- air dodge after being launched

Counts decay over time. When `adaptation > 0`, the CPU tilts its coverage toward the opponent's most likely option, for example charging a smash where the opponent usually rolls.
This answers Smash's most common criticism, that you can't train against CPUs because they never adapt, while keeping matches reproducible. It's off below level 6 and part of the level 9 identity.

### 2.13 Determinism, rollback and performance

- Each `CpuController` owns a `RandomNumberGenerator`, seeded from the match seed and its slot. **No global `randf()`, no wall-clock reads**, and nothing that depends on frame rate.
  The match seed is printed in the training overlay so a bug can be reproduced.
- For rollback later: `CpuController.save_state()`/`load_state()` cover the RNG state, current situation, plan queue and habit model. `AiWorld`'s snapshot ring buffer rolls back with the world.
- **Budget:**
  - Perception: O(fighters).
  - Situation choice: cheap checks every frame.
  - Tactic scoring: only every `decision_interval` frames or when the situation changes.
  - `Predict`: closed-form or ≤ 60 fixed steps per query, and at most about 20 queries per decision.
  - Profiles: cached per `Moveset`.
  - No per-frame allocations beyond the single `InputFrame` the controller already returns.
- Measure with a headless benchmark: 10,000 frames of CPU level 9 vs CPU level 9, timing `poll()`, on desktop and in the Web export.

### 2.14 Testing and tuning

**Unit and integration tests**, added to `tests/run_tests.gd`, which uses scripted controllers on the real stage:

- *Macros:* each `InputPlan` macro reaches its target state (short hop gives the short-hop apex, tilt doesn't turn into a smash, fast fall doesn't block a ledge grab once released, tech press lands in the window).
- *Determinism:* two runs of CPU vs CPU with the same seed give identical `InputFrame` streams for 1,200 frames.
- *Input validity:* stick length ≤ 1 on every frame, and no state change made by AI code. An instrumented `Fighter` asserts that `change_state` is only called from `tick()`.
- *Reaction:* the same scripted forward smash is shielded later by level 3 than by level 9, and never sooner than `reaction_frames` after its first visible frame.
- *Recovery:* from a grid of offstage positions and velocities that the planner says are recoverable, level 9 recovers at least 98% of the time and level 1 at least 80% (passive, not suicidal).
- *No self-destructs:* 60 s of each level vs a stand dummy gives zero self-destructs.
- *Punish:* a dummy whiffing an unsafe smash in range gets punished by level 9 in at least 90% of trials, and by level 1 in at most 20%.
- *DI:* the same kill-percent hit; a level 9 CPU's launch survives where a no-DI dummy dies.

**Ladder harness** (`tests/ai_ladder.gd`, slow, run by hand or nightly; not in the 2 s suite):
- Plays N headless first-to-3-KO matches between every pair of levels and characters.
- Prints the win-rate matrix plus telemetry per level: average reaction, shield rate, punish rate, recovery success, self-destructs, move usage histogram, average match length.
- **Done when the win rate rises with level**, with each level beating the one below it at least 60% of the time.
- It doubles as the balance harness proposed in `plans/physics-and-stats-review.md` (S2): CPU level 9 mirrors on every character show tier outliers.

**Debug views:**
- F3 toggles **AI debug** in the training overlay: per CPU its level, situation, chosen tactic and score, plan queue, reaction delay and seed.
- A ghost of the *perceived* opponent next to the real one.
- Predicted recovery path and hit-query boxes, drawn with `FighterDebugDraw`.

### 2.15 UI

- **Pause menu:** per slot "Human / CPU" (P2 also "Dummy: stand / shield / jump", which become CPU modes), plus a **level selector 1–9**.
  Use large touch targets (touch is first-class) and colour the level from indigo to red, as in Smash 4 and Ultimate. Brawl's adjectives (Puny … Nasty) could go in a tooltip.
- **HUD:** the damage meter shows "CPU" and the level for CPU slots.
- The level selection persists in user settings. A future character select screen reuses the same `PlayerSlot`.

---

## Part 3 — Implementation phases

### Phase overview

| # | Phase | Effort | Playable result | Status |
|---|-------|--------|-----------------|--------|
| 0 | Plumbing: `PlayerSlot`, `CpuController` skeleton, `AiWorld` capture, menu, seeded RNG | S | CPU walks toward you | todo |
| 1 | Execution layer: `InputPlan` macros and tests | M | Debug CPU can be told "short-hop fair" and does it | todo |
| 2 | Knowledge: `MoveProfile`/`MoveBook`, `StageModel`, `Predict`, `frames_until_actionable` | M | Training overlay shows "in range: f-tilt (3f)" | todo |
| 3 | Neutral, defend, punish + `CpuDifficulty` curves | L | A real level 1–9 opponent on stage | todo |
| 4 | Recover, ledge, edgeguard (R3 planner) | L | CPU survives offstage and edgeguards | todo |
| 5 | Hit reaction: DI/SDI/tech/getup; fold `DummyController` into CPU modes | M | Hard to combo at high level, easy at low | todo |
| 6 | Tuning: ladder harness, personalities, per-character profiles, AI debug draw | M | Levels feel distinct; win rate rises with level | todo |
| 7 | Optional: habit model (adaptation), advantage/combo depth, multi-fighter targeting | M | Level 9 adjusts to your ledge habits | todo |

### Phase 0 — Plumbing

**Files:** `ai/cpu_controller.gd`, `ai/ai_world.gd`, `ai/fighter_snapshot.gd`, `match/player_slot.gd`, `match/match.gd`, `ui/pause/pause_menu.gd`, `ui/hud/*`, `tests/run_tests.gd`.

- Add `PlayerSlot`. Port `Match.selections`, `player_two_human` and `dummy` to `slots: Array[PlayerSlot]`, and keep the pause menu working.
- `CpuController` with `level`, `mode`, `rng`, and `poll()` returning a walk toward the nearest opponent's delayed position. Modes STAND, SHIELD and JUMP delegate to an internal `DummyController` for now.
- `AiWorld.capture()` at the end of `Match._physics_process` and of the test world.
- Seed: `Match.seed` (random at match start, printed in the overlay); CPU seed = hash(match seed, slot).

**Done when:** P2 can be set to CPU level 1–9 from the pause menu and walks toward P1. The CPU sees P1 `reaction_frames` late (a test checks the delay). The existing tests still pass. The smoke run prints only the banner.

### Phase 1 — Execution layer

**Files:** `ai/input_plan.gd`, tests.

- Implement every macro in §2.9, with `timing_error` support (0 in tests).
- A debug hook (`CpuController.force_plan(...)`) so tests and the overlay can run a macro directly.

**Done when:** a test per macro confirms the fighter reaches the expected state on the expected frame, including the gotchas in §2.9 (short-hop up air isn't an up smash; fast fall released in time still grabs the ledge; one tech press inside the window techs, and a press 12+ frames early misses).

### Phase 2 — Knowledge

**Files:** `ai/move_profile.gd`, `ai/move_book.gd`, `ai/stage_model.gd`, `ai/predict.gd`, `fighters/states/*` (`frames_until_actionable`), `ui/debug/training_info.gd`.

- Derive profiles for Cat's and Bear's movesets. Test reach boxes against hand-checked `.tres` values (e.g. Cat's forward smash hits at frame 15 with reach to about x = 15).
- `Predict.trajectory()` matches the real simulation: a test launches a fighter and compares the predicted position at +20 frames to the real one, within 1 unit.
- The training overlay shows frames until actionable (the frame advantage readout) for both fighters.

**Done when:** the hit query's "will hit" agrees with `HitResolver` in at least 95% of randomized close-range trials (headless test).

### Phase 3 — Fighting

**Files:** `ai/situations/{neutral,defend,punish}_situation.gd`, `ai/cpu_difficulty.gd(.tres)`, `ai/cpu_controller.gd`.

- Situation choice, utility scoring with softmax temperature, `follow_through`, the repetition penalty, perception with extrapolation and jitter.
- Out-of-shield options. Charged-smash punishes.

**Done when:** the reaction, punish and no-self-destruct tests in §2.14 pass, and a human playtest of levels 1, 5 and 9 feels clearly different.

### Phase 4 — Offstage

**Files:** `ai/situations/{recover,ledge,edgeguard,respawn}_situation.gd`.

- Recovery planner with candidate plans per level; the R3 reachability check shared with edgeguarding.
- Ledge options with timing mixups; ledge stealing.

**Done when:** the recovery grid test passes (level 9 ≥ 98%, level 1 ≥ 80%), and level 9 vs level 9 for 10 minutes has no self-destructs.

### Phase 5 — Hit reactions and CPU modes

**Files:** `ai/di.gd`, `ai/situations/{hit_reaction,grounded_down}_situation.gd`, `input/dummy_controller.gd`.

- Move `_di_stick` to `AiDi`, and use it from both the dummy and the CPU.
- SDI, tech mixups, getup mixups, hitstun cancels only under threat.
- Make STAND, SHIELD and JUMP real `CpuController` modes. Add WALK and EVADE (Smash's Walk and Run). Remove `DummyController`, or keep it as a thin wrapper.

**Done when:** the DI test passes, and the existing `_test_dummy` passes against the CPU modes.

### Phase 6 — Tuning and identity

**Files:** `tests/ai_ladder.gd`, `ai/cpu_personality.gd`, `ai/cpu_profile.gd`, `fighters/fighter_data.gd`, roster `.tres` files, debug draw.

- Ladder harness and telemetry; tune the `CpuDifficulty` curves until the win rate rises with level.
- Default personalities for Cat and Bear and per-archetype profiles for the 12 animals (they share Cat's or Bear's moveset for now).
- AI debug view (F3), perceived-opponent ghost, recovery path drawing.
- Record final values and the reasoning in a new `docs/ai.md`, the counterpart of `docs/physics.md`: what's ported from Smash (levels, value scale, CPU modes) and what's ours (perception delay, R1–R7).

**Done when:** in the ladder, each level beats the one below it at least 60% of the time. The benchmark stays under the budget on the Web export.

### Phase 7 — Optional depth

- Habit model (§2.12) for levels 6+.
- Deeper combos using true-combo checks.
- Multi-fighter targeting (R6) once matches support more than 2 fighters: score targets by distance, threat, kill chance and offstage state, plus a "someone else is already edgeguarding" damping.
- Team awareness when teams exist: no team-attack hits on allies, which all Smash CPUs get wrong.
- When grabs, throws, specials, ledge attack, parry or items land, add their macros and profile flags. The situations pick them up through `MoveBook`.

---

## Open questions

1. **Level 9 feel:** human-plausible (10-frame reactions, as proposed), or Smash-faithful near-frame-perfect defence? This plan proposes the former, with the frame-perfect mode as a hidden debug level 10.
2. **Default P2:** CPU level 3 on launch (proposed for mobile, where there's one human), or keep the stand dummy everywhere until there's a mode select?
3. **Adaptation:** do you want the in-match habit model at all, or should CPUs stay non-adaptive like Smash's (minus amiibo)?
4. **Order with the physics review:** P1, P2 and P5 in `plans/physics-and-stats-review.md` change knockback slides and stick deadzones. `Predict` and the macros depend on them, so land them before Phase 2 to avoid retuning.
5. **Grabs and specials:** both are on the README's next-step list. A CPU without grabs can't beat a shielding human. Should grabs come before Phase 3, or after the AI ships?

## Sources

- SmashWiki, [Artificial intelligence](https://www.ssbwiki.com/Artificial_intelligence): levels, the 0–100 scale, defence, offence and recovery by level, CPU modes, Brawl's input-reading and learning myths, amiibo.
- SmashWiki, [Flaws in artificial intelligence](https://www.ssbwiki.com/Flaws_in_artificial_intelligence): per-game behaviour and flaws (64, Melee, Brawl, Smash 4, Ultimate).
- SmashWiki, [List of CPU modes](https://www.ssbwiki.com/List_of_CPU_modes): Stand / Walk / Jump / Run / CPU and Ultimate's training modes.
- SmashWiki, [amiibo](https://www.ssbwiki.com/Amiibo): Figure Players, learning, and turning learning off in Ultimate.
- Smashboards, [AI Handbook 2.0x](https://smashboards.com/threads/ai-handbook-2-0x-readable-syntax-stable.300461/): Brawl AI files (`AIMain` routines, `ATKD`, `AIPD`; `Fighter.pac` default AI overridden per character). Only seen through a search summary; the page itself blocked fetching.
