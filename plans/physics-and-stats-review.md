# Physics & Fighter Stats Review — Recommendations

Status: **proposed** · Reviewed: 2026-10-16 at commit `74a1e8f` · Scope: `combat/`, `fighters/`, `input/`

A code review of the physics and fighter-stats systems. It covers two things:

1. Making it easy to keep a roster of dozens of characters balanced.
2. Improving game feel: responsiveness, tight controls, and hits that feel tactile.

The numbers labelled **Measured** came from headless probe scripts run against the current code. All 82 existing tests passed at review time.

## How to use this document

- Each item has an ID (`P1`, `S2`, …), the files it touches, the problem, a recommended fix, and the result to check for once it's done ("Done when").
- Line numbers are as of `74a1e8f` and will drift, so search by function name.
- Follow the rules in `CLAUDE.md`:
  - Smash Ultimate units only.
  - New constants and formulas go in `SmashFormulas`, with a source comment.
  - Record what was ported or approximated in `docs/physics.md`.
  - Run the test suite after every gameplay change.
- When an item is done, update its status in the [Priority order](#priority-order) table. Add a regression test where the "Done when" line describes something measurable.

## Priority order

| #  | ID  | Item                                                  | Effort | Impact                 | Status |
|----|-----|-------------------------------------------------------|--------|------------------------|--------|
| 1  | P1  | Grounded hitstun slide ignores traction               | S      | High (feel, correctness) | todo |
| 2  | P2  | Low-angle tumble landings bounce and refund resources | S      | High (feel, correctness) | todo |
| 3  | P3  | Ultimate balloon knockback + 70–110° fall speed       | M      | High (feel)              | todo |
| 4  | P4  | Hit feedback tied to hitlag (flash, shake, camera)    | M      | High (feel)              | todo |
| 5  | P5  | Double stick deadzone                                 | S      | High (controls)          | todo |
| 6  | S1  | Archetype base resources; freeze `FighterStats` defaults | M   | High (roster scaling)    | todo |
| 7  | S2  | Balance harness tests (KO % bands, move reach)        | M      | High (roster scaling)    | todo |
| 8  | S3  | Bear stats contradict heavyweight archetype           | S      | Medium (balance)         | todo |
| 9  | S4  | Bear up tilt / up smash miss short targets            | S      | Medium (balance)         | todo |
| 10 | P6  | Shield hitlag clamp inflates low-multiplier hitboxes  | S      | Medium (correctness)     | todo |
| 11 | P7  | Attacker shield pushback + parry                      | M      | Medium (balance)         | todo |
| 12 | S5  | Explicit jump airtime (floaty vs fast-faller)         | M      | Medium (roster scaling)  | todo |
| 13 | P8  | Polish: turn rate, edge stops, buffer during hitlag, shieldstun check | S each | Low–Medium | todo |

P1, P2 and P5 are small, contained fixes with an outsized effect on feel. Do them first. S1 and S2 should land **before** more characters are added. Retrofitting archetypes onto many `.tres` files is much harder than starting with them.

---

## Part 1 — Physics & game feel

### P1. Grounded hitstun slide ignores traction

**Files:** `fighters/states/hitstun_state.gd` (`update`, ~line 30), `fighters/fighter.gd` (`apply_traction`, `_move`)

**Problem**
- On the ground, `HitstunState.update()` calls `f.apply_traction()`.
- Traction only slows `velocity_self`, which `_launch` sets to zero.
- `velocity_knockback` therefore slides along the floor, slowed only by the air launch decay (`LAUNCH_DECAY`, 0.051).
- Hitstun can end while knockback is still non-zero. The leftover knockback keeps moving the fighter after it becomes actionable, on top of its own walk or dash input.

**Measured:** a 53-knockback, 0° Cat forward tilt on Bear at 40% slid Bear **25.6 units**, about 4× its hurtbox radius. When Bear returned to Idle it still had `velocity_knockback.x = 0.57` and drifted another ~3.5 units over ~15 frames.

**Why it matters:** hits feel slippery instead of weighty. Traction doesn't affect hit slides, so low- and high-traction characters slide the same distance. In Smash, low-traction characters slide further.

**Fix**
- While grounded, decay `velocity_knockback.x` by `traction + LAUNCH_DECAY` per frame, in `HitstunState.update()` or `Fighter._move`.
- Zero the grounded knockback when hitstun ends (in `to_neutral()` or on hitstun exit).
- Add the source and any approximation to `docs/physics.md`.

**Done when**
- The same probe hit slides Bear a distance consistent with its traction.
- `velocity_knockback == Vector2.ZERO` on the first actionable frame.
- A test asserts that a low-traction fighter slides further than a high-traction one under the same hit.

### P2. Low-angle tumble landings bounce and refund resources

**Files:** `fighters/fighter.gd` (`land_from_tumble`, ~line 493)

**Problem**
- The bounce condition is `velocity_knockback.y < 0.0 and velocity_knockback.length() >= GROUND_BOUNCE_SPEED`. It tests total speed, not downward speed, so a grazing landing bounces.
- By the time this runs, `_land` has already reset `jumps_used` and `air_dodge_used`. A bounced victim gets its double jump and air dodge back for free.
- On the second contact `vk.y > 0`, so the fighter goes straight to knockdown and gets no correct tech chance.

**Measured:** a tumbling Cat landing with `vk = (2.35, -0.39)` (length 2.38, very little downward speed) bounces back to `vk.y = +0.30`.

**Fix**
- Change the condition to `-velocity_knockback.y >= GROUND_BOUNCE_SPEED`.
- Don't refund jumps or air dodge on a bounce. Either restore them after the bounce check, or snapshot them before `_land` and restore them on a bounce.

**Done when** tests cover all three cases:
- A shallow landing goes to knockdown or tech, not a bounce.
- A steep landing still bounces.
- `jumps_used` and `air_dodge_used` don't change across a bounce.

### P3. Port Ultimate balloon knockback and the 70–110° fall speed

**Files:** `combat/smash_formulas.gd` (`launch_velocity`, `decay_launch`, ~line 168), `docs/physics.md`

**Problem:** launches use plain Smash 4 speed and decay. **Measured:** a KO-strength hit (knockback ~190, hitstun 75) leaves at 5.7 u/f and takes over 100 frames to decay. Strong hits read as floaty.

**Fix**
- Port Ultimate's launch speed-up for high-hitstun launches ("balloon knockback"). For launches above the hitstun threshold, scale initial launch speed and decay together so that:
  - total travel distance stays the same;
  - hitstun stays the same;
  - the distance is covered in far fewer frames.

  This is most of why Ultimate's kill hits feel snappy.
- Add the 1.8 fall speed for 70–110° launches. It's already listed as missing in `docs/physics.md`.
- Put the constants in `SmashFormulas` with source comments, and update the ported/approximated list in `docs/physics.md`.

**Done when**
- A test compares launch distance with balloon knockback on and off. It confirms the total distance matches within tolerance and the launch reaches its peak in fewer frames.
- Existing KO % probes (S2) don't shift beyond tolerance.

### P4. Hit feedback tied to hitlag (flash, shake, camera)

**Files:** `fighters/fighter_model.gd` (`flash`, ~line 38; `sync`), `camera/` (FightCamera), `combat/` (`HitInfo` already carries hitlag and knockback)

**Problem**
- `flash()` sets a fixed 4 frames. Hitlag lasts 10–30 frames, so the flash ends early in the freeze.
- The victim's shake is a random jitter of constant magnitude (~0.06 m), and physics interpolation smooths it further.
- The attacker freezes but doesn't shake.
- The camera doesn't react at all.
- As a result, weak and strong hits look nearly the same.

**Fix**
1. **Flash:** keep the flash on for the whole hitlag. Pass `info.hitlag` into `flash()`.
2. **Victim shake:** shake along the launch angle with alternating sign, sized by knockback and decaying over the hitlag. It should be a deliberate offset, not random noise. Make sure interpolation doesn't smooth it away; apply the offset to the visual pivot, not the physics body.
3. **Attacker shake:** a smaller version of the same shake.
4. **Camera:** shake scaled by knockback, plus an optional brief zoom on strong or KO hits. The values come from `HitInfo`.
5. Keep everything presentational. No gameplay state may depend on it, so tests and determinism are unaffected.

**Done when**
- In a `--write-movie` capture, the flash lasts the whole hitlag.
- A fully charged smash looks clearly different from a jab.
- The camera visibly responds to hits above a knockback threshold.

### P5. Double stick deadzone

**Files:** `input/player_controller.gd` (`poll`, ~line 20), `input/` (`InputTracker` thresholds)

**Problem**
- `Input.get_vector(...)` uses the actions' 0.2 deadzone and rescales the result.
- `MOVE_DEADZONE` (0.2), `FLICK_FROM` (0.3) and `FLICK_TO` (0.8) are then applied to that rescaled value.
- Together, these push the effective thresholds up:
  - walking needs ~0.36 physical deflection;
  - a dash or smash flick needs ~0.84 physical, starting below ~0.44, within 3 frames.
- Partial flicks on a gamepad, and especially on the touch stick, come out as walks or tilts.

**Fix**
- Read raw axes by passing `deadzone = 0` to `get_vector`, or by reading the axes directly.
- Keep **one** set of Smash-calibrated thresholds in `InputTracker`.
- Check that the touch stick produces values on the same scale as a gamepad.

**Done when** an `InputTracker` test drives raw stick values and confirms:
- walking starts at the intended physical deflection;
- a flick from neutral to ~0.8 within the window registers as a dash or smash.

### P6. Shield hitlag clamp inflates low-multiplier hitboxes

**Files:** `combat/smash_formulas.gd` (`hitlag_frames`, ~line 131)

**Problem:** `multiplier = maxf(multiplier, 1.0) * HITLAG_SHIELD`. A hitbox authored with `hitlag_multiplier = 0.3` gets 0.3× hitlag on hit but 0.67× on shield, more than twice as much. Multi-hit moves become unexpectedly sticky on shield.

**Fix:** use `multiplier * HITLAG_SHIELD`. If the clamp is intentional, document it with a source comment.

**Done when** a unit test checks that shield hitlag is never longer than hit hitlag for the same hitbox.

### P7. Attacker shield pushback and parry

**Files:** `fighters/fighter.gd` (`receive_shield_hit`, ~line 592), `fighters/states/shield_state.gd`, `combat/smash_formulas.gd`

**Problem**
- Only the defender gets pushback (`ShieldState.take_hit`).
- A grounded attacker stays flush against the shield, so moves that should be unsafe can still be spaced from inside the shield.
- This skews shield-pressure balance toward slow, heavy moves.
- Perfect shield (parry) is missing.

**Fix**
- For grounded hits, split pushback between attacker and defender, as Ultimate does.
- Add a parry window on shield release.
- Put both in `SmashFormulas` with source comments, and update `docs/physics.md`.

**Done when** tests confirm:
- The attacker is moved away on a grounded shield hit.
- A shield released within the parry window turns the hit into a parry.

### P8. Smaller polish items

- **Turnarounds:** `FighterModel.sync` lerps yaw at `TURN_RATE`. Raise it to ≥ 0.8, or snap on turnaround, so turns look as instant as they play.
- **Edge stops:** when a fighter is stopped at a ledge, place it exactly at the edge. Today it's rolled back a whole frame (`global_position = previous`), which looks like a stutter.
- **Buffer during hitlag:** consider freezing input-buffer aging during hitlag. Presses made during a long freeze would then survive, which matters once hitlag cancels exist.
- **Shieldstun:** check `shieldstun_frames` against Ultimate's separate aerial and grounded multipliers.

---

## Part 2 — Fighter stats & roster balance

### S1. Archetype base resources; freeze `FighterStats` defaults

**Files:** `fighters/stats/fighter_stats.gd` (~line 12), `fighters/roster/*/*.tres`, `docs/fighter-stats.md`

**Problem**
- Every `FighterStats` default is Mario's value, and `.tres` files store only differences.
- Cat's stats sub-resource is empty, so tuning Cat means editing the defaults.
- Editing a default silently changes every field Bear inherits, including:
  - `air_acceleration_base`
  - crouch ratio
  - ledge frames
  - fast-fall multiplier
  - jumpsquat
- It will also change every future character. Nothing flags these changes.

**Fix**
1. Treat the `FighterStats` defaults as **neutral and frozen**. Document that changing them is a roster-wide balance change.
2. Add archetype base resources:
   - `feather`, `light`, `middle`, `heavy`, `superheavy`;
   - plus `floaty` and `fastfaller` variants (or modifiers).
3. Each character references an archetype, through a `base` field or by duplicating it, and overrides only what makes it distinct.
4. Give Cat its own explicit stats, even if they match the middleweight archetype today.
5. **Derive what can be derived**, so fewer hand-tuned values can drift:
   - shield radius from the hurtbox (about `height × 0.5 + margin`);
   - ledge intangibility universal;
   - fast-fall multiplier fixed at 1.6 for everyone.

**Done when**
- Every character names an archetype.
- Changing a default and re-running S2 shows exactly which characters moved.

### S2. Balance harness tests

**Files:** `tests/` (new suites)

Turn the raw stats into a few **derived indices** and give each archetype an allowed band for each:

| Index          | Inputs                                                         |
|----------------|----------------------------------------------------------------|
| Survivability  | weight, fall speed, gravity (drive horizontal & vertical KO %) |
| Mobility       | initial dash, run, air speed, air acceleration                 |
| Recovery       | jump count × air-jump height + up-special distance             |
| Target size    | height × hurtbox radius                                        |
| Speed          | frame of the fastest out-of-shield option; jab frame           |

**Tests to add**
1. **KO % sweep:**
   - Hit every character with one reference `HitboxData`, such as a "Mario forward smash".
   - Hit from stage center, uncharged, testing the side and top blast zones.
   - Assert the KO % falls inside the character's archetype band.
   - Target: under ~25% spread between the lightest and heaviest characters for the reference move.
2. **Move reach:**
   - Fire every grounded move at the smallest and largest roster member, at resting spacing (`_separate_fighters` distance).
   - Fail unless the move connects or is explicitly flagged `anti_air_only`.
3. **Index bands:** compute each character's indices and assert they fall inside the archetype's band. Heavier characters must pay for weight with one or more of:
   - a bigger hurtbox;
   - higher fall speed or gravity;
   - slower frame data;
   - a worse air dodge.

   They must never pay with more mobility.

**Baseline (Measured, no DI, uncharged forward smash from center)**

| Attacker → Target | KO % |
|-------------------|------|
| Cat → Cat         | 80   |
| Cat → Bear        | 100  |
| Bear → Cat        | 55   |
| Bear → Bear       | 65   |

Expect these to rise once DI is in play. The review used two scratch probes, a KO % sweep and a move-reach sweep; both should be rebuilt as permanent tests here.

**Done when** both suites run in `tests/run_tests.gd` and fail on an out-of-band character.

### S3. Bear's stats contradict the heavyweight archetype

**Files:** `fighters/roster/bear/bear.tres` (~line 326)

**Problem**
- Bear out-runs the all-rounder on the ground:

  | Stat         | Bear  | Cat   |
  |--------------|-------|-------|
  | Initial dash | 2.1   | 1.936 |
  | Run          | 1.85  | 1.76  |

- Bear's air dodge is strictly better:

  | Air dodge         | Bear | Cat  |
  |-------------------|------|------|
  | Intangible frames | 4–32 (29) | 3–29 (27) |
  | Total frames      | 46   | 52   |

- Bear's description says "slow". Combined with its KO power (Bear → Cat 55% vs Cat → Bear 100%), the heaviest, hardest-hitting character also has the best mobility and defensive escape.

**Fix:** cut Bear's dash and run below Cat's, and make its air dodge worse (fewer intangible frames, more total frames). Alternatively, give Cat a clear mobility edge. Re-run the S2 KO sweep afterward.

**Done when** Bear falls within the heavy band and Cat within the middleweight band on every S2 index.

### S4. Bear's up tilt and up smash miss short targets

**Files:** `fighters/roster/bear/bear.tres` (~line 246)

**Problem:** the up smash hitbox (offset `(2, 21)`, radius 7) and up tilt hitbox (offset `(3, 19)`, radius 6.5) are placed for Bear's 20-unit height.

**Measured**

| Move     | Misses a standing Cat at gaps of |
|----------|----------------------------------|
| Up smash | 9.0, 10.2, 12.0                  |
| Up tilt  | 10.2 and beyond                  |

10.2 is the resting spacing that `_separate_fighters` leaves between them. Cat's up moves hit Bear at all of those gaps.

**Fix:** lower or extend the hitboxes so they cover a short standing target near Bear, or flag the moves as anti-air only if that's the design intent. More generally, this is the bug class the S2 move-reach test is meant to catch across the whole roster.

**Done when** the S2 move-reach test passes for Bear.

### S5. Explicit jump airtime

**Files:** `fighters/stats/fighter_stats.gd`, `fighters/fighter.gd` (`apply_gravity`), `docs/fighter-stats.md`

**Problem:** full-hop airtime falls out of the gravity and jump-velocity stats. It's currently **61 frames**, against Ultimate's 56. Floaty versus fast-faller isn't a deliberate number.

**Fix (pick one)**
- **Option A:** author each jump as a (height, airtime) pair and solve gravity and initial velocity from it.
- **Option B:** add a rise/fall gravity multiplier, so the peak height and the descent can be tuned separately.

Either way, add airtime to the S2 indices.

**Done when** each archetype has a target full-hop airtime and a test asserts that every character is within tolerance of it.

---

## Notes

- The uncommitted `project.godot` change at review time only removed values that equal Godot's defaults: 60 Hz physics ticks, `emulate_mouse_from_touch`, and the web `gl_compatibility` renderer. It doesn't change behavior.
- After any change here, run the tests and the smoke run (commands are in `CLAUDE.md`).
