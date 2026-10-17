# Animal Fight — notes for Claude

Godot 4.7.2 + GDScript, Smash Bros-style platform fighter, desktop + mobile + web (touch is first-class).
Architecture and layout are in README.md; ported mechanics in docs/physics.md; stats in docs/fighter-stats.md.

## Commands
- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`
- Re-import / refresh class cache after adding `class_name` scripts: `Godot --headless --path . --import`
- Tests (run after any gameplay change): `Godot --headless --path . --fixed-fps 60 --script res://tests/run_tests.gd`
- Smoke run (should print only the banner): `Godot --headless --path . --quit-after 120`
- Desktop run with touch controls: `Godot --path . -- --touch`
- Web export: `Godot --headless --path . --export-release "Web" build/web/index.html`
- Visual check (opens a window, writes PNG frames): `Godot --path . --write-movie <dir>/frame.png --quit-after 120`
  (scripts run via `--script` don't load autoloads, so use a temporary scene for scripted demos).

## Rules of thumb
- All gameplay values are Smash Ultimate units (units, units/frame, frames). Convert only at the
  Godot boundary through `Units`. Don't put meters or seconds in stats or move data.
- Fighters are ticked by `Match` (or the test world), never by their own `_physics_process`.
  New per-frame gameplay goes into `Fighter.tick()`, a state's `update()` or the match loop, in order.
- Gameplay reads input only through `Fighter.input` (`InputTracker`); controllers produce `InputFrame`s.
  Never poll `Input` from fighters or states.
- y is up in all gameplay math. `Vector2.UP` is `(0, -1)` in Godot, so write `Vector2(0, 1)`.
- New combat constants and formulas go in `SmashFormulas` with a source comment; record what's
  ported (or approximated) in docs/physics.md.
- `FighterStats` defaults are Mario's Ultimate stats, and .tres files store only differences:
  changing a default changes every character that relies on it.
- Models are visual only. `AnimatedFighterModel` steps its `AnimationPlayer` manually from `sync()` (one
  simulation frame per call), so never switch it back to idle/physics processing or read animation state in gameplay.
- Static typing everywhere; tabs; `##` doc comments on public API. Avoid naming enums after
  native classes (e.g. `Button`): GDScript rejects it.
- Commit `*.uid` files; `.godot/` and `build/` are ignored.
