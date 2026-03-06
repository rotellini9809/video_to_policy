# P1 Reward Report (Penalty SetShot)

This report summarizes the intended reward/termination design for the **Penalty expert**:
- `mjlab/src/mjlab/tasks/penalty_expert/p1_set_shot/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/penalty_expert/p1_set_shot/mdp.py`

The penalty expert is constrained to **one kick** and aims for **high + lateral** shots.

---

## 1) Key design rules

1) **No termination on goal**.
2) All goal-related rewards must be **event-based**:
   - they output `1` only on the **first** step where the ball crosses the goal plane in the goal mouth.
   - after that, they return `0` even if the ball stays behind the goal line.

If goal rewards are dense while you don’t terminate on goal, PPO will see a huge constant reward tail and training becomes unstable.

---

## 2) Reward terms (suggested config)

Per-step total reward (training):

```
R = 3.0*yaw_align
  - 1.0*tilt_penalty
  + 2.0*approach_ball
  + 1.0*behind_ball
  + 4.0*strike_event
  + 3.0*ball_to_aim_speed_3d
  + 4.0*ball_flight_high_side
  + 30.0*goal_high_corner_event
  - 10.0*goal_bad_event
  + 2.0*goal_scored_event
  - 0.5*outside_area
  - 0.03*xy_speed
  - 8.0*fallen
```

Notes:
- `goal_high_corner_event`, `goal_bad_event`, `goal_scored_event` must be event-based.
- If `ball_flight_high_side` dominates early learning, reduce it to ~2–3 and increase the event reward instead.

---

## 3) What each term does

### `yaw_align`
Encourages the trunk heading to face the aim point direction.

### `approach_ball` + `behind_ball`
Gets the robot into a stable pre-kick pose: close to ball, and with the ball in front.

### `strike_event`
A positive pulse on the **first** ball contact.

### `ball_to_aim_speed_3d`
Rewards ball velocity component toward the 3D aim point (pushes upward if `aim_z` is high).

### `ball_flight_high_side`
Dense shaping while the ball travels: rewards being **high** and **wide**.
Use moderate thresholds:
- shaping: `z_min ~ 1.05`, `|y|_min ~ 0.95`

### `goal_high_corner_event`
Main success: goal event AND high+wide thresholds, e.g.
- corner: `z_min ~ 1.25`, `|y|_min ~ 1.00`

### `goal_bad_event`
Penalty for scoring too central or too low.

### `fallen`
Strong negative terminal (or near-terminal) penalty.

---

## 4) Terminations

The environment should terminate on:
- `fallen`
- `second_touch` (ball touched more than once)
- `ball_out` (out-of-play)
- `hard_outside_area`
- `time_out` (6 seconds)

And should NOT terminate on:
- `goal_scored`
