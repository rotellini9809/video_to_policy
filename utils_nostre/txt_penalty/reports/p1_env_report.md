# P1 Environment Report (Penalty SetShot)

This report captures the environment-level design decisions for the penalty expert.

---

## 1) Scene

Entities:
- `robot`: Booster T1 23-DoF
- `soccer_ball`: RoboCup ball
- `goalpost_left`, `goalpost_right`
- `soccer_field`: RoboCup field, optionally wrapped with **P1 test walls + overlays**

### P1 test walls (debug)
- walls on the 14×9 playable boundary:
  - long sides at `y = ±4.5`
  - short sides at `x = ±7.0` with an opening around the goal mouth
- shaded overlays:
  - striker allowed area
  - hard margin area

This is purely for visibility + clean out-of-play handling.

---

## 2) Reset / spawn

- Ball is placed on the penalty spot (env-local coordinates) with minimal/no noise.
- Robot spawns behind the ball, facing the goal.

Key tuning knobs:
- `PENALTY_DIST_FROM_GOAL`
- `ROBOT_BEHIND_BALL`
- `SPAWN_YAW_RANGE`

---

## 3) Action space

- High-level action is a latent vector `z`.
- `MotorLatentAction` decodes `(motor_obs, z)` through Stage‑1.

Required env var:
- `MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY`

---

## 4) Command term

`SetShotCommand` is responsible for:
- placing robot + ball at reset
- defining the 3D aim point `(aim_x, aim_y, aim_z)`
- computing metrics used by reward/termination

### Left/right generalization
Store `aim_y = 1.15` in config.
In the command term, sample the sign of `aim_y` (left/right) at reset.

---

## 5) Observations

Actor/Critic typically include:
- base linear/angular velocity (IMU)
- projected gravity
- joint pos/vel
- last decoded actions
- ball position relative
- ball velocity
- target direction

---

## 6) Episode and termination

- Episode length: **6 seconds**.
- One-touch: terminate on second ball touch.
- Out-of-play: terminate if the ball leaves the playable rectangle or crosses the end line outside the goal opening.
- Do not terminate on goal.
