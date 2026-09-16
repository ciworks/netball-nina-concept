# AGENTS.md

Working notes for AI agents (and humans) editing this project. Read this before
your first change.

`res://.summerrules` holds the settled design decisions for the court art, the
court projection and the player avatar. Read it before touching any of those,
and append to it rather than rewriting it.

## Project at a glance

- Finger-drag netball prototype: the player is controlled by drawing a route on
  the court with a finger or mouse, then the coach feeds a ball in and the catch
  is judged.
- Engine: Godot 4.7, renderer `mobile`.
- Language: GDScript only. There is no C# code in this project.
- Entry scene: `res://main.tscn` (`application/run/main_scene`).
- Viewport: 1280x720 base, stretch mode `canvas_items`, aspect `expand`. The
  layout must survive being stretched on a phone.
- 2D only. The court's "3/4 view" is a projection of a 2D logical grid, not 3D.
- Git repo on `master` with an `origin` remote.

## Hard rules

1. Never delete or rewrite `project.godot`, `icon.svg`, or `.godot/`.
2. Do not generate the court at run time. The floor and the line markings are
   hand-painted editor TileMap data; only the route highlight is drawn in code.
3. `main.gd` owns gameplay state. Do not move round state into the token, the
   court or the HUD.
4. Any new HUD node goes on the UI root that is already `MOUSE_FILTER_IGNORE`.
   A Control that defaults to `MOUSE_FILTER_STOP` over the court swallows the
   drag and the game stops responding to touch.
5. ASCII punctuation only in code, comments and docs. No smart quotes, no em
   dashes.

## Scene tree

```
Main            Node2D          scripts/main.gd      owns the round
  Player        AnimatedSprite2D scripts/player.gd   z_index 10, passive token
  UI            CanvasLayer     scripts/ui.gd        whole HUD built in code
  CourtRig      Node2D                              carries the 3/4 view transform
    Court         TileMapLayer                      sand checkerboard floor
    CourtMarkings TileMapLayer                      white third/mid line tiles
    CourtRoute    TileMapLayer  scripts/court.gd    route highlight overlay only
  GoalPost      Sprite2D                            netball post; main.gd places it
```

`GoalPost` is plain art, not a generated court: `main.gd` puts it on the
`POST_CELL` cell (the middle of the right goal line) in `_recompute_layout()`
and scales it to `POST_HEIGHT_CELLS` court cells tall so it keeps its height
next to the token at any viewport size. It has no script.

`Court` and `CourtMarkings` share `res://tiles/court_tileset.tres` (atlas
`res://tiles/court_tiles.svg`, 10 tiles of 32x32). All three court layers are
`z_index = -1` and are transformed together by `CourtRig`.

The coach is **not** a scene node. `Main` builds it in code (see `_create_coach`)
so it needs no texture and no scene entry.

## Scripts

| File | Global class | Role |
| --- | --- | --- |
| `scripts/main.gd` | none | Round owner: input, projection, layout, movement, scoring. Talks to everything else. |
| `scripts/ui.gd` | none | Builds the entire HUD in `_build()` and exposes setters. Owns the avatar widget. |
| `scripts/avatar.gd` | `PlayerAvatar` | The reacting face box in the top-left corner. |
| `scripts/shot_meter.gd` | `ShotMeter` | The shot meter: power bar and direction dial in one control, shown while the token holds the ball. |
| `scripts/power_gauge.gd` | `PowerGauge` | Superseded by `shot_meter.gd`. The earlier standalone power meter, no longer built by `ui.gd`. |
| `scripts/direction_gauge.gd` | `DirectionGauge` | Superseded by `shot_meter.gd`. The earlier standalone direction dial, no longer built by `ui.gd`. |
| `scripts/player.gd` | `PlayerToken` | Passive token. Main writes its position and state; it draws shadow, move ring and cell label. |
| `scripts/coach.gd` | `CoachThrower` | The feed: pick spot, hold, windup, release, projectile flight, bounce, verdict. |
| `scripts/court.gd` | `CourtBoard` | Route highlight overlay. Merges selected cells into one band. |
| `scripts/gesture.gd` | `GestureInterpreter` | Freehand stroke to orthogonal grid route (no diagonals). |

