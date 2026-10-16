# Fold: Puzzle Design Plan

Status: **design, partly built.** Section 9 records what's implemented. Decisions
from review are folded into the text and summarised in section 8. Numbers come from the current build (player
5 m/s, jump ~1.4 m, step-up 0.55 m, reach 2.4 m, hands lift -3..+3.2 m, player
70 kg, paper 0.6 kg/m², so an 18 x 12 m sheet weighs about 130 kg).

---

## 1. What makes a good Fold puzzle

The verb is **"turn this flat sheet into the shape the world needs."** Every
puzzle should be won by the *shape* the players fold, not by finding a key or
a hidden lever. Five rules for every puzzle:

1. **The goal reads at a glance.** A gap, a river, a high ledge, a glowing
   silhouette in a wall. Players should be able to say what they need ("a ramp
   that reaches up there", "something that floats") before they know how to
   fold it.
2. **The folding is the answer, the world is the question.** The level gives
   constraints (size of a gap, height of a ledge, width of a doorway, wind
   direction). The sheet size and pre-made creases limit what can be built.
3. **Physics checks the work.** A ramp that's too steep is unclimbable, a boat
   with a hole sinks, an overhanging sheet tips. No "is this a boat?" checkbox
   if physics can judge it. Where physics can't (see §4), use a shape gate
   that measures the real geometry.
4. **Co-op is load-bearing.** At least one step per puzzle needs two players
   at once: one holds, one folds; one stands as a counterweight, one walks the
   plank; one carries the corner across, the other pins the sheet.
5. **Failure is funny, never punishing.** Lost sheets respawn with their folds;
   Z undoes; players respawn at the last checkpoint. A boat that capsizes is a
   joke, not a reload.

### Difficulty levers (use one or two per puzzle, not all)

| Lever | Easy | Hard |
|---|---|---|
| Number of folds | 1 | 5+ in order |
| Fold kind | flat fold | partial angle, reverse fold, collapse |
| Precision | "roughly here" (big tolerance) | must match a shape gate within ~0.3 m |
| Precreases given | crease lines printed on the sheet | blank sheet |
| Sheet handling | sheet already in place | slide, flip, turn, carry it there |
| Physics | static result | must survive load, water, wind, motion |
| Co-op timing | sequential | simultaneous (hold + walk) |

---

## 2. Mechanics we have today

- Fold any corner or edge to any point, at any angle (flat or partial), with
  live preview and snapping. Folds persist. Z undoes.
- Layer-selective folds: fold only the connected flap you grabbed.
- Inside and outside reverse folds.
- Collapse along existing creases (squash and petal folds), with a choice of
  results.
- Sheet handling: slide (with riders), flip 180°, turn 45°.
- Rigid-body sheets: mass from area, centre of mass follows folds, tipping
  over edges, player weight counts, respawn when lost.
- Solid paper: folds stop against the world, and no paper passes through
  paper.

## 3. New systems the puzzles need

Each puzzle in §5 lists which of these it needs. They're in rough build order
(cheapest and most reused first).

| # | System | What it does | Used by |
|---|---|---|---|
| S1 | **Printed creases / sheet patterns** | Sheets can spawn with visible precrease lines (and optionally crease memory set as mountain/valley), plus coloured regions or targets printed on the paper | P2, P3, P5, P8, P12, P14, P15 |
| S2 | **Shape gates** | A volume or silhouette in the world (glowing outline) that checks whether a sheet's folded geometry fits: inside a box, covers a footprint, matches a profile within tolerance. Opens a door / lights a lamp / counts as a goal | P3, P4, P10, P12, P15 |
| S3 | **Pressure plates and weights** | Plates that trigger on mass (players, sheets, loose objects) | P6, P11, P13 |
| S4 | **Loose props** | Physics objects you can push and carry (balls, crates, paper cups, pebbles); grabbing a prop uses the same grab button | P5, P6, P11 |
| S5 | **Water** | Buoyancy for sheets (displaced volume from folded geometry, see §4.1), drag, a gentle current. Paper never gets soggy | P5, P7 |
| S6 | **Wind** | Fans and vents that push sheets based on their exposed area in the wind's direction (sail, plane, kite) | P8, P9, P14 |
| S7 | **Cables / ziplines** | A rope between two anchors. A sheet folded over the rope with a crease along it hangs and slides along it (see §4.3) | P2 |
| S8 | **Moving and rotating world parts** | Lifts, turntables, drawbridges, pulleys driven by plates or by weight | P11, P13 |
| S9 | **Light and shadow** | Spotlights casting the sheet's shadow onto a wall; a shadow target counts as a shape gate in 2D | P10 |

---

## 4. How the game judges a folded shape

The game has the exact folded geometry (facets with 3D transforms and stacking
order), so every check can be honest physics or measurement rather than
recognising a named model.

### 4.1 Boats and baskets: volume below a rim

To decide whether a folded sheet **holds water** (a boat floats, a basket
carries pebbles):

1. Find the sheet's lowest region in its resting pose and treat the paper as
   the walls of a container.
2. Take horizontal slices at increasing heights. At each height, the paper
   crossing that slice must form a **closed loop** (no gaps wider than the
   paper thickness; stacked layers count as one wall). Paper layers that are
   joined at a fold count as sealed. Gaps between separate flaps that only
   overlap also count, as real paper boats do.
3. The highest closed slice is the **rim height**. The enclosed volume under
   it is the capacity.
4. **Buoyancy** = water density × the enclosed volume that's below the
   waterline, plus the paper's own displacement. A boat sinks when the
   waterline reaches the rim, or when it tips enough that the rim dips under.
   Tipping comes for free from the rigid body: buoyancy acts at the centre of
   the displaced volume.

This makes the traditional paper boat, a "tub" (four sides folded up and the
corners folded in, i.e. the masu box) and a crude "taco" all valid, at
different capacities and stabilities. A flat sheet floats too (a raft), but it
has no rim, so anything heavy swamps it.

### 4.2 Shape gates: fit and cover tests

A shape gate is authored as either:

- **Fit box**: the folded sheet (any pose) must fit fully inside an outline
  (for example a 2 x 2 x 6 m slot in a wall to post a sheet through, or a
  "mailbox" opening). Test all facet vertices against the box after the
  player pushes the sheet in.
- **Footprint**: the sheet must cover a marked area on the floor with at least
  N layers, or bridge two marked points with a continuous walkable surface no
  steeper than X°.
- **Profile**: seen from a fixed direction (like a shadow), the sheet's
  silhouette must cover ≥ 90% of the target shape and spill ≤ 10% outside it.
  Use a coarse raster (64x64) of the projected facets.

Gates show live feedback: the outline glows brighter as coverage rises, and
red where paper spills outside it.

### 4.3 Hangers and hooks (zipline)

A sheet **hangs on a cable** when it has a crease (or an inside fold) that
lies within ~0.15 m of the cable along at least 1 m, with paper on both sides
dropping below the cable (an upside-down V). Then:

- The sheet's rigid body gets a slider joint along the cable through that
  crease line.
- It slides downhill, with speed limited by friction, which depends on how
  long the crease is.
- Players can grab the dangling flaps (hold the grab button on any paper edge
  while airborne) and ride.
- A crease that's too short or too shallow, or a sheet that's too heavy
  (overloaded hook), lets it slip off.

### 4.4 Stability and load

"Will this platform hold?" is already physical: sheets tip over edges, and
player weight counts. **Paper doesn't sag or break** (decided in review): a
single layer is as strong as a stack. Structural folds still matter for
*shape* (walls that stop things sliding or blowing off, a channel that stays
on a narrow path), and wind (S6) can flip a light, flat sheet.

---

## 5. The puzzles

Each entry gives the setup, the goal, the intended solution, the co-op roles,
alternative solutions we should allow, how players fail, the systems needed and
a difficulty rating from 1 to 5.

---

### P1. "The Ramp" (exists: Level 1)

- **Setup:** an island, a 2.2 m ledge 7 m away across a gap, one 18 x 12 m
  sheet.
- **Goal:** both players reach the flag on the ledge.
- **Solution:** fold the far strip up into a ramp at about 25°, slide the
  sheet out (riding it) until the ramp tip rests on the ledge and the sheet is
  held at both ends, then walk up.
- **Co-op:** one rides as ballast so the overhang doesn't tip while the other
  slides it.
- **Teaches:** grabbing, partial folds, sheet sliding, tipping.
- **Systems:** none (done). **Difficulty:** 1.

---

### P2. "Zipline Delivery"

- **Setup:** a cable runs downhill from a cliff top to a lower island 25 m
  away. Starting on the cliff: a 6 x 10 m sheet with one precrease printed
  lengthwise down its middle (S1). The cable anchor is at chest height.
- **Goal:** cross to the lower island.
- **Solution:** fold the sheet in half along the printed crease (a V, not
  flat: hands raised so the halves stay apart about 60°). Together, lift it so
  the crease sits on the cable (one player per end, each raising hands to
  cable height). It hooks on. Each player grabs a dangling flap and rides it
  down.
- **Co-op:** carrying a 10 m sheet up onto a cable takes both ends held at
  once (S7 checks the crease length against the cable). Two riders weigh
  140 kg; the sheet only holds if the crease runs along at least 4 m of
  cable, which forces the long fold rather than a quick corner fold.
- **Alternate solutions:** a corner folded over the cable as a small triangle
  hook works for *one* rider only (short crease, low friction), so a second
  trip is needed. Two trips are allowed: the sheet slides back if a player pulls
  it uphill.
- **Failure:** the crease isn't on the cable, so the sheet falls (it respawns
  at the top). Folded flat, the halves press together and there's nothing to
  hold on to.
