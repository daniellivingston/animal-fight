# Physics & Fighter Stats Review — Recommendations

Status: **proposed** · Reviewed: 2026-10-16 at `74a1e8f`; re-reviewed at `caf1453` (14-fighter roster) · Scope: `combat/`, `fighters/`, `input/`

A code review of the physics and fighter-stats systems. It covers two things:

1. Making it easy to keep a roster of dozens of characters balanced.
2. Improving game feel: responsiveness, tight controls, and hits that feel tactile.

The numbers labelled **Measured** came from headless probe scripts run against `caf1453`. All 410 tests passed at re-review.

**Re-review summary:** none of the original items had been fixed by `caf1453`. The gameplay code (`fighter.gd`, `smash_formulas.gd`, the states, input) hasn't changed since `74a1e8f`. The 12 new animated fighters reuse the Cat and Bear movesets and copy Bear's stats blocks, so S3 and S4 are now roster-wide problems. The re-review added S6–S7 and P9–P10.

## How to use this document

- Each item has an ID (`P1`, `S2`, …), the files it touches, the problem, a recommended fix, and the result to check for once it's done ("Done when").
- Line numbers are as of `caf1453` and will drift, so search by function name.
- Follow the rules in `CLAUDE.md`:
  - Smash Ultimate units only.
  - New constants and formulas go in `SmashFormulas`, with a source comment.
  - Record what was ported or approximated in `docs/physics.md`.
  - Models are visual only.
  - Run the test suite after every gameplay change.