Public surface of `main.gd`: `random_test()`, `load_scenario(index)`,
`grid_to_screen(cell)`, `screen_to_grid(pos)`, `report_shot_result(made)`.

## The core loop

1. Main randomises a player cell and a target cell (the feed destination).
2. The player drags a stroke starting on the token. `GestureInterpreter` turns
   it into an orthogonal grid route, previewed live on `CourtRoute`.
3. On release the route is committed and the token walks it automatically.
4. Meanwhile `CoachThrower` runs the feed and shows a destination ring, then
   throws the ball as a real projectile. Only the first bounce is aimed; after
   that the ball carries on and decays.
5. The catch is judged the instant the ball touches down, inside `coach.gd`, by
   comparing the ball's real landing point against the cell Main reports. Being
   on the ball when it arrives is fine; arriving after it has landed is too late.
6. Outcomes:
   - Clean catch (the token was set on the spot, or won the coin flip):
     `_complete_catch()`, a PERFECT / GOOD / OK route rating flashes, phase
     `CAUGHT`, avatar goes happy.
   - Dropped feed: `_begin_loose_ball()`, phase `LOOSE BALL`, and the player has
     `LOOSE_BALL_TIME` to drag onto the ball. Collecting it clears the round;
     running out of time is a `MISS`.
   - Landed outside the court: `_feed_out_of_bounds()`, a `MISS`.
   - Both miss paths feed the avatar: one drop is sad, two in a row is angry.
7. A clean catch or a collected loose ball puts the token in possession: the shot
   meter comes up for `POSSESSION_TIME` (3.0s) and the token is shooting. The
   player picks a power (hold to charge, release to lock) and then a direction
   (hold to sweep the dial, release on the green). That second release IS the
   shot: `_fire_shot()` judges the two values against the ranges the meter was
   showing,
   the ball flies to the ring, and the round settles as a GOAL or a MISS.
   Locking the power tops the possession clock up by `AIM_WINDOW_TIME` (3.0s),
   once per possession, so the aim gets a window of its own. Letting the window
   run out without a shot is still a missed shot (`_shot_window_expired()`).
   Either way the coach feeds the next ball.

`State` is the round machine: `READY, DRAWING, COMMITTED, MOVING, COMPLETE,
INVALID, MISS`.

## Court coordinates and the projection

- The logical grid is `0..GRID_MAX` (10) on both axes. `cell_w` / `cell_h` are
  computed in `_recompute_layout()` from the viewport.
- `_project_point(p)` turns a logical point into a screen point: x runs across
  the screen, y is squashed by `VIEW_SQUASH` and slid sideways by `VIEW_SKEW`
  per row, and `COURT_FILL` sizes the whole court inside the viewport.
- `grid_to_screen(cell)` is the forward projection for a logical point;
  `screen_to_grid(pos)` is the inverse and is what maps a drag back to cells.
  Input must always round-trip through these, never through raw screen maths.
- The tile layers are transformed by `CourtRig`. The token and the ball are
  placed at projected screen positions and stay upright.

## Round rules worth preserving

- A route that merely ends on the ball is not a result. The rating word only
  ever flashes from `_complete_catch()`.
- The ball cannot be collected while the coach still holds it.
- A committed route always plays out: the loose-ball clock only ticks in
  `READY`, so it pauses during a drag or a walk.
- A landed feed is held by `_throw_pending` until the player is not mid-action,
  so the verdict is shown after the movement finishes, not during it.
- Every feed resolves exactly once, through either the loose-ball path or the
  out-of-bounds path.