- **Variant (harder, later):** no printed crease, and a second cable going the
  other way that the sheet has to be moved to mid-route (a "transfer" at a
  pylon).
- **Systems:** S1, S7. **Difficulty:** 2.

- **As built (room 8):** as designed, with these choices. A crease hooks on
  only when it's carried up to the cable (two beans, one at each end of the
  crease) and lies along it; it then swings to hang below, and the carriers
  are left hanging on, held by the ends of the crease. A flat fold works as
  well as a V (like a towel over a line). The paper stays put on the cable
  until someone hangs on, then slides down (about 4 m/s at most). Each metre
  of crease holds 50 kg: the 10 m crease takes both beans, a corner fold of
  about 2.7 m holds one and slips off under two. There's no pulling it back
  uphill for a second trip yet.
---

### P3. "Shape of the Doorway"

- **Setup:** a wall with a glowing **outline** painted on it at floor level
  (a square first, later a house, an arrowhead, a diamond) and a locked door
  beside it. A sheet lies on the floor in front of the wall, with a few
  creases printed on it (S1) in early rooms.
- **Goal:** stand paper up against the wall so that it fills the outline: it
  must cover at least 90% of the shape, with no more than 10% spilling
  outside it (S2, profile mode, looking straight at the wall). The door then
  opens; reach the flag behind it.