- When an item is done, update its status in the [Priority order](#priority-order) table. Add a regression test where the "Done when" line describes something measurable.

## Roster at a glance

Fighters share two movesets: the Cat moveset and the Bear moveset.

| Moveset | Fighters                                                                                  |
|---------|-------------------------------------------------------------------------------------------|
| Cat     | Cat, Fox, Wolf, Husky, Shiba Inu, Deer, Alpaca                                            |
| Bear    | Bear, Bull, Cow, Donkey, Horse, Stag, White Horse (all copy Bear's dodge / air-dodge block) |

## Priority order

| #  | ID  | Item                                                         | Effort | Impact                   | Status |
|----|-----|--------------------------------------------------------------|--------|--------------------------|--------|
| 1  | P1  | Grounded hitstun slide ignores traction                      | S      | High (feel, correctness) | todo |
| 2  | P2  | Low-angle tumble landings bounce and refund resources        | S      | High (feel, correctness) | todo |
| 3  | P5  | Double stick deadzone (gamepad and touch)                    | S      | High (controls)          | todo |
| 4  | S4  | Shared up tilt / up smash miss most of the roster            | S–M    | High (balance)           | todo |
| 5  | S1  | Archetype base resources; freeze `FighterStats` defaults     | M      | High (roster scaling)    | todo |
| 6  | S2  | Balance harness tests (KO % bands, move reach, index bands)  | M      | High (roster scaling)    | todo |
| 7  | S3  | Heavies out-run and out-dodge lighter fighters               | S      | High (balance)           | todo |
| 8  | P4  | Hit feedback tied to hitlag (flash, shake, camera)           | M      | High (feel)              | todo |
| 9  | P9  | Attack animation contact frame ≠ hitbox start frame          | M      | High (feel)              | todo |
| 10 | P3  | Ultimate balloon knockback + 70–110° fall speed              | M      | High (feel)              | todo |
| 11 | S5  | Explicit jump airtime (floaty vs fast-faller)                | M      | Medium (roster scaling)  | todo |
| 12 | S6  | Crouch doesn't shrink small fighters' hurtboxes              | S      | Medium (balance)         | todo |
| 13 | P6  | Shield hitlag clamp inflates low-multiplier hitboxes         | S      | Medium (correctness)     | todo |
| 14 | P7  | Attacker shield pushback + parry                             | M      | Medium (balance)         | todo |
| 15 | P10 | Mid-air jumps show no animation                              | S      | Medium (feel)            | todo |
| 16 | S7  | Fox walk speed outside documented Ultimate range             | S      | Low                      | todo |
| 17 | P8  | Polish: turn rate, edge stops, buffer during hitlag, shieldstun check | S each | Low–Medium   | todo |

P1, P2 and P5 are small, contained fixes with an outsized effect on feel. Do them first. S4 makes seven characters lack a grounded anti-air against standing targets, so fix it early.

S1 and S2 should land **before** more characters are added. Retrofitting archetypes onto 14 `.tres` files is already harder than it was at 2. It only gets worse.

---

## Part 1 — Physics & game feel

### P1. Grounded hitstun slide ignores traction

**Files:** `fighters/states/hitstun_state.gd` (`update`, lines 30–31), `fighters/fighter.gd` (`apply_traction`, `_move`)

**Problem**
- On the ground, `HitstunState.update()` calls `f.apply_traction()`.
- Traction only slows `velocity_self`, which `_launch` sets to zero.
- `velocity_knockback` therefore slides along the floor, slowed only by the air launch decay (`LAUNCH_DECAY`, 0.051).
- Hitstun can end while knockback is still non-zero. The leftover knockback keeps moving the fighter after it becomes actionable.

**Measured** (Cat forward tilt at 40%)

| Fighter | Traction       | Slide (units)  |
|---------|----------------|----------------|
| Horse   | 0.09 (lowest)  | 22.5           |
| Bull    | 0.13 (highest) | 19.6           |
| Fox     | 0.122          | 27.5 (longest) |

- The slide length follows the knockback size, not traction. Horse's description ("slides on stops") has no effect on hits.
- Every fighter still has 0.57–0.67 u/f of knockback x-speed on its first actionable frame.

**Fix**
- While grounded, decay `velocity_knockback.x` by `traction + LAUNCH_DECAY` per frame, in `HitstunState.update()` or `Fighter._move`.
- Zero the grounded knockback when hitstun ends (in `to_neutral()` or on hitstun exit).
- Record the source and any approximation in `docs/physics.md`.

**Done when**
- `velocity_knockback == Vector2.ZERO` on the first actionable frame.
- A test asserts that, under the same hit, Horse slides further than Bull.

### P2. Low-angle tumble landings bounce and refund resources

**Files:** `fighters/fighter.gd` (`land_from_tumble`, line 493; `_land`, lines 257–258)

**Problem**
- The bounce condition is `velocity_knockback.y < 0.0 and velocity_knockback.length() >= GROUND_BOUNCE_SPEED`. It tests total speed, not downward speed, so a grazing landing bounces.
- By the time this runs, `_land` has already reset `jumps_used` and `air_dodge_used`. A bounced victim gets its jumps and air dodge back for free. Alpaca (4 jumps) and Cow (3) gain the most.
- On the second contact `vk.y > 0`, so the fighter goes straight to knockdown and gets no correct tech chance.

**Measured:** a tumbling fighter landing with `vk = (2.35, -0.39)` (length 2.38, very little downward speed) bounces back to `vk.y = +0.30`.

**Fix**
- Change the condition to `-velocity_knockback.y >= GROUND_BOUNCE_SPEED`.
- Don't refund jumps or air dodge on a bounce. Either restore them after the bounce check, or snapshot them before `_land` and restore them on a bounce.

**Done when** tests cover all three cases:
- A shallow landing goes to knockdown or tech, not a bounce.
- A steep landing still bounces.
- `jumps_used` and `air_dodge_used` don't change across a bounce.

### P3. Port Ultimate balloon knockback and the 70–110° fall speed

**Files:** `combat/smash_formulas.gd` (`launch_velocity` line 168, `decay_launch` line 173), `docs/physics.md`

**Problem:** launches use plain Smash 4 speed and decay, so strong hits read as floaty.

**Measured**
- A KO-strength hit (knockback ~190, hitstun 75) leaves at 5.7 u/f and takes over 100 frames to decay.
- A 100% Cat forward smash on Cat takes about 97 frames to reach the blast zone.

**Fix**
- Port Ultimate's launch speed-up for high-hitstun launches ("balloon knockback"). For launches above the hitstun threshold, scale initial launch speed and decay together so that:
  - total travel distance stays the same;
  - hitstun stays the same;
  - the distance is covered in far fewer frames.

  This is most of why Ultimate's kill hits feel snappy.
- Add the 1.8 fall speed for 70–110° launches. It's already listed as missing in `docs/physics.md`.
- Put the constants in `SmashFormulas` with source comments, and update `docs/physics.md`.

**Done when**
- A test compares launch distance with balloon knockback on and off. It confirms the total distance matches within tolerance and the launch reaches its peak in fewer frames.
- The S2 KO % sweep doesn't shift beyond tolerance.

### P4. Hit feedback tied to hitlag (flash, shake, camera)

**Files:** `fighters/fighter_model.gd` (`flash`, lines 38–39; random shake, lines 87–90), `fighters/animated_fighter_model.gd` (reuses the same shake), `camera/` (FightCamera), `HitInfo` (already carries hitlag and knockback)

**Problem**
- `flash()` sets a fixed 4 frames. Hitlag lasts 10–30 frames, so the flash ends early in the freeze.
- The victim's shake is a random jitter of constant magnitude (~0.06 m), and interpolation smooths it further.
- The attacker freezes but doesn't shake.
- The camera doesn't react at all.
- As a result, weak and strong hits look nearly the same.

**Fix**
1. **Flash:** keep the flash on for the whole hitlag. Pass `info.hitlag` into `flash()`.
2. **Victim shake:** shake along the launch angle with alternating sign, sized by knockback and decaying over the hitlag. It should be a deliberate offset, not random noise. Apply it to the visual pivot, not the physics body, so interpolation doesn't smooth it away.
3. **Attacker shake:** a smaller version of the same shake.
4. **Camera:** shake scaled by knockback, plus an optional brief zoom on strong or KO hits.
5. Keep everything presentational. No gameplay state may depend on it.

**Done when**
- In a `--write-movie` capture, the flash lasts the whole hitlag.
- A fully charged smash looks clearly different from a jab.
- The camera responds to hits above a knockback threshold.

### P5. Double stick deadzone

**Files:** `input/player_controller.gd` (`poll`, line 20), `fighters/fighter.gd` (line 22), `input/input_tracker.gd` (lines 14–15), and the touch stick

**Problem**
- `Input.get_vector(...)` uses the actions' 0.2 deadzone and rescales the result.
- `MOVE_DEADZONE` (0.2), `FLICK_FROM` (0.3) and `FLICK_TO` (0.8) are then applied to that rescaled value.
- Together, these push the effective thresholds up:
  - walking needs ~0.36 physical deflection;
  - a dash or smash flick needs ~0.84 physical, starting below ~0.44, within 3 frames.
- The touch stick goes through the same rescale. Partial flicks come out as walks or tilts.

**Fix**
- Read raw axes by passing `deadzone = 0` to `get_vector`, or by reading the axes directly.
- Keep **one** set of Smash-calibrated thresholds in `InputTracker`.
- Check that the touch stick produces values on the same scale as a gamepad.

**Done when** an `InputTracker` test drives raw stick values and confirms:
- walking starts at the intended physical deflection;
- a flick from neutral to ~0.8 within the window registers as a dash or smash.

### P6. Shield hitlag clamp inflates low-multiplier hitboxes

**Files:** `combat/smash_formulas.gd` (`hitlag_frames`, line 131)

**Problem:** `multiplier = maxf(multiplier, 1.0) * HITLAG_SHIELD`. A hitbox with `hitlag_multiplier = 0.3` gets 0.3× hitlag on hit but 0.67× on shield, more than twice as much.

**Fix:** use `multiplier * HITLAG_SHIELD`. If the clamp is intentional, document it with a source comment.

**Done when** a unit test checks that shield hitlag is never longer than hit hitlag for the same hitbox.

### P7. Attacker shield pushback and parry

**Files:** `fighters/fighter.gd` (`receive_shield_hit`, lines 592–596), `fighters/states/shield_state.gd`, `combat/smash_formulas.gd`

**Problem**
- Only the defender gets pushback.
- A grounded attacker stays flush against the shield, so moves that should be unsafe can still be spaced from inside it.
- There's no parry.

**Fix**
- For grounded hits, split pushback between attacker and defender, as Ultimate does.
- Add a parry window on shield release.
- Put both in `SmashFormulas` with source comments, and update `docs/physics.md`.

**Done when** tests confirm:
- The attacker is moved away on a grounded shield hit.
- A shield released within the parry window turns the hit into a parry.

### P8. Smaller polish items

- **Turnarounds:** `TURN_RATE` is 0.45 (`fighters/fighter_model.gd:14`). Raise it to ≥ 0.8, or snap on turnaround, so turns look as instant as they play.
- **Edge stops:** at a ledge stop (`fighters/fighter.gd:231`), place the fighter exactly at the edge. Today it's rolled back a whole frame (`global_position = previous`), which looks like a stutter.
- **Buffer during hitlag:** consider freezing input-buffer aging during hitlag. Presses made during a long freeze would then survive.
- **Shieldstun:** check `shieldstun_frames` against Ultimate's separate aerial and grounded multipliers.

### P9. Attack animation contact frame doesn't match the hitbox start frame

**Files:** `fighters/animated_fighter_model.gd` (line 65)

**Problem**
- Every attack plays the same `Attack_Headbutt` clip, stretched over `move.total_frames`.
- Hitboxes start at different points in each move. For Bear's moveset:
  - jab: frame 5 of 24, about 21% of the way through;
  - forward smash: frame 19 of 57, about 33%.
- So hitlag freezes the model before or after the head visibly connects. Hits don't look tactile on any of the 12 animated fighters.

**Fix**
- Give each move a contact frame in the clip (per move or per clip).
- Time-warp the animation in two pieces: play startup up to contact so it lands on the hitbox's `start_frame`, then play the rest over the remaining frames.
- Keep it visual-only, stepped from `sync()` (see `CLAUDE.md`).

**Done when** in a `--write-movie` capture, the clip's contact pose is on screen during hitlag for both a jab and a smash.

### P10. Mid-air jumps show no animation

**Files:** `fighters/animated_fighter_model.gd` (line 93), `fighters/fighter.gd` (`try_double_jump`, line 326)

**Problem**
- The jump animation restarts only on a state change.
- `try_double_jump` stays in `AirState`, so a mid-air jump doesn't restart it.
- The model holds the last frame of `Gallop_Jump` while rising again. This is worst for the multi-jump fighters, Alpaca and Cow.

**Fix**
- Restart the jump clip whenever `jumps_used` increases, or have the fighter emit a jump signal or counter that the model watches.

**Done when** every mid-air jump visibly restarts the jump animation.

---

## Part 2 — Fighter stats & roster balance

### S1. Archetype base resources; freeze `FighterStats` defaults

**Files:** `fighters/fighter_stats.gd`, `fighters/roster/*/*.tres`, `docs/fighter-stats.md`

**Problem**
- Every `FighterStats` default is Mario's value, and `.tres` files store only differences.
- Cat's stats sub-resource is still empty.
- All 14 fighters silently rely on unstated defaults:
  - crouch ratio
  - ledge frames
  - jumpsquat
  - landing lag
  - `air_acceleration_base`
- Changing a default moves the whole roster, and nothing flags it.
- The 6 heavy animals copy-paste Bear's 11-line dodge block.

**Fix**
1. Treat the `FighterStats` defaults as **neutral and frozen**. Document that changing them is a roster-wide balance change.
2. Add archetype base resources:
   - `feather`, `light`, `middle`, `heavy`, `superheavy`;
   - plus `floaty` and `fastfaller` modifiers.
3. Move the shared dodge, roll and air-dodge blocks into the archetypes.
4. Make defensive values worse as weight goes up: fewer intangible frames, and longer air dodges and rolls.
5. Each character references an archetype and overrides only what makes it distinct.
6. Give Cat its own explicit stats.
7. **Derive what can be derived**, so fewer hand-tuned values can drift:
   - shield radius from the hurtbox (about `height × 0.5 + margin`);
   - ledge intangibility universal;
   - fast-fall multiplier fixed at 1.6 for everyone.

**Done when**
- Every character names an archetype.
- No `.tres` duplicates the dodge block.
- Changing a default and re-running S2 shows exactly which characters moved.

### S2. Balance harness tests

**Files:** `tests/` (new suites). The only weight test today is Cat vs Bear.

Turn the raw stats into a few **derived indices** and give each archetype an allowed band for each:

| Index          | Inputs                                                         |
|----------------|----------------------------------------------------------------|
| Survivability  | weight, fall speed, gravity (drive horizontal & vertical KO %) |
| Mobility       | initial dash, run, air speed, air acceleration                 |
| Airtime        | full-hop frames (see S5)                                       |
| Recovery       | jump count × air-jump height + up-special distance             |
| Target size    | height × hurtbox radius                                        |
| Speed          | frame of the fastest out-of-shield option; jab frame           |

**Tests to add**
1. **KO % sweep:**
   - Hit every character with one reference `HitboxData`, such as a "Mario forward smash".
   - Hit from stage center, uncharged, testing the side and top blast zones.
   - Assert the KO % falls inside the character's archetype band.
   - Target: under ~25% spread between the lightest and heaviest characters.
2. **Move reach:**
   - Fire every grounded move from every fighter at every other fighter, at resting spacing (`_separate_fighters` distance).
   - Fail unless the move connects or is explicitly flagged `anti_air_only`.
3. **Index bands and ordering rules:**
   - A heavier fighter never out-runs a lighter fighter of the same archetype.
   - Small hurtboxes go with low weight.
   - A speedster's run beats every heavy's.
   - Heavies pay for weight with a bigger hurtbox, higher fall speed or gravity, slower frames, or a worse air dodge. They never pay with more mobility.

**Baseline** (Measured at `caf1453`: uncharged forward smash from stage center, no DI, fighters at resting distance; only launches out of the side or top count)

| Target      | Cat moveset (reference) | Bear moveset |
|-------------|-------------------------|--------------|
| Fox         | 69                      | 44           |
| Shiba Inu   | 70                      | 45           |
| Deer        | 73                      | 47           |
| Alpaca      | 75                      | 49           |
| Wolf        | 76                      | 50           |
| Husky       | 77                      | 51           |
| Cat         | 79                      | 52           |
| White Horse | 82                      | 55           |
| Donkey      | 84                      | 56           |
| Horse       | 86                      | 58           |
| Stag        | 89                      | 60           |
| Cow         | 94                      | 64           |
| Bear        | 96                      | 65           |
| Bull        | 98                      | 67           |

- The reference spread is 69–98%, a 29-point (~42%) gap. That's above the ~25% target.
- The moveset matters more than weight. Any Bear-moveset fighter KOs Cat 27 points earlier (52% vs 79%) than any Cat-moveset fighter.
- Expect these numbers to rise once DI is in play.

**Done when** all three suites run in `tests/run_tests.gd` and fail on an out-of-band character.

### S3. Heavies out-run and out-dodge lighter fighters

**Files:** `fighters/roster/bear/bear.tres` (lines 15, 17, 40–41), `fighters/roster/bull/bull.tres` (lines 16, 37), `fighters/roster/white_horse/white_horse.tres` (line 16), `fighters/roster/horse/horse.tres`

**Problem:** weight comes with extra mobility and a better escape, not a cost.

| Fighter     | Weight | Initial dash | Run   | Moveset | KOs Cat at |
|-------------|--------|--------------|-------|---------|------------|
| White Horse | 104    | 2.3          | 2.53  | Bear    | 52%        |
| Horse       | 112    | 2.3          | 2.3   | Bear    | 52%        |
| Fox ("Speedster") | 77 | 2.2        | 2.402 | Cat     | 79%        |
| Bear        | 130    | 2.1          | 1.85  | Bear    | 52%        |
| Bull        | 135    | 1.9          | 1.87  | Bear    | 52%        |
| Cat         | 98 (default) | 1.936 (default) | 1.76 (default) | Cat | 79% |

- **The speedster has no niche.** White Horse has the fastest dash and run in the roster, ahead of Fox. Horse's dash also beats Fox's. It also survives a Cat forward smash to 82% (Fox: 69%) and hits much harder.
- **The heaviest fighters out-run the all-rounder.** Bear and Bull, the two heaviest, both run faster than Cat.
- **Heavies get the better air dodge.** All seven Bear-moveset heavies copy Bear's air dodge: intangible frames 4–32, 46 frames total. That's strictly better than the lighter fighters' 3–29 / 52. The heaviest characters escape juggles and edge-guards most easily.

**Fix**
- Bring every heavy's dash and run below the middleweight band.
- Make Fox (or whichever fighter is the speedster) clearly the fastest.
- Give heavies a worse air dodge, via the S1 archetypes.
- Re-run the S2 sweep afterward.

**Done when** every fighter is inside its archetype bands, and the S2 ordering rules pass.

### S4. Shared up tilt / up smash miss most of the roster

**Files:** `fighters/roster/bear/bear_moveset.tres` (lines 243, 286), `fighters/roster/cat/cat_moveset.tres` (lines 266, 319)

**Problem:** the shared hitboxes are placed for one body size, but used by fighters of many sizes.

**Bear moveset** (placed for Bear's 20-unit height)
- Up smash, offset `(2, 21)`, radius 7:
  - when used by Bull, Cow, Donkey, Horse, Stag or White Horse, it misses every fighter in the roster at resting distance;
  - when used by Bear, it misses everyone except Bear and Bull.
- Up tilt, offset `(3, 19)`, radius 6.5: misses everything below about 19 units tall, including Cat, Fox, Shiba, Husky, Wolf, Deer and Cow.
- Result: 7 characters have no grounded anti-air against standing targets.

**Cat moveset**
- Up tilt `(2, 14)` r5 and up smash `(2, 14)` r5.5 miss standing Fox, Shiba Inu, Husky and Wolf. Their hurtbox capsules reach only 10–11 units high.
- They miss in all 28 attacker/target pairs. The small dogs are immune to half of the shared grounded moveset.

**Fix**
- Until each animal has its own moveset, pick one of:
  - scale hitbox offsets by the attacker's height;
  - scale them by the shorter of the two fighters' heights;
  - give each archetype its own moveset copy.
- Lower or extend the up moves so they cover short standing targets, unless they're intentionally anti-air only. If they are, flag them.
- The S2 move-reach test is what keeps this bug class from coming back.

**Done when** the S2 move-reach test passes for all 14 fighters.

### S5. Explicit jump airtime

**Files:** `fighters/fighter_stats.gd`, `fighters/fighter.gd` (`apply_gravity`), `docs/fighter-stats.md`

**Problem:** full-hop airtime falls out of the gravity and jump-velocity stats, so floaty versus fast-faller isn't a deliberate number. Ultimate's Mario is 56 frames.

**Measured full-hop airtime (frames)**

| Fighter                | Airtime |
|------------------------|---------|
| Fox                    | 39      |
| Wolf                   | 42      |
| Stag                   | 47      |
| Bull                   | 49      |
| Horse, White Horse     | 50      |
| Bear, Donkey           | 51      |
| Husky, Shiba Inu       | 56      |
| Cat                    | 61      |
| Alpaca, Cow            | 63      |
| Deer                   | 79      |

The "floaty" Alpaca ties the super-heavy Cow and is only 2 frames floatier than Cat.

**Fix (pick one)**
- **Option A:** author each jump as a (height, airtime) pair and solve gravity and initial velocity from it.
- **Option B:** add a rise/fall gravity multiplier, so the peak height and the descent can be tuned separately.

Either way, add airtime to the S2 indices.

**Done when** each archetype has a target full-hop airtime and a test asserts that every character is within tolerance of it.

### S6. Crouch doesn't shrink small fighters' hurtboxes

**Files:** `fighters/fighter.gd` (`get_hurt_segment`, line 671)

**Problem**
- `get_hurt_segment` clamps the capsule's top to at least the radius.
- For the 10–11-unit fighters (Shiba, Fox, Husky, Wolf), the crouched hurtbox is therefore identical to the standing one. For example, Shiba (10 × 5) has top = 5 standing and `max(6 - 5, 5) = 5` crouched.
- Cat's crouch, by contrast, drops its hurtbox from 15 to 9.
- Crouch-ducking does nothing for the smallest fighters, so hurtbox size behaves inconsistently across archetypes.

**Fix**
- Decide whether crouch should shrink a fighter to a sphere, or lower its radius as well as its height.
- Apply that rule consistently.
- Include crouched target size in the S2 target-size index.

**Done when** every fighter's crouched hurtbox is measurably smaller than its standing one, and a test checks it.

### S7. Fox walk speed outside documented Ultimate range

**Files:** `fighters/roster/fox/fox.tres`, `docs/fighter-stats.md` (line 18)

**Problem:** Fox's `walk_speed` is 1.6, above Ultimate's range of 0.62–1.575. `docs/fighter-stats.md` claims every animal stays inside the range.

**Fix:** clamp it to 1.575 or below, or document the exception.

**Done when** an S2 range test checks every stat against the ranges in `docs/fighter-stats.md`.

---

## Notes

- After any change here, run the tests and the smoke run (commands are in `CLAUDE.md`).