- A possession always resolves too, and exactly once. Once the token holds the
  ball the round is in `COMPLETE` on the shot clock: either a release on the
  dial fires the shot (`_fire_shot()`), or the clock runs out and
  `_shot_window_expired()` classes it as a missed shot. The ball goes back to
  the coach either way.
- The possession clock starts at `POSSESSION_TIME` (3.0s), but the moment the
  power is locked it is topped up by `AIM_WINDOW_TIME` (3.0s) so picking a
  direction has a window of its own. `_aim_window_granted` allows that top-up
  once per possession only, so re-picking the power cannot hold the round open
  indefinitely, and it is cleared in `_start_test()`.
- The shot takes the press for itself while the token holds the ball, so a
  court drag and a shot can never both claim the same gesture. The power hold
  only charges while `_has_ball` is true, and a drag only begins in `READY`.

## Avatar reactions

`PlayerAvatar` reads one PNG per expression from
`res://images/players/<player_name>/player_expression_<expression>.png`
(`player_name` defaults to `nina`). Missing art falls back to the default image;
with no art at all the box stays an empty black-bordered frame.

| Event | Expression |
| --- | --- |
| Clean catch | `happy` |
| Dropped catch | `sad` |
| Second dropped catch in a row | `angry` |
| Perfect shot | `excited` |
| Missed shot | `angry` |

Main speaks in game terms and the avatar picks the face:
`ui.avatar_catch_made()`, `ui.avatar_catch_missed()`, `ui.avatar_shot_made()`,
`ui.avatar_shot_missed()`.

Both shot reactions are live. `_resolve_shot()` reports the settled shot through
`Main.report_shot_result(made)` - `true` for a shot that went through the ring
(avatar `excited`), `false` for one that came down beside it (avatar `angry`).
`_shot_window_expired()` reports the other miss: a possession whose 3 second
window ran out with no shot taken. `report_shot_result(made)` stays the single
seam for a shot outcome; nothing else should call the avatar's shot reactions.

## The shot meter

`scripts/shot_meter.gd` (`ShotMeter`) is one floating control holding both halves
of a shot: the power bar on the left, the direction dial on the right. `ui.gd`
builds it in `_build()` on the same ignore-only root as the rest of the HUD and
re-exposes it as the `ui.shot_meter_*` / `ui.set_shot_meter_*` wrappers, which
are the only surface `main.gd` uses.

- It is visible while the token holds the ball and is choosing: `_has_ball and
  not _shot_active`, pushed through Main's `_change_shot_meter(on)`, which is the
  one place that shows and hides it.
- Both halves work the same way: hold, and the needle moves by itself; release,
  and the value it was on is locked in. The power needle climbs from zero
  (`CHARGE_SPEED`); the aim needle sweeps back and forth between the dial's two
  extreme values and bounces off them (`SWEEP_SPEED`), so the green arc is a
  timing window to catch rather than a spot to drag onto.
- The two halves are still answered in order, because a direction is only
  meaningful against a settled power. Before a power is locked the press charges
  the power needle; once one is locked a press takes the aim sweep
  (`begin_aim()`), unless it landed on the power bar (`BAR_HIT`), which re-picks
  the power instead. Every aim sweep restarts from the dial's low end, so the
  timing reads the same way each time.
- The required power range is sized from `_distance_to_post_cells()` - the
  straight-line distance from the token's cell to `POST_CELL`, in court cells.
  The mapping (which band, how wide) lives in `shot_meter.gd` as
  `MIN/MAX_DISTANCE_CELLS`, `BAND_CENTER_NEAR/FAR`, `BAND_HALF_NEAR/FAR`:
  further out means more power and a narrower band.
- The green arc on the dial spans `DIRECTION_TOLERANCE` (0.05) either side of the
  optimal direction - 5% each way, which over the dial's 180 degree sweep is 9
  degrees either way. The optimal direction is owned by Main's
  `_optimal_direction_t()`: the direction from the token's screen position to
  `grid_to_screen(POST_CELL)`, read in screen space so the dial matches the
  projection the player can see, with a post below the token clamped to the
  nearest end.