- **Solution (square, 3 x 3 m, 6 x 6 m sheet):** fold the sheet in half to
  3 x 6, slide it against the wall, then lift the half nearest the wall
  straight up (a partial 90° fold along the printed crease). Lifting a 6 m
  wide half instead spills over the outline, so the first fold matters.
- **Solution (house):** fold the two top corners down along the printed roof
  lines while the sheet is still flat (the top is out of reach once it stands
  up), then stand it up the same way.
- **Co-op:** one player folds and stands the paper up while the other lines
  the sheet up with the outline and slides it in (a sheet can't be slid while
  someone's mid-fold, so it's fold, then slide). In the house room the second
  player can spot the roof corners from the far side.
- **Series:** square, house, then later an arrowhead, a diamond (turn 45°
  first), and a crane outline as an end-game challenge. Shapes that need cuts,
  like a star, are out.
- **Teaches:** precise flat folds, standing sheets on edge, partial folds.
- **Systems:** S1, S2. **Difficulty:** 1 (square) to 4 (crane outline).

---

### P4. "Tight Squeeze"

- **Setup:** a low tunnel (1 m high, 2 m wide) leads to a room with a tall
  ledge. A huge 16 x 16 m sheet sits outside the tunnel.
- **Goal:** get the sheet through the tunnel and use it as a ramp on the
  other side.
- **Solution:** fold it down small enough to fit: fold in half three times
  into a 2 x 8 m strip, then turn it to line up with the tunnel. The sheet must
  pass through the tunnel physically: it's pushed through, and the tunnel
  collides like any wall. On the other side, unfold it (by hand or with undo:
  undo is unlimited, decided in review) and refold it as a ramp. Undo needs
  room to swing the paper back out, so unfolding inside the tunnel is refused.
