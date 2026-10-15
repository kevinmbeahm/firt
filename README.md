# Fold

A 2-player local co-op **3D** puzzle-platformer in **Godot 4** (tested on 4.3), in the wobbly physics-playground spirit of *Human Fall Flat*. The twist: giant sheets of paper (~10x the size of a player) that you grab, fold and slide around to build your own platforms.

## Run
Open this folder in Godot 4.3+ and press **F5** (main scene: `scenes/main.tscn`). Click the window to capture the mouse for camera control.

## Controls
| | Player 1 | Player 2 |
|---|---|---|
| Move | WASD | Arrow keys |
| Jump | Space | `/` |
| Grab paper | hold **F** or **LMB** near a glowing corner/edge | hold **.** |
| ...while holding: raise / lower hands | **Space** / **C** (or mouse wheel) | **/** / **;** |
| Sheet handling (hold) | **R** or **RMB**: move = slide, Space = flip over, F/LMB = turn 45 deg | **,** (same combos) |

Gamepads (device 0 = P1, device 1 = P2): left stick move, A jump/raise, B lower, X grab, RB sheet handling.
Shared camera: mouse / right stick / Q-E to orbit. **Z** undo last fold, **Backspace** restart, **Esc** release mouse.

## How folding works
The paper is thin (3 cm) and folds like real paper, rigidly, at any angle:
- Grab a corner or edge midpoint. **The grabbed point follows your hands**: walk to carry it, raise/lower your hands to lift it. The paper creases wherever it has to bend for that point to reach your hands (an orange line shows it), and the flap swings live.
- Keep your hands low and carry a corner over to fold flat; lift them to leave the flap standing at an angle (ramps, walls, wings). Angles near 90 and 180 deg snap, and so do corners/creases you carry a point onto, so corner-to-corner and corner-to-crease folds are easy.
- Release to make the crease permanent (Z undoes it).
- Only the paper **connected** to what you grabbed moves. Fold a stack in half and you can still fold just the top flap: that's how you do a paper plane's wings. A fold that would need to tear paper that's joined elsewhere is refused (the crease line turns red and the HUD says why).
- Re-folding along an existing crease reuses it exactly, so you can open wings back out or unfold.
- Hold *sheet handling* to slide the whole sheet (riders are carried), flip it over (to fold the other side) or turn it.

## Level 1
Get both players to the flag on the 2.6 m ledge across the gap, too high to jump. Fold part of the big sheet up into a **ramp** and slide it against the ledge. (Hint: whatever you stand on when you fold the far strip up comes up too, so fold it over solid ground.)
The smaller sheet on the island is a free-folding sandbox: try a paper plane.

## Tests
- `godot --headless -s tests/fold_model.gd` folds a paper plane step by step in the origami model and checks layer-selective folds, partial angles, crease reuse and tear refusal.
- `godot --headless -s tests/solve_level.gd` has bots solve level 1 with real input actions (slide sheet, fold a ramp, ride, climb) and asserts the win condition.

## Code layout
- `scripts/paper_geometry.gd` - 2D polygon clipping / overlap helpers
- `scripts/paper_model.gd` - rigid-origami model: facets in paper space + 3D transforms, fold planning (crease from grab/target, connectivity, tear check, layer order), stacking offsets, grab handles
- `scripts/paper_sheet.gd` - a sheet in the world (`AnimatableBody3D`): live fold preview, undo, flip/turn, thin-slab meshes and collision
- `scripts/player.gd` - `CharacterBody3D` bean: movement, step-up, grab/fold input, procedural wobble and arm reaching
- `scripts/level.gd` - terrain, lighting, sheets, shared orbit camera, input map, sheet sliding, win condition

## Known limits / next steps
- Each fold is a single straight crease. That covers paper planes, boats, hats, ramps and walls, but a crane also needs **squash, reverse and petal folds** (several creases moving at once); those are the next mechanic to add.
- Paper is rigid between creases (no bending/curling) and folds don't collide with other layers or the world.
- Flip turns a sheet 180 deg; there's no free 3D rotation yet (e.g. to stand a finished plane upright, or throw it).
- Local co-op only, shared camera.