- `required_range()`, `valid_range()` and `in_valid_range()` are what a shot is
  judged against, and they are exactly what the HUD is drawing, so the picture
  and the verdict can never disagree.
- The meter must stay `MOUSE_FILTER_IGNORE`. It hangs over the middle of the
  court, and a Control that stopped touches there would eat drag strokes drawn
  across the screen (hard rule 4). Main reads the press and release itself in
  `_unhandled_input()`.

`scripts/power_gauge.gd` and `scripts/direction_gauge.gd` are the two earlier,
separate halves of this meter. `ShotMeter` replaced both and `ui.gd` no longer
builds either, so they are dead code kept only as reference.

## The shot

A shot is taken when the player releases while the dial is sweeping. That release
is the trigger: the press started the sweep, the release locks the direction the
needle had reached and fires.

- `Main._unhandled_input()` routes the press and release: `_press_with_ball(pos)`
  picks the half, `_release_with_ball()` locks the power (and lights the dial)
  or, while `_aiming`, locks the direction the sweep had reached and fires.
- A drag while the dial is held is ignored: the aim needle is not the finger's,
  it sweeps on its own, so `InputEventScreenDrag` / `InputEventMouseMotion` only
  ever drive a court route.
- `_release_with_ball()` calls `_fire_shot()`, which is the one place a shot is
  judged. It freezes `_selected_power` / `_selected_direction` against the
  ranges the meter was showing at that moment, so a make means power inside its
  band AND direction inside the green arc.
- A make arrives over the ring and drops through it; a miss is offset by how far
  outside each range the value was (`_shot_miss_error()`, `_side_error()`): the
  power error carries the ball short or long as a fraction of the distance it had
  to travel (`SHOT_MISS_REACH`), and the dial error swings it off to that side by
  an angle (`SHOT_MISS_ANGLE`), each with a floor so a near miss still lands clear
  of the ring rather than looking like it went in.
- The ball is not a colliding object. The flight, the ring and the drop through
  the net are all drawn by `_draw_shot_ball()`, and the verdict is read off that
  same path.
- **The flight carries a ground track and a height separately, and a shot that
  reaches the post must ARRIVE at ring height.** `_shot_ground_at(t)` is the
  projected horizontal path to the floor point under the ring; `_shot_height_at(t)`
  climbs from `SHOT_RELEASE_HEIGHT` to the ring's height, plus an arc lift
  (`SHOT_ARC_MIN`/`SHOT_ARC_MAX`, fullest at `SHOT_ARC_FULL_CELLS`) that is zero at
  both ends. The ball is drawn at the ground point lifted by the height. Getting
  this wrong is what makes a shot slide along the floor: a height term built from
  `sin(t * PI)` alone is zero on arrival, so the ball would land at the foot of the
  post instead of at the hoop.
- The ring is read into court space, not off the screen: `_hoop_logical()` returns
  the point on the floor under the ring plus `HOOP_HEIGHT_CELLS`. It must NOT
  unproject the ring's SCREEN point - the ring's drawn position is lifted off the
  floor by its own height, so the floor inverse would read that height as distance
  up the court and throw the ball at the middle of the court. The sprite's base
  point (which is on the floor) carries the x across instead.
- `HOOP_HEIGHT_FRAC` / `HOOP_X_FRAC` are measured off
  `res://images/netball_post.png` by `res://tools/inspect_post.tscn`, and both the
  sprite and the flight are built from the same numbers. Re-measure if the post art
  is replaced.
- `_resolve_shot()` runs once the ball has come down: it reports through
  `report_shot_result(made)` (avatar `excited` on a goal, `angry` on a miss) and
  hands the round back to the next feed. A `GOAL` / `SHOT MISSED` beat holds for
  `SHOT_RESULT_TIME`, and a floor ring where the ball landed fades out over
  `SHOT_LANDING_MARK_TIME`.

