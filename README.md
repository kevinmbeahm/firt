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
| Pick up a prop (apple, weight block) | hold grab near it; raise / lower it with **Space** / **C**; release to put it down | hold **.**; **/** / **;** |
| Carry a sheet together | one bean grabs an edge, the other grabs another edge while the first still holds it; walk to carry, raise / lower your end | (same) |
| Hang on (paper on a cable) | hold grab at an end of the hooked crease; release to drop, push the stick as you release to hop off | (same) |

Gamepads (device 0 = P1, device 1 = P2): left stick move, A jump/raise, B lower, X grab, Y fold type, RB sheet handling.
Shared camera: mouse / right stick / Q-E to orbit. **Z** undo last fold, **Backspace** restart the room, **Page Up / Page Down** previous / next room, **Esc** release mouse, **F11** (or Alt+Enter) fullscreen. The view stretches to fill any window size.

**Solo play:** **V** (or LB on P1's pad) swaps which bean you control. The bean you leave stands still but keeps holding whatever it was holding (and keeps its weight on the paper), so you can hold a flap up with one bean and do something else with the other. Swap back and the first bean keeps holding until you press grab (then letting go creases the fold). In two-player games, bean 2 goes back to P2 when P1 swaps back. To carry a sheet alone, grab one edge, swap, and grab another edge with the other bean: the idle bean then walks and raises its hands in step with the one you drive. The **weight block** (70 kg, as heavy as a bean) stands in for a second bean on scales and seesaws.

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
- **Printed creases**: some sheets come with crease lines printed on them (blue: fold toward you, red: fold away, as seen from the cream side). A fold close to a printed line (or to any crease made before) folds exactly along it; the bigger the flap, the more forgiving the aim, since you can't lift the far edge of a 4 m flap 4 m up.
- A sheet holds still while someone's folding it (you can't slide it then either), so walking onto it with a corner in your hands doesn't shove it.
- Hold *sheet handling* to slide the whole sheet (riders are carried; if you're not on it you walk alongside; sliding doesn't spin it), flip it over (to fold the other side) or turn it.

## Paper physics
Each sheet is a rigid body with real weight (mass from its area; centre of mass recomputed after every fold):
- It rests on whatever holds it up and slides with friction.
- Hang it too far over an edge and it tips and falls. Your weight counts: walking out onto an overhang can tip a sheet that was balanced.
- A sheet lost in the void comes back at its starting spot (with its folds).
- You can only slide a sheet that's resting on something (no steering it in mid-fall). Flips, turns and undos are refused when the paper would end up inside something solid.

## Rooms
The game is a series of puzzle rooms, one at a time; solving a room (both beans at its flag) moves you on to the next after a few seconds. The room's name, hint and progress show at the bottom of the screen. Puzzle designs for future rooms are in [docs/puzzle_design.md](docs/puzzle_design.md).

1. **The Ramp.** Get both players to the flag on the 2.2 m ledge across a 7 m gap; too high to jump, too far to just slide the sheet across (it would tip into the void). Fold part of the big sheet up into a **ramp**, ride the sheet out until the ramp's tip reaches over the ledge so it's held up at both ends, and walk up. (Hint: whatever you stand on when you fold the far strip up comes up too.) The smaller sheet on the island is a free-folding sandbox: try a paper plane, or fold a strip in half and reverse-fold its tip.
2. **Doorway: Square.** A glowing square is painted on a wall next to a locked door. Stand paper up against the wall so it fills the square (at least 90% covered, no more than 10% spilling outside) and the door opens. Fold the sheet in half on its printed line, stand half of it up on the other line, then slide it into place.
3. **Doorway: House.** The same with a house shape. Fold the roof corners down while the paper's flat (they're out of reach once it stands up), then stand it up and slide it in.
4. **Tight Squeeze.** A 12 x 12 m sheet and a wall with a low tunnel (1.2 m high, 3.4 m wide) behind a door. A glowing sizer box in front of it opens the door once the paper fits inside: fold the sheet in half three times, slide the strip in, and push it through. The beans go round by a narrow passage (too tall for the tunnel, too narrow for the paper) and pull it out on the far side; there, unfold it (undo) and lay it flat over the glowing square on the floor.
5. **Basket Run.** Six 15 kg apples on an upper terrace, a scale on the lower one that needs all six at once, and a long ramp between. The scale tips everything back up the hill if it's left part-loaded for 30 s, so ferrying apples one by one is too slow. Fold the sheet's sides up on the printed lines into a **trough**, roll the apples in, then carry it down the ramp together, one bean at each open end. Keep it level: tilt it and the apples roll out of the ends.
6. **Counterweight Lift.** A long seesaw plank is the only way up to a high ledge. It rests with its near end down, a ramp to the ledge, but tips under you once you're past the middle unless its near end is weighed down. One bean (or the weight block) can hold it for the other, but the last one up needs a counterweight of apples, and loose apples roll off the slope: carry them up onto the plank's near end in a folded trough.
7. **Paper Elevator.** A hook bar hangs in a shaft below a high ledge, on a lift that rises while a plate is pressed: the one in the alcove at the bottom, or the one up on the ledge. Fold the sheet in half, carry it up to the bar together until the crease hooks on, and hang on while your partner stands on the bottom plate. At the top, push toward the ledge as you let go to hop off; then the top plate brings the lift back up with your partner hanging on.
8. **Zipline Delivery.** A cable runs down from the cliff to an island across the void. Fold the sheet in half on its printed line, carry it up to the cable together (one of you at each end of the crease) until the crease lies along the cable: it hooks on and you're both hanging from it. Ride it down and let go over the island.

**Props and plates.** Apples and the weight block are physics objects: they roll and slide, ride in folded paper, and slow you down while you carry them. Things resting in a sheet two beans are carrying move with it (as if friction held them; tilt it and they still roll), and the carried sheet follows the hands smoothly, so stepping up a ledge doesn't fling the load out. A carried sheet slips out of your hands if you pull its ends more than 1.5 m apart (or push them together), and either bean letting go drops it. Pressure plates weigh the props in the column above them, including props inside paper set down on them (but not props still being carried).

**Cables.** Carry a sheet up to a cable (or a hook bar) with a crease lying along it, and once the crease lies along as much of it as it can, it hooks on: it swings to hang below and the carriers are left hanging on to it. A hooked sheet is held by the two ends of its hooked crease: grab one to hang on, let go to drop, and push the stick as you let go to hop off that way. With someone hanging on it slides downhill along the cable (on its own, friction holds it). Each metre of crease on the cable holds 50 kg, so a little corner folded over it holds the sheet and one bean but slips off under two.

**Shape gates** come in two modes: an outline (on a wall, or lying on the floor) that paper must cover (at least 90%, no more than 10% spilling), and a fit box that every corner of the paper must be inside.

## Tests
Run each with `godot --headless --fixed-fps 120 -s tests/<name>.gd` (exit code 0 = pass). `--fixed-fps 120` steps the physics exactly once per frame, which makes the bot runs deterministic; without it, how many physics steps fall between two input frames depends on how fast the machine is, and the longer bot runs can occasionally miss a step.

- `godot --headless -s tests/fold_model.gd` folds a paper plane step by step and checks layer-selective folds, partial angles, crease reuse, tear refusal, and inside/outside reverse folds.
- `godot --headless -s tests/fold_physics.gd` checks folds against the world and the rigid body: flat folds near the floor go over the top, flaps rest on the ground instead of passing through it, hanging flaps over the void, no paper through paper, buried corners, undo/turn needing room, no steering falling sheets, clean grab release, respawn orientation.
- `godot --headless -s tests/unfold_game.gd` folds a strip over with real inputs, then walks the flap back sloppily and checks it unfolds along the old crease.
- `godot --headless -s tests/paper_physics.gd` checks sheets rest, tip into the void when pushed over an edge, respawn, and tip under the players' weight.
- `godot --headless -s tests/solve_level.gd` has bots solve room 1 (the Ramp) with real input actions (fold a ramp, ride the sheet out to the ledge, climb) and asserts the win condition.
- `godot --headless -s tests/solve_doorways.gd` has bots solve both Doorway rooms with real input actions (fold on the printed lines, stand the paper up, slide it against the wall, walk through the door), and checks that paper spilling past the outline keeps the door shut.
- `godot --headless -s tests/solve_squeeze.gd` has bots solve Tight Squeeze with real input actions (fold down three times, slide into the sizer, push through the tunnel, go round, pull it out, undo the last fold, cover the square).
- `godot --headless -s tests/solve_elevator.gd` has bots solve the Paper Elevator with real input actions (hook the folded sheet on the bar, one rides up while the other stands on the plate, hop off, and back again from the top plate).
- `godot --headless -s tests/solve_zipline.gd` has bots ride the Zipline with real input actions (fold, carry the crease up to the cable until it hooks on, ride down, let go over the island), and checks that a short hook slips off under two beans.
- `godot --headless -s tests/solve_carry_rooms.gd` has bots solve the Basket Run and the Counterweight Lift with real input actions (fold a trough, load apples, carry it together down a ramp or up onto the seesaw, walk to the flag), and checks the rules on the way: a part-loaded scale tips its apples back, the plank tips under a bean with nothing on its near end and can't be outrun, and a loose apple rolls off it.
- `godot --headless -s tests/solo_carry.gd` carries a sheet solo with real inputs: grab one edge, swap, grab the other; the idle bean walks and lifts in step.
- `godot --headless -s tests/solo_swap.gd` plays solo with real inputs: lift a flap with one bean, swap, walk the other bean while the first keeps holding, swap back and crease it.
- `godot --headless -s tests/crane.gd` is the **benchmark**: it folds a traditional paper crane from an 8 m square in 32 steps with the game's own operations (precreases, square-base collapse, kite folds, petal folds, leg narrowing, inside reverse folds for a long neck and tail and a bent head, wing folds). After every step it checks the whole sheet: no tears, no paper through paper, no paper lost, a valid stacking. Then it checks the crane's shape: neck and tail rise well above the spread wings on opposite sides, and the head bends down off the neck. It prints a step table (about 150 facets, under 2 s of planning in total). `godot -s tests/crane.gd -- --shots=DIR` renders the finished crane from the side, three-quarters and above to `DIR` (needs a display).

## Code layout
- `scripts/paper_geometry.gd` - 2D polygon clipping / overlap helpers
- `scripts/paper_model.gd` - rigid-origami model: facets in paper space + 3D transforms, fold planning (crease from grab/target, connectivity, tear check, layer order, reverse folds), stacking offsets, grab handles
- `scripts/paper_layers.gd` - layer-order solver for flat-folded stacks (taco/tortilla constraints, transitivity, search)
- `scripts/paper_sheet.gd` - a sheet in the world (`RigidBody3D`): mass/centre of mass from the paper, sliding, respawn, live fold preview, undo, flip/turn, thin-slab meshes and collision
- `scripts/player.gd` - `CharacterBody3D` bean: movement, step-up, grab/fold input, procedural wobble and arm reaching
- `scripts/level.gd` - hosts the rooms: loads them in order, players and solo swap, lighting, shared orbit camera, HUD, input map, undo
- `scripts/room.gd` - base class for a puzzle room (terrain, sheets, goal, checkpoints, doors), with the rooms in `scripts/rooms/`
- `scripts/shape_gate.gd` - shape gates: an outline the paper must fill (profile mode), or a box it must fit inside
- `scripts/prop.gd` - loose props (apples, crates, the weight block): pick up, carry, respawn
- `scripts/pressure_plate.gd` - plates and scales that weigh the props on them
- `scripts/cable.gd` - cables and hook bars that creased paper hangs on

## Known limits / next steps
- Crane benchmark limits (rigid paper only bends at creases): narrowing the legs also folds a small gusset into the layers above each leg, so the wings hinge where those gussets end, a little higher than a hand-folded crane's (wings 2.6 m long rather than 4 m). And a real crane puffs out its body as the wings open; here the body stays flat and the wings stand square to it.
- Paper is rigid between creases: a whole sheet tips and falls, but a flap doesn't droop or bend under its own weight.
- Fold collision checks the folded result (and, for ordinary folds, the flap's swing) against the world, but checks paper-against-paper only for the final position, so a flap can still swing through other paper on its way to a valid spot.
- Flip turns a sheet 180 deg; there's no free 3D rotation yet (e.g. to stand a finished plane upright, or throw it).
- The two-bean carry is kinematic: the sheet moves rigidly between the hands (it doesn't swing or sag), and only two beans can carry one sheet.
- Local co-op only, shared camera.
- Shape gates have the profile (outline) and fit-box modes; the design doc's "bridge two points with a walkable surface" footprint test isn't built.
- Hanging is kinematic too: a hooked sheet swings to hang below its cable (it can't be pushed into a swing), and only creases of a carried sheet hook on (paper dropped onto a cable doesn't).
