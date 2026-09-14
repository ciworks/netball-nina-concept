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
| `scripts/power_gauge.gd` | `PowerGauge` | Floating shot-power meter, shown only while the token holds the ball. |
| `scripts/direction_gauge.gd` | `DirectionGauge` | Shot direction dial, revealed once a power value is selected. |
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
   power meter comes up for `POSSESSION_TIME` (3.0s). Shooting is not built, so
   the window simply runs out, which is classed as a missed shot
   (`_shot_window_expired()`) and the coach feeds the next ball.

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
- A possession always resolves too. Once the token holds the ball the round is
  in `COMPLETE` on the shot clock, and the clock running out is a missed shot -
  the ball goes back to the coach either way.

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

Shooting does not exist in the prototype yet, so nothing triggers `excited` - but
the missed-shot reaction is live: a possession whose 3 second window runs out
without a shot is a miss, and `_shot_window_expired()` reports it. Main's
`report_shot_result(made)` is the seam: call it with `true` for a perfect shot
and `false` for a miss once a shooting move exists.

## Shot power meter

`scripts/power_gauge.gd` (`PowerGauge`) is a floating panel anchored to the centre
of the screen, built in code by `ui.gd` on the same ignore-only root as the rest
of the HUD. It is visible only while the token is holding the ball, which Main
tracks as `_has_ball` and pushes out through `ui.set_power_gauge_visible()`.

- Possession starts on a clean catch (`_complete_catch()`) or on collecting a
  loose ball (the collect branch of `_finish_movement()`), and ends when the
  coach takes the ball back for the next feed (`_start_coach_round()`).
- The window is `POSSESSION_TIME` (3.0s), and it is the round's `State.COMPLETE`
  timer, so the meter stays up for 3 seconds once it appears. Letting it run out
  without a shot is classed as a missed shot: `_shot_window_expired()` reports it
  through `report_shot_result(false)` (the avatar goes angry) and settles through
  the normal `MISS` beat, which hands the next feed to the coach.
- `CATCH_COMPLETE_TIME` (1.6s) now only governs the route highlight and the
  rating beat, not the length of the possession.
- The required range is sized from `Main.distance_to_post_cells()` - the
  straight-line distance from the token's cell to `POST_CELL`, in court cells.
  The mapping (which power band, how wide) lives in `power_gauge.gd` as
  `MIN/MAX_DISTANCE_CELLS`, `BAND_CENTER_NEAR/FAR` and `BAND_HALF_NEAR/FAR`:
  further out means more power and a narrower band.
- Selecting a value is hold and release. The meter itself never reads input, so
  `Main._unhandled_input()` watches the press and release: pressing while the
  token holds the ball calls `_begin_power_charge()` (the needle charges from
  zero under `CHARGE_SPEED`), and letting go calls `_release_power_charge()`,
  which locks the value into `_selected_power` through `ui.power_gauge_power()`.
  A press only charges when `_has_ball` is true and a drag only begins in
  `READY`, so the two can never overlap.
- Hold and release only ever sets a value. No shot is fired: the possession
  clock keeps running down and still ends as a missed shot, so the selected
  value is read by nothing but the debug line.
- Selecting a value raises the shot direction meter (see the next section): the
  power is locked on release, so a direction is chosen against a settled power.
  `in_accuracy_band()` says whether a locked needle sits inside the required
  band, and a settled shot should report through `Main.report_shot_result(made)`.
- The meter must stay `MOUSE_FILTER_IGNORE`. It hangs over the middle of the
  court, and a Control that stopped touches there would eat drag strokes drawn
  across the screen (hard rule 4).

## Shot direction meter

`scripts/direction_gauge.gd` (`DirectionGauge`) is a semicircular dial, built in
code by `ui.gd` on the same ignore-only root as the rest of the HUD. It is the
direction half of a shot, the way the power meter is the strength half, and it is
built to the supplied reference art.

- The art it follows: a flat grey outer track, a coloured band inside it, and a
  dark needle turning on a hub at the bottom centre.
- The needle position is a direction across the upper half of the screen: dial
  left is aimed left, dial middle is straight up the screen, dial right is aimed
  right. It reads in screen space because it has to match the direction the
  player can actually see in the 3/4 projection.
- The optimal direction is owned by Main (`_optimal_direction_t()`): the
  direction from the token's screen position to `grid_to_screen(POST_CELL)`,
  mapped onto 0..1 across the dial. A post below the token clamps to the nearest
  end, because the dial only covers the upper half of the screen.
- Green is a valid shot and red is out of bounds. The green arc spans
  `DIRECTION_TOLERANCE` (0.05) either side of the optimal direction - 5% each
  way, which over the dial's 180 degree sweep is 9 degrees either way.
- It appears once a power value has been selected, because a direction is chosen
  against a settled power. `_release_power_charge()` locks the power and then
  raises the dial, and `_sync_power_gauge()` keeps the optimal direction in step
  while it is up. It hides again at the next feed.
- Nothing moves the needle yet and no shot is fired, so it sweeps the dial by
  itself (`SWEEP_SPEED`) to show where the green range sits. A direction move
  should call `set_direction()` and judge with `in_valid_range()` or
  `valid_range()`, then report through `Main.report_shot_result(made)`.
- It must stay `MOUSE_FILTER_IGNORE`, like every other floating HUD node: a
  Control that stopped touches over the court would eat drag strokes (hard rule 4).

## Common change recipes

- **New player name / expression art**: drop the PNGs into
  `res://images/players/<name>/` and call `set_player_name()` on the avatar.
  Expression keys live in `avatar.gd` as `EXPRESSION_*`.
- **New test scenario**: add an entry to `SCENARIOS` in `main.gd` and matching
  entries to `SCENARIO_LABELS` and `SCENARIO_TIPS` in `ui.gd`. The three lists
  are indexed together by button position and must stay the same length.
- **Repaint the court**: edit the `Court` and `CourtMarkings` layers in the
  editor's TileMap panel. If the atlas layout itself changes, regenerate the
  `tile_map_data` blob with `res://tools/dump_court_data.tscn` and paste the
  result from `res://tools/court_data.txt` into `main.tscn`.
- **Restyle the route highlight**: replace
  `res://images/court_move_highlight.png`. `court.gd` samples its fill colour
  and its corner cuts, so the art is the styling.
- **Change the feed**: `coach.gd` phases and constants, plus the round
  start/advance calls in `main.gd`.
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
- `asset_check.*` - asset sanity check.

## Known gaps and placeholder art

- Still no shooting mechanic: nothing fires, and the possession window's
  expiry-as-a-miss is the only shot outcome that exists. Both halves of the aim
  are built and wired (the power meter and the direction dial), so the missing
  piece is a trigger that reads `power()` / `direction()` against
  `required_range()` and `valid_range()` and reports through
  `Main.report_shot_result(made)`.
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