## Common change recipes

- **New player name / expression art**: drop the PNGs into
  `res://images/players/<name>/` and call `set_player_name()` on the avatar.
  Expression keys live in `avatar.gd` as `EXPRESSION_*`.
- **New test scenario**: add an entry to `SCENARIOS` in `main.gd` and matching
  entries to `SCENARIO_LABELS` and `SCENARIO_TIPS` in `ui.gd`. The three lists
  are indexed together by button position and must stay the same length. Note
  that `ui.gd` does not currently build those buttons, so a new scenario is only
  reachable from code until they are switched back on.
- **Repaint the court**: edit the `Court` and `CourtMarkings` layers in the
  editor's TileMap panel. If the atlas layout itself changes, regenerate the
  `tile_map_data` blob with `res://tools/dump_court_data.tscn` and paste the
  result from `res://tools/court_data.txt` into `main.tscn`.
- **Restyle the route highlight**: replace
  `res://images/court_move_highlight.png`. `court.gd` samples its fill colour
  and its corner cuts, so the art is the styling.
- **Change the feed**: `coach.gd` phases and constants, plus the round
  start/advance calls in `main.gd`.
- **Change how a shot is judged or flown**: `main.gd`'s `_fire_shot()` (the
  judging rule and where a miss comes down) and the `SHOT_*` constants beside it
  (flight time per cell, arc height by distance, how far and how wide a miss
  spreads). The flight shape itself is `_shot_ground_at()` + `_shot_height_at()`.
  The ring comes from `_hoop_logical()` off `HOOP_HEIGHT_FRAC` / `HOOP_X_FRAC`, so
  re-measure with `res://tools/inspect_post.tscn` if the post art changes.
- **Retune the meter's ask**: `shot_meter.gd`'s band constants (power) and
  `DIRECTION_TOLERANCE` (the green arc's width).
- **Change HUD layout**: `ui.gd` `_build()`. The avatar is pinned top-left and
  the control bar's left offset is derived from the avatar size, so keep those
  two in step.

## Dev tools

`res://tools/` holds one-shot editor scenes, not part of the game. Open the
`.tscn` and press Play to run one.

- `dump_court_data.*` - regenerates the court `tile_map_data` blob.
- `build_run_sheet.*`, `inspect_run_sheet.*`, `verify_run_anim.*` - build and
  inspect the player run cycle sprite sheet.
- `inspect_highlight.*` - samples the route highlight image.
- `inspect_post.*` - prints the hoop's position inside `netball_post.png`, which
  is where the `HOOP_*` constants in `main.gd` come from.
- `asset_check.*` - asset sanity check.

## Known gaps and placeholder art

- The shot is judged from the values the player selected, not from a simulated
  ball: a make goes through the ring and a miss comes down beside it, both
  drawn. There is no rebound, no goal defence and no scoring streak - a made
  shot goes straight on to the next feed.
- The possession window still ends a shot-less possession as a miss
  (`_shot_window_expired()`), which is what happens if the player never releases
  on the dial. The clock it runs on is `POSSESSION_TIME` plus the single
  `AIM_WINDOW_TIME` top-up once a power is locked, so a player who charges and
  then never aims gets the longer of the two windows.
- The coach and the ball are drawn from primitives in `coach.gd` `_draw()`.
  Swap in real art when it exists.
- The token's animations come from `res://images/player_frames.tres`; `player.gd`
  falls back to `idle` while the `move` animation has no frames.
- Stray images at the project root and in `res://images/` (sprite sheet copies,
  a couple of imported PNGs) are not referenced by code.

## Verifying a change

There is no automated test suite. The practical check is to run
`res://main.tscn` and play a round: draw a route, take a feed, drop one, and
watch the HUD and the avatar. The in-game **Debug** toggle shows live round and
coach state; **Grid** overlays the logical grid. Script and parse errors show up
in the editor Output and Debugger panels.
