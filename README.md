# Fold

A 2-player co-op puzzle-platformer built in **Godot 4** (tested on 4.3), built around folding giant sheets of paper (~10x player size).

## Run
Open this folder in Godot 4.3+ and press **F5** (main scene: `scenes/main.tscn`).

## Controls
| | Player 1 | Player 2 |
|---|---|---|
| Move | WASD | Arrow keys |
| Jump | Space | `/` |
| Fold | hold **F** near a corner/edge, walk, release | hold **.** |
| Slide whole sheet | hold **E** + move | hold **,** |

Gamepads (device 0 = P1, device 1 = P2): left stick move, A jump, X fold, RB slide sheet.
Global: **Z** undo last fold, **Backspace** restart.

## How folding works
- Stand near a highlighted corner or edge midpoint and hold *Fold* to grab it. A tether shows what you're holding.
- Walk to where the grabbed point should land. The fold line is the perpendicular bisector of grab-point -> your position (the grabbed point is folded onto you). An orange dashed line previews the crease and the folded result.
- Release to commit. Folds are permanent (until undone) and stack: everything on the grabbed side is mirrored on top, back side showing in blue.
- Hold *Slide sheet* and move to push the entire folded sheet around; anyone standing on it rides along.
- Paper layers count as height: you can step up 1 layer, and jump ~3 layers.

## Level 1
Bring both players to the flag on the 6-layer-high ledge. Fold the sheet into >= 3 layers, slide it next to the ledge, and climb.

## Code layout
- `scripts/paper_geometry.gd` - polygon clipping helpers
- `scripts/paper_sheet.gd` - facet-based paper model: `fold_facets`, undo, handles, rendering
- `scripts/player.gd` - movement, grab/fold input, z-axis platforming
- `scripts/level.gd` - level data, input map setup, camera, HUD, sheet pushing