- **Co-op:** pushing a long strip through a tunnel needs one player each end
  (the sheet has to be turned 45° to get round a bend inside).
- **Teaches:** folding *down* (compact shapes), turning, planning a fold
  sequence you'll want to reverse.
- **Systems:** none new (S2 optional for feedback). **Difficulty:** 2.

- **As built (room 4):** a 12 x 12 sheet, a 1.2 x 3.4 m tunnel through a 6 m
  thick wall, and a **sizer box** (the fit-box gate) in front of it: the
  tunnel door opens once every corner of the paper is inside the box, so the
  sheet must be folded to a 3 x 6 strip (in half three times). The beans
  can't fit the tunnel; they go round by a narrow passage (too narrow for the
  paper unless it's folded four times the same way, an allowed alternative)
  and pull the strip out on the far side with sheet handling. Instead of a
  ramp to a ledge, the far side asks you to unfold it (undo) and lay it over a
  6.2 m square on the floor (a profile gate lying down).
---

### P5. "Paper Boat"

- **Setup:** a calm river 20 m wide (S5) with a gentle current toward a
  waterfall at the far end. A dock on each side. On the start dock: one
  square 8 x 8 m sheet printed with its precreases (S1: the paper boat's
  crease pattern), plus a crate (S4).
- **Goal:** get both players *and the crate* to the far dock.
- **Solution:** fold the traditional paper boat (the folds are printed: fold
  in half, corners to centre, brims up, open into a square, fold up, pull
  open). With the precreases, the opening steps are a **collapse** (choose the
  boat option). Slide it off the dock into the water. Put the crate in, climb
  in, and paddle (walking inside the boat shifts its centre of mass; leaning
  forward drifts it forward) or drift with the current and jump off at the far
  dock before the falls.
- **Co-op:** the boat tips if both players stand on one side (load
  balancing). One must stand in the middle while the other climbs in. The
  crate makes three loads to balance.
- **Alternate solutions:**
  - A **raft** (a flat or doubled sheet) floats players but the
    crate swamps it (no rim; §4.1). Players can cross on a raft, then the
    crate can't come, and the far door needs the crate on a plate (S3). So the
    raft gets you halfway: a good "aha".
  - A **box** (masu) holds more but steers worse (it spins in the current).
    Allowed.
- **Failure:** a leaky hull (a gap in the rim loop) sinks in seconds; the
  sheet washes over the falls and respawns, with its folds, on the start dock.
- **Systems:** S1, S3, S4, S5. **Difficulty:** 3.

---

### P6. "Basket Run"

- **Setup:** an orchard terrace. Six paper "apples" (balls, S4) lie scattered
  on the upper terrace. A pressure plate on the lower terrace needs all six
  (each 15 kg, plate needs 90 kg; players don't count, the plate is too small
  to stand on). A 7 x 7 m sheet. The only way down is a narrow ledge path.
