# Animal Fight

A Smash Bros-style platform fighter with animals, built with **Godot 4.7** (GDScript). It targets desktop, mobile and the web, and touch controls are first-class.

> Current state: the foundation. One stage (Meadow: a main platform with two soft platforms above it), 14 selectable characters, Smash Ultimate physics and combat, training tools, and desktop, gamepad and touch controls.
> Cat and Bear are primitive placeholders with their own movesets. The other 12 (Fox, Wolf, Husky, Shiba Inu, Deer, Stag, Alpaca, Donkey, Horse, White Horse, Cow, Bull) are rigged, animated low-poly models with their own stats; for now they share Cat's or Bear's moveset (see [docs/fighter-stats.md](docs/fighter-stats.md#the-animal-roster)).

## Running

- **Editor:** open the folder in Godot 4.7 and press <kbd>F5</kbd>.
- **CLI:** `/Applications/Godot.app/Contents/MacOS/Godot --path .`
- **Touch controls on desktop:** `Godot --path . -- --touch` (the mouse acts as one finger).
- **Tests:** `Godot --headless --path . --fixed-fps 60 --script res://tests/run_tests.gd` (about 2 s; exits with 1 on failure).
- **Smoke check:** `Godot --headless --path . --quit-after 120` should print only the version banner.

## Controls

| Action  | Keyboard P1 | Keyboard P2 | Gamepad (P1 = pad 0, P2 = pad 1) | Touch (P1) |
|---------|-------------|-------------|----------------------------------|------------|
| Move    | WASD        | Arrows      | Left stick / d-pad               | Floating stick (left side) |
| Attack  | J           | ,           | A (bottom)                       | Attack |
| Special | K           | .           | B (right)                        | Special |
| Jump    | Space       | Enter       | X / Y                            | Jump, or flick up |
| Shield / dodge | L    | /           | LB / RB / triggers               | Shield |
| Smash attack | I (+ direction) | ; | Right stick (C-stick)            | Flick + Attack |
| Walk / tilt | Left Shift | Right Shift | (analog)                      | (analog) |

Global keys: Esc / Start pauses, F1 toggles hitboxes, F2 toggles the training overlay, F5 / Back resets.

**Smash-style inputs.** Flick the stick to dash; flick and press attack together for a smash attack, or tilt gently for a tilt attack. Hold attack to charge a smash.
Tap down in the air to fast fall. Flick down on a platform to drop through. Shield and flick sideways to roll, or flick down to spot dodge. Shield in the air to air dodge, toward a direction for a directional air dodge.
Press shield just before landing while tumbling to tech.

**Keyboards.** Every key press goes straight to full tilt, so a direction plus attack would always be a flick. Hold **Shift** to walk and tilt, and use **I** for smash attacks.
Tap jump (jumping by flicking up) is off on keyboards by default and on for gamepad and touch; the pause menu can change it.

**Touch layout.** A floating analog stick on the left appears under your thumb and follows it, so a quick swipe is a flick (dash, smash attack, tap jump).
Four buttons sit on the right: Attack, Special, Jump, Shield. Pause is top-right. Multi-touch works, so you can move and press buttons at the same time.
Phones in portrait get a "turn your device" hint.

## Training tools

The pause menu (Esc, Start, or the touch pause button) has the playtest settings:

- Pick each player's character.
- Make player 2 a dummy (stand / shield / jump) or a second local player.
- Set the dummy's DI (none / survival / combo) and the tap jump mode.
- Toggle hitboxes and the training overlay.
- A side-by-side **stats comparison** of the two fighters.

With hitboxes on (default), active hitboxes show as red spheres and hurtboxes as faint capsules (blue while intangible).
The training overlay (F2) shows each fighter's state, frame, velocities, jumps and shield, and the numbers behind the last hit: damage, staleness, knockback, angle before and after DI, launch speed, hitstun, hitlag, and tumble.

## Project layout

Folders are grouped by feature. Each scene sits next to its script.

```
camera/          FightCamera: frames every fighter, clamped to the stage's camera bounds
combat/          SmashFormulas (all ported constants and formulas), HitboxData, MoveData,
                 HitResolver (hit detection), StaleMoveQueue, HitInfo
core/            Units (Smash units <-> meters), PhysicsLayers, DebugSettings
docs/            physics.md (what's ported and how), fighter-stats.md (every stat, ranges)
fighters/        Fighter (CharacterBody3D), FighterStats, Moveset, FighterData,
                 FighterModel (placeholder posing), AnimatedFighterModel (rigged glTF models)
  states/        One FighterState per Smash action (idle, dash, jumpsquat, hitstun, ledge, ...)
  roster/        One folder per character: <name>.tres (stats), <name>_model.tscn and, for
                 animals, <name>.gltf. cat/ and bear/ also hold the shared <name>_moveset.tres.
    _licenses/   Licenses of third-party models
input/           GameInput autoload (device tracking), InputTracker (buffer, flicks),
                 controllers (PlayerController, DummyController), InputActions
  touch/         TouchStick, VirtualButton, touch controls scene
match/           Match: owns the simulation loop, fighters, camera and UI
stages/          Stage base, SoftPlatform, StageLedge
  meadow/        The first stage
tests/           Headless test suite (run_tests.gd)
ui/              HUD (damage meters), training overlay, pause menu, theme, SafeArea
```

## Architecture

### Simulation loop

`Match._physics_process` runs once per Smash frame (physics is fixed at 60 Hz):

1. `Fighter.tick()` for each fighter: poll the controller → `InputTracker` → hitlag or state update → move.
2. `HitResolver.resolve()` detects every hit for the frame, then applies them all, so simultaneous hits trade.
3. Overlapping grounded fighters are pushed apart.
4. Blast-zone check, then `Fighter.sync_visuals()`.

Fighters never run their own `_physics_process`. The order is fixed and deterministic, which is also what rollback netcode would need.

### Key principles

- **Smash units everywhere.** Stats, moves and formulas use Ultimate's units and frame timing, so community frame data copies over directly. `Units` converts at the boundary (10 units = 1 m).
- **Data-driven characters.** A character is a `FighterData` resource with a model scene, `FighterStats` and a `Moveset` of `MoveData` / `HitboxData`. No character-specific code; add one in the inspector.
- **States as small classes.** `FighterState` subclasses (`fighters/states/`) hold behaviour. `Fighter` holds physical state and shared helpers (`try_jump`, `try_ground_attack`, `apply_air_drift`, ...). States can't drift apart in how they handle a jump or an aerial.
- **Controllers drive fighters.** `FighterController.poll()` returns an `InputFrame`. `PlayerController` reads the Input Map (keyboard, gamepad and touch all press the same `p1_*` actions); `DummyController` is the training dummy. A CPU or a network peer would be another controller.
- **Visuals are separate from gameplay.** `FighterModel.sync()` poses the model from the fighter's state each frame: facing, tumble spin, hit flash, intangibility tint, and squash/lean for the placeholder models.
  `AnimatedFighterModel` instead picks an animation per state and steps the glTF's `AnimationPlayer` manually, one simulation frame at a time, so animations freeze in hitlag and attacks stretch to the move's length.

### Rendering & physics

- **Renderer:** Forward+ on desktop, Mobile on phones, Compatibility (WebGL 2) on the web.
- **Physics:** Jolt, fixed 60 ticks per second, physics interpolation on. Fighters use `CharacterBody3D` on the XY plane.
- **Physics layers:** 1 `world` (solid ground), 2 `platform` (soft platforms), 3 `fighter`. Fighters don't collide with each other; they're pushed apart instead. Mirrored in `core/physics_layers.gd`.

## Web export

```sh
mkdir -p build/web
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/index.html
```

The Web preset uses the **single-threaded** build (`variant/thread_support=false`), so it needs no cross-origin isolation headers and runs on any static host (itch.io, GitHub Pages, Netlify), including iOS Safari.
The preset also adds CSS that stops the browser from scrolling, zooming or selecting text on touch, and enables a fullscreen, landscape PWA for "Add to Home Screen".

Test locally with `python3 -m http.server -d build/web`. The PWA service worker caches aggressively: after re-exporting, hard-reload or clear the site data. Another Godot project served earlier on the same port can also leave a stale worker that breaks loading.

Other presets (Windows, macOS, Linux, Android, iOS) are set up with bundle ids. Android needs the SDK and a keystore configured in the editor; iOS needs a team id.

## Conventions

- Static typing everywhere; tabs for indentation; `##` doc comments on public API.
- The official GDScript style guide: `snake_case` files, `PascalCase` class names, `_private` members.
- Use `%UniqueName` or exported references rather than long node paths.
- Stage geometry lives on the XY plane. Fighter facing is `1` (right) or `-1` (left), and angles are relative to facing.
- Commit `*.uid` files; never commit `.godot/` or `build/`.

## Likely next steps

- Grabs and throws, plus neutral, side and down specials.
- Ultimate's balloon knockback and parry (see [docs/physics.md](docs/physics.md#not-ported-yet)).
- A character select screen and match rules (stocks, timer, results).
- Per-animal movesets for the 12 animated animals, and hurtboxes that fit four-legged bodies (today's vertical capsule covers the torso; heads and tails stick out).
- A CPU controller.
- Rollback netcode: the simulation is already frame-stepped and ordered. It would need state snapshots and fixed-point or verified-deterministic math.

## Credits

The animated animals are from [Ultimate Animated Animals](https://quaternius.com/packs/ultimateanimatedanimals.html) by Quaternius, released under CC0 (license in `fighters/roster/_licenses/`).
