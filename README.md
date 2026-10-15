# Fold

A 2-player local co-op **3D** puzzle-platformer in **Godot 4** (tested on 4.3), in the wobbly physics-playground spirit of *Human Fall Flat*. The twist: giant sheets of paper (~10x the size of a player) that you grab, fold and slide around to build your own platforms.

## Run
Open this folder in Godot 4.3+ and press **F5** (main scene: `scenes/main.tscn`). Click the window to capture the mouse for camera control.

## Controls
| | Player 1 | Player 2 |
|---|---|---|
| Move | WASD | Arrow keys |
| Jump | Space | `/` |
| Grab + fold | hold **F** or **LMB** near a glowing corner/edge, walk, release | hold **.** |
| Slide whole sheet | hold **R** or **RMB** + move | hold **,** + move |

Gamepads (device 0 = P1, device 1 = P2): left stick move, A jump, X grab/fold, RB slide sheet.
Shared camera: mouse / right stick / Q-E to orbit. **Z** undo last fold, **Backspace** restart, **Esc** release mouse.

## How folding works
- Walk up to a corner or edge midpoint of the paper; a glowing marker shows what you can reach. Hold *grab* and your arms stretch out to it.
- Walk to drag it. The held point follows you, and the paper creases along the perpendicular bisector of (where you grabbed -> where you are), so the corner lands exactly where you carry it. An orange line marks the crease and the flap swings over live.
- Release to commit. The fold is permanent (until undone) and the paper is thick, solid and stackable: the flap lands on top, back side (blue) showing. Fold again to build 2, 3, 4... layer stacks.
- Hold *slide sheet* and move to push the whole folded sheet around; anyone standing on it is carried along.
- One layer is a step you can walk up; a full jump clears about two more.

## Level 1
Get both players to the flag on the 2.6 m ledge across the gap. A single jump off a 1-2 layer paper bridge isn't enough: fold the sheet into a stack of **3+ layers**, board it, slide it up against the ledge, and jump across.

## Tests
`godot --headless -s tests/solve_level.gd` runs a bot that solves level 1 using only real input actions (two folds, slide, climb) and asserts the win condition.

## Code layout
- `scripts/paper_geometry.gd` - polygon clipping / overlap helpers
- `scripts/paper_sheet.gd` - the foldable sheet: facet model, fold + undo, flap-swing animation, slab meshes, collision (an `AnimatableBody3D`)
- `scripts/player.gd` - `CharacterBody3D` bean: movement, step-up, grab/fold input, procedural wobble and arm reaching
- `scripts/level.gd` - terrain, lighting, shared orbit camera, input map, sheet sliding, win condition

## Known limits / next steps
- Local co-op only, shared camera (split-screen and online play are natural next steps).
- Folds are flat: every layer on the grabbed side moves, and nothing blocks a fold passing through other geometry. Overhanging flaps are rigid.
- Crease lines can appear as grab points.
