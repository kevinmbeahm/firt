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
| ...while holding: cycle fold type (fold / inside reverse / outside reverse / collapse) | **Tab** | **'** |
| ...in collapse mode: next / previous way to collapse | **Space** / **C** | **/** / **;** |
| Sheet handling (hold) | **R** or **RMB**: move = slide, Space = flip over, F/LMB = turn 45 deg | **,** (same combos) |

Gamepads (device 0 = P1, device 1 = P2): left stick move, A jump/raise, B lower, X grab, Y fold type, RB sheet handling.
Shared camera: mouse / right stick / Q-E to orbit. **Z** undo last fold, **Backspace** restart, **Esc** release mouse, **F11** (or Alt+Enter) fullscreen. The view stretches to fill any window size.

## How folding works
The paper is thin (3 cm) and folds like real paper, rigidly, at any angle:
- Grab a corner or edge midpoint. **The grabbed point follows your hands**: walk to carry it, raise/lower your hands to lift it. The paper creases wherever it has to bend for that point to reach your hands (an orange line shows it), and the flap swings live.
- Keep your hands low and carry a corner over to fold flat; lift them to leave the flap standing at an angle (ramps, walls, wings). Angles near 90 and 180 deg snap, and so do corners/creases you carry a point onto, so corner-to-corner and corner-to-crease folds are easy.
- Release to make the crease permanent (Z undoes it).
- Only the paper **connected** to what you grabbed moves. Fold a stack in half and you can still fold just the top flap: that's how you do a paper plane's wings. A fold that would need to tear paper that's joined elsewhere is refused (the crease line turns red and the HUD says why).
- **Unfolding:** grab a folded flap and carry it back roughly where it came from (or lift it part-way): it swings about its existing crease, so you don't need to put the corner back exactly. A new crease near an old one also snaps onto the old one rather than leaving slivers.
- Paper is solid. A flap that runs into the ground or anything solid stops there and rests against it, the way real paper would; a near-flat fold that would have to go under a sheet lying on the floor goes over the top instead. Over the void you can fold a flap down to hang freely. A fold is only refused (red crease, reason in the HUD) when the flap can't move at all, or would end up passing through other paper. Paper lying on a flap holds it down: it can fold away from that paper but not up through it. Corners buried under a layer on top can't be grabbed; flip the sheet to reach the other side.
- The flap moves continuously with your hands: once it's over on one side of the paper, pushing your hands on through the paper just presses it flat there; it never jumps through to the other side. A flap part-way through a fold is drawn hinged to its own layer of the stack.
- **Reverse folds** (Tab / ' / Y while holding paper): on a folded edge (layers joined at a spine, e.g. a strip folded in half), the two sides of the tip swing about the same crease in opposite directions. An *inside reverse fold* tucks the tip between the layers (a crane's neck and tail); an *outside reverse fold* wraps it around them. They need a folded edge and are always flat.
- **Collapse (squash / petal folds)**: the fourth fold type. Precrease first (fold and unfold), then grab a point and collapse: every existing crease may fold or unfold together, as long as the result is flat-foldable (Kawasaki's theorem at every crease vertex) and nothing tears. That's how you make a square base from a precreased square, or a petal fold on a kite. When the creases allow several collapses (square base vs waterbomb, say), raise/lower your hands to step through them; the HUD shows "option i of n". The simplest one that brings the grabbed point closest to your hands comes first.
- **Layering**: every flat fold's stacking order comes from a layer solver (the taco/tortilla rules plus transitivity), so a fold that would need paper to pass through paper is refused rather than faked.
- Hold *sheet handling* to slide the whole sheet (riders are carried; if you're not on it you walk alongside), flip it over (to fold the other side) or turn it.

## Paper physics
Each sheet is a rigid body with real weight (mass from its area; centre of mass recomputed after every fold):
- It rests on whatever holds it up and slides with friction.
- Hang it too far over an edge and it tips and falls. Your weight counts: walking out onto an overhang can tip a sheet that was balanced.
- A sheet lost in the void comes back at its starting spot (with its folds).
- You can only slide a sheet that's resting on something (no steering it in mid-fall). Flips, turns and undos are refused when the paper would end up inside something solid.

## Level 1
Get both players to the flag on the 2.2 m ledge across a 7 m gap; too high to jump, too far to just slide the sheet across (it would tip into the void). Fold part of the big sheet up into a **ramp**, ride the sheet out until the ramp's tip reaches over the ledge so it's held up at both ends, and walk up.
(Hint: whatever you stand on when you fold the far strip up comes up too.)
The smaller sheet on the island is a free-folding sandbox: try a paper plane, or fold a strip in half and reverse-fold its tip.

## Tests
- `godot --headless -s tests/fold_model.gd` folds a paper plane step by step and checks layer-selective folds, partial angles, crease reuse, tear refusal, and inside/outside reverse folds.
- `godot --headless -s tests/fold_physics.gd` checks folds against the world and the rigid body: flat folds near the floor go over the top, flaps rest on the ground instead of passing through it, hanging flaps over the void, no paper through paper, buried corners, undo/turn needing room, no steering falling sheets, clean grab release, respawn orientation.
- `godot --headless -s tests/unfold_game.gd` folds a strip over with real inputs, then walks the flap back sloppily and checks it unfolds along the old crease.
- `godot --headless -s tests/paper_physics.gd` checks sheets rest, tip into the void when pushed over an edge, respawn, and tip under the players' weight.
- `godot --headless -s tests/solve_level.gd` has bots solve level 1 with real input actions (fold a ramp, ride the sheet out to the ledge, climb) and asserts the win condition.

- `godot --headless -s tests/crane.gd` is the **benchmark**: it folds a traditional paper crane from an 8 m square in 32 steps with the game's own operations (precreases, square-base collapse, kite folds, petal folds, leg narrowing, inside reverse folds for a long neck and tail and a bent head, wing folds). After every step it checks the whole sheet: no tears, no paper through paper, no paper lost, a valid stacking. Then it checks the crane's shape: neck and tail rise well above the spread wings on opposite sides, and the head bends down off the neck. It prints a step table (about 150 facets, under 2 s of planning in total). `godot -s tests/crane.gd -- --shots=DIR` renders the finished crane from the side, three-quarters and above to `DIR` (needs a display).

## Code layout
- `scripts/paper_geometry.gd` - 2D polygon clipping / overlap helpers
- `scripts/paper_model.gd` - rigid-origami model: facets in paper space + 3D transforms, fold planning (crease from grab/target, connectivity, tear check, layer order, reverse folds), stacking offsets, grab handles
- `scripts/paper_layers.gd` - layer-order solver for flat-folded stacks (taco/tortilla constraints, transitivity, search)
- `scripts/paper_sheet.gd` - a sheet in the world (`RigidBody3D`): mass/centre of mass from the paper, sliding, respawn, live fold preview, undo, flip/turn, thin-slab meshes and collision
- `scripts/player.gd` - `CharacterBody3D` bean: movement, step-up, grab/fold input, procedural wobble and arm reaching
- `scripts/level.gd` - terrain, lighting, sheets, shared orbit camera, input map, sheet sliding, win condition

## Known limits / next steps
- Crane benchmark limits (rigid paper only bends at creases): narrowing the legs also folds a small gusset into the layers above each leg, so the wings hinge where those gussets end, a little higher than a hand-folded crane's (wings 2.6 m long rather than 4 m). And a real crane puffs out its body as the wings open; here the body stays flat and the wings stand square to it.
- Paper is rigid between creases: a whole sheet tips and falls, but a flap doesn't droop or bend under its own weight.
- Fold collision checks the folded result (and, for ordinary folds, the flap's swing) against the world, but checks paper-against-paper only for the final position, so a flap can still swing through other paper on its way to a valid spot.
- Flip turns a sheet 180 deg; there's no free 3D rotation yet (e.g. to stand a finished plane upright, or throw it).
- Local co-op only, shared camera.
