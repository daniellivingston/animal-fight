class_name PhysicsLayers
## Bitmasks for the 3D physics layers named in
## Project Settings > Layer Names > 3D Physics. Keep the two in sync.

## Solid stage geometry: floors, walls and ceilings.
const WORLD := 1 << 0
## Soft platforms that fighters can jump up through and drop down through.
const PLATFORM := 1 << 1
## Fighters. They don't collide with each other (see [method Match.separate_fighters]).
const FIGHTER := 1 << 2
