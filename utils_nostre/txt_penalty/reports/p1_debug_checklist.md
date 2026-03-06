# P1 Debug Checklist

Use this checklist when the penalty expert behaves strangely.

## 1) Coordinate sanity
- Is the goal plane really at `x = +GOAL_X_LINE`?
- Does the robot face +x at spawn?
- Does the ball start in front of the robot?

## 2) Goal event sanity
- If you do **not** terminate on goal, verify goal rewards are **event-based**.
  - `goal_event` should be 1 only on the first crossing step.

## 3) Termination sanity
- Ensure there is **no** `success_goal` termination.
- Ensure there **is**:
  - `second_touch`
  - `ball_out`
  - `fallen`
  - `time_out = 6s`

## 4) Reward scale sanity
- If return explodes, reduce dense shaping:
  - `ball_flight_high_side` weight
  - `ball_to_aim_speed_3d` weight
- Keep event rewards large (they fire once):
  - `goal_high_corner_event`

## 5) Visual debugging
- Enable P1 test walls + overlays.
- Use `play --agent random` to verify the geometry and terminations first.