- **Goal:** deliver all six apples to the plate in one go (a timer resets the
  plate if it's emptied).
- **Solution:** fold a **basket**: a masu box (four sides up, corners tucked
  in by reverse folds), or a simpler "tray" (fold the four edges up as
  partial 90° folds). With the corners not tucked, the sides fall down when
  carried. Players load the apples, then **carry the basket together**: each
  grabs an opposite rim and walks the ledge path. A sheet held by two players
  moves with them (new: a two-handed carry, which is just two grabs on one
  sheet).
- **Co-op:** the carry is mandatory (the basket is 20 kg plus 90 kg of apples,
  too heavy for one); walking out of step tilts it and spills apples.
- **Alternate solutions:** carry apples one by one (allowed, but the timer
  makes six trips too slow); a ramp to roll them down (allowed if it lands
  them on the plate, which is hard to aim: a funnel-shaped fold at the bottom
  of the ramp could do it, a great emergent answer).
- **Systems:** S3, S4, two-player carry. **Difficulty:** 3.
- **As built (room 5):** the container is a **trough**, not a masu box or
  tray: the sheet has two printed lines and you fold its two sides up, leaving
  the ends open. Each bean holds an open end, so carrying it out of level rolls
  apples out of the ends. The path down is a 4 m wide ramp. The scale tips its
  load back up the hill after 30 s part-loaded. The basket isn't too heavy for
  one bean to drag (sheets are light); the time limit is what makes the carry
  worth it.

---

### P7. "Ferry Across the Flood"

- **Setup:** S5 water with a **current**, three small islands in a line
  across a wide river, two sheets (one large, one small), and no dock on the
  far bank, only a 1.5 m high wall to climb.
- **Goal:** reach the far bank.
- **Solution:** build a boat from the big sheet (any valid hull). Paddle to
  island 2. There, use the small sheet as a **ramp/step** onto the far wall
  (1.5 m is above the step-up height, so a step is needed): fold it into a
  wedge or a Z-fold step and slide it against the wall from the boat. A boat
  is a moving platform, so the ramp must be placed while one player holds the
  boat against the wall.
- **Co-op:** one anchors the boat (holding on to a post: grabbing the world),
  the other builds the step.
- **Teaches:** combining two built objects, building on a moving base.
- **Systems:** S5 (plus a "grab a post" anchor; reuse grab). **Difficulty:** 4.

---

### P8. "Paper Plane Post"

- **Setup:** a canyon too wide to bridge (40 m). A strong fan (S6) on the near
  side blows across. On the far side a lever is high on a wall inside a
  target ring. A 4 x 6 m sheet printed with the paper-plane creases (S1).
- **Goal:** hit the target ring with a thrown plane to lower the far
  drawbridge (S8).
- **Solution:** fold a paper plane (the existing test already folds one):
  kite, fold in half, wings down. Launching is a new action: hold the plane
  over your head (lift +3 m), run, release. The wind carries it. A flat sheet
  just tumbles, and a plane with its wings up spirals down.
- **Co-op:** the second player stands on the fan control to set the fan
  speed (three settings). Too strong overshoots, too weak drops short. The
  thrower calls the setting.
- **Alternate solutions:** a **glider** (just the wings, no keel) is less
  stable but works with the right fan speed. Any shape with enough lift and
  stability is accepted; the target is only hit-based.
- **Systems:** S1, S6, S8, throw action. **Difficulty:** 3.

---

### P9. "Sail Away"

- **Setup:** a lake (S5) with steady wind (S6) blowing along it. The goal
  pier is upwind at a diagonal. Two sheets: one big for a hull, one small.
- **Goal:** reach the upwind pier.
- **Solution:** boat from the big sheet (P5). Fold the small sheet into a
  **sail** with a spine fold (a vertical crease gives it a mast-like edge)
  and stand it up in the boat (it's held upright by a partial 90° fold whose
  foot is pinned under a player's weight). Turning the sail 45° to the wind
  (the turn action) tacks the boat diagonally; wind force is applied along the
  sail's normal, so a sail at an angle drives the boat sideways and forwards.
- **Co-op:** one stands on the sail's foot and turns it at each tack; the
  other balances the boat.
- **Systems:** S5, S6 (normal-based force). **Difficulty:** 4.

---

### P10. "Shadow Play"

- **Setup:** a dark room. A spotlight (S9) shines across the room onto a
  wall, where a faint chalk outline shows a **bird** (or a rabbit, a fox, a
  house, a boat). A 6 x 6 m sheet on a pedestal between the light and the
  wall.
- **Goal:** make the sheet's shadow match the outline (profile gate, S2).
- **Solution:** for the fox: the classic "fold a triangle, fold the ears up".
  The shadow can be scaled by sliding the sheet nearer the light, and rotated
  by turning it, so the **3D shape doesn't need to be exact, only its
  silhouette**. Partial folds count: a flap standing at 90° casts a thin
  line, a flap at 45° a foreshortened one.
- **Co-op:** one player stands at the wall and calls out ("left ear's too
  big") while the other folds; there's no free camera from the light's point
  of view. The "caller" can also stand in the beam and *add their own shadow*
  (a player's head as the fox's eye is a fun intended cheat).
- **Series:** four outlines in one room, each lighting a lamp; all four open
  the exit.
- **Systems:** S2 (profile), S9. **Difficulty:** 2 to 4.

---

### P11. "Counterweight Lift"

- **Setup:** a seesaw platform (S8) over a pit: one end at ground level, the
  other at a high doorway. A 10 x 10 m sheet. A pile of crates (S4).
- **Goal:** one player rises to the doorway and lowers a rope for the other.
- **Solution:** the high end needs more weight on the low end than one player.
  Fold the sheet into a **basket** (P6) and fill it with crates on the low end;
  or fold the sheet into a box that one player stands in while the other loads
  it. Only a container keeps the crates from sliding off as the seesaw tilts.
- **Co-op:** naturally asymmetric: one rides, the other loads.
- **Alternate:** stacking crates on a flat sheet works if the sheet is folded
  up at the lip to stop them sliding (a "tray"), which is a nice
  intermediate answer.
- **Systems:** S3, S4, S8. **Difficulty:** 3.
- **As built (room 6):** redesigned around a **tipping ramp**. The plank rests
  with its near end on the ground and its far end at the ledge, so it is
  itself the way up, but it tips the moment a bean walks past the middle
  (it leans back onto its near end by itself when empty, so it can't be
  soft-locked). One bean or the weight block on the near end holds it for
  the other; the last bean up needs a counterweight: eight 15 kg apples,
  carried onto the plank's near end in a trough (loose apples roll off the
  17 degree slope). Apples, not crates, and no rope.

---

### P12. "Bridge to Spec"

- **Setup:** two cliffs 9 m apart with a **footprint gate** (S2) painted on
  both lips: the bridge must land on both marked pads. Wind gusts (S6) every
  few seconds. A 10 x 14 m sheet.
- **Goal:** cross.
- **Solution:** a flat 14 m strip would bridge it, but the gusts lift and flip
  a flat sheet and blow players off it. Fold the long edges up into a
  **U-channel** (two partial 90° folds along the length): narrower, so it
  catches less wind, with walls that keep players from being blown off. Slide it
  across with one player riding the back end as a counterweight (P1 skill).
- **Co-op:** counterweight while sliding; then the first across holds the far
  end down in the gusts while the second crosses.
- **Alternate:** a doubled flat strip (folded in half lengthwise) is heavier,
  so it flips less, but walking it in the wind without walls is risky:
  allowed.
- **Teaches:** folds as structure (the channel idea).
- **Systems:** S2 (footprint), S6. **Difficulty:** 4.

---

### P13. "Paper Elevator"

- **Setup:** a vertical shaft with a pulley (S8) at the top. A rope hangs
  down with a hook on its end; the other end of the rope goes to a pressure
  plate (S3) behind a window. A 6 x 6 m sheet.
- **Goal:** one player rides up the shaft.
- **Solution:** fold a **seat** that the hook can lift: a box or basket whose
  rim takes the hook through a fold (a crease at the rim, as in §4.3). The
  second player stands on the counterweight plate (through a side door) to
  raise it. A flat sheet folds up around the rider and dumps them.
- **Co-op:** the classic "one lifts the other" pairing; the rider then drops
  a ladder (a long folded strip) back down.
- **Systems:** S3, S7 (hook on a crease), S8. **Difficulty:** 3.

- **As built (room 7):** the hook is a 4 m bar on a lift (S8) in a shaft. It
  rises while either of two plates is pressed: one in an alcove at the
  bottom, one up on the ledge. Fold the sheet in half and carry it up to the
  bar until the crease hooks on; one bean hangs on (by an end of the crease)
  while the other stands on the bottom plate, and hops off onto the ledge at
  the top. The first bean up then brings the lift back up for the other from
  the top plate, instead of dropping a ladder. There's no seat: you ride by
  hanging on. Solo, the weight block holds the bottom plate down.
---

### P14. "Kite Lookout"

- **Setup:** a misty valley. The exit is a door that only opens when a beacon
  is lit high on a cliff (20 m) above a narrow ledge you can't reach. A steady
  updraft vent (S6) next to the ledge. A 5 x 7 m sheet with a short cable
  tethered to the floor (S7, tether mode).
- **Goal:** get the tethered paper up to the beacon so a lantern hung on it
  lights it.
- **Solution:** fold a **kite**: a diamond with a centre spine fold (for
  stability), the cable attached at the printed tether point (S1 marks it).
  Place it over the vent. One player lets out line (holding the tether and
  walking forward), the other steers by standing on a turntable that turns
  the vent.
- **Co-op:** line and steering at once.
- **Alternate:** a paper plane on the tether also flies, but it's unstable;
  allowed.
- **Systems:** S1, S6, S7 (tether). **Difficulty:** 4.

---

### P15. "Crane Gate" (finale)

- **Setup:** the final hall has a crane-shaped silhouette gate (S2, profile
  plus fit) and a square sheet with only the diagonals and midlines printed.
- **Goal:** fold a crane (the same sequence as the `tests/crane.gd`
  benchmark) and stand it in the gate.
- **Co-op:** petal folds and reverse folds on a 10 m sheet need one player to
  hold layers while the other collapses them; spreading the wings needs both
  sides at once.
- **Tolerance:** the profile gate accepts the rigid-paper crane described in
  the README limits (shorter wings), plus some slack for a sloppy head angle.
- **Systems:** S1, S2. **Difficulty:** 5.

---

## 6. Proposed campaign order

| Chapter | Theme | Puzzles | New ideas introduced |
|---|---|---|---|
| 1. The Desk | Basics | P1 Ramp, P3 Doorway (square, house), P4 Tight Squeeze | grab, partial fold, slide, tipping, compact folds, unfolding |
| 2. The Garden | Carrying | P6 Basket Run, P11 Counterweight Lift, P13 Elevator | containers, two-player carry, weight plates |
| 3. The River | Water | P5 Paper Boat, P7 Ferry, P9 Sail Away | buoyancy, leaks, balance, building on moving platforms |
| 4. The Sky | Wind | P8 Paper Plane Post, P14 Kite, P2 Zipline (and its variant) | lift, throwing, hanging on cables |
| 5. The Studio | Precision | P10 Shadow Play, P12 Bridge to Spec, P3 Doorway (arrowhead, diamond) | silhouettes, structural folds |
| 6. The Workshop | Mastery | P15 Crane Gate | complex models |

Each chapter starts with a one-mechanic room, then a room that combines it
with an earlier mechanic, then a "free" room with several valid solutions.

---

## 7. Build priority (suggested)

1. **S1 printed creases + S2 shape gates.** Cheap, they reuse the existing
   fold model, and they unlock P3, P10 (with S9), P12 and P15, so a whole
   precision chapter can be made before any new physics.
2. **S4 props + S3 plates + two-player carry.** These unlock the Garden
   chapter (P6, P11).
3. **S7 cables.** A slider joint on a crease: P2, P13.
4. **S5 water.** The biggest new system (slice-based capacity, buoyancy,
   current); the River chapter depends on it.
5. **S6 wind** (normal-based force on facets) and the throw action.
6. **S8 and S9** as needed per level.

## 8. Decisions from review

| Question | Decision |
|---|---|
| Paper stiffness / sag | None. Paper doesn't sag or break (§4.4). |
| Capacity check cost | Compute capacity once when a fold is committed and cache it; only the waterline test runs every tick. |
| Undo scope | Unlimited. |
| Two-player carry | Kinematic first (the sheet moves rigidly between the two holders' hands); springs later if it feels stiff. |
| Soggy paper | No. |
| Tearing | No tearing mechanic (S10 and the old "Two From One" puzzle are cut). |
| Single player | A weight prop (a block as heavy as a player) and swapping control between the two characters. An idle character keeps holding whatever it was holding and keeps its weight. No AI partner. |

## 9. Implementation status

| Item | Status |
|---|---|
| Rooms: one level made of puzzle rooms, with restart per room, checkpoints and room-local goals | built |
| Solo character swap | built |
| S1 printed creases | built |
| S2 shape gates (profile mode) | built |
| P1 Ramp (room 1) | built |
| P3 Doorway: square, house (rooms 2, 3) | built |
| S3 pressure plates (and a scale that tips its load back) | built |
| S4 loose props: apples (balls), crates, the solo weight block | built |
| Two-player carry (kinematic; solo by swapping) | built |
| P6 Basket Run (room 5) | built (trough version) |
| P11 Counterweight Lift (room 6) | built (tipping-ramp version) |
| S7 cables and hook bars; hanging on | built |
| S8 lift (plate-driven) | built (for P13) |
| S2 fit-box mode | built |
| P2 Zipline Delivery (room 8) | built |
| P4 Tight Squeeze (room 4) | built (unfold-and-cover ending) |
| P13 Paper Elevator (room 7) | built (hang-on version, two plates) |
| Everything else | not started |
