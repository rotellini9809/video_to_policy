# E1 Reward Report (Current Implementation)

This report reflects the active E1 Set&Square task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/mdp.py`

## 1) Reward Terms Configured in E1

Per-step total reward is the weighted sum:

`R = 2.5*yaw_align + 1.0*upright - 0.45*drift - 0.06*xy_speed - 2.0*outside_area - 8.0*fallen`

## 2) Term-by-Term Definition

## 2.1 `yaw_align` (weight `+2.5`)
Function:
- `yaw_alignment_reward(..., k=2.5)`

Raw term:
- `exp(-k * yaw_error^2)` with `k=2.5`
- `yaw_error` is signed yaw-only angle between torso forward direction and ball direction in XY plane.

Range and effect:
- Raw range `(0, 1]`
- Weighted contribution `(0, 2.5]`
- Encourages the torso to face the ball.

## 2.2 `upright` (weight `+1.0`)
Function:
- `upright_stability_reward(height_target=robot_cfg.init_state.pos[2])`

Raw term:
- `height_reward = exp(-(height - height_target)^2 / height_sigma^2)`, `height_sigma=0.12`
- `upright_reward = exp(-(tilt^2) / tilt_sigma^2)`, `tilt_sigma=0.5`
- `upright = height_reward * upright_reward`

Where:
- `tilt = ||projected_gravity_b_xy||`

Range and effect:
- Raw range `(0, 1]`
- Weighted contribution `(0, 1]`
- Encourages nominal base height and upright torso.

## 2.3 `drift` (weight `-0.45`)
Function:
- `xy_drift_l2`

Raw term:
- `||root_xy - spawn_xy||^2`

Effect:
- Penalizes translation away from spawn position.
- Penalty grows quadratically with displacement.

## 2.4 `xy_speed` (weight `-0.06`)
Function:
- `xy_speed_l2`

Raw term:
- `||root_lin_vel_xy||^2`

Effect:
- Penalizes base planar motion speed.
- Supports "set and square" behavior (micro-adjustment, not locomotion).

## 2.5 `outside_area` (weight `-2.0`)
Function:
- `outside_keeper_area_penalty`

Raw term:
- L1-style violation magnitude outside keeper bounds:
  - `x_low + x_high + y_low + y_high`, each clamped at zero.
- Bounds are in env-local XY and set to:
  - `x in [6.0, 7.5]`
  - `y in [-2.0, 2.0]`

Effect:
- Soft penalty once the keeper exits the allowed area.
- Penalty scales with distance outside.

## 2.6 `fallen` (weight `-8.0`)
Function:
- `fallen_indicator(min_height=0.32, max_tilt=1.25)`

Raw term:
- `1.0` if `(height < 0.32) OR (tilt > 1.25)`, else `0.0`

Effect:
- Large discrete per-step penalty in fallen states.

## 3) Terminations That Interact with Reward

Configured terminations:
- `time_out` (episode timeout)
- `fallen` from `FallTermination` with `min_height=0.32`, `max_tilt=1.25`, `consecutive_steps=6`
- `out_of_area_hard` from `outside_keeper_area_hard`

Hard out-of-area bounds:
- soft bounds expanded by margin `0.3`:
  - `x in [5.7, 7.8]`
  - `y in [-2.3, 2.3]`
- episode terminates as soon as any violation is positive.

Important:
- Falling is both penalized by reward and used for early termination.

## 4) Episode Timing Context

- Episode length is `5.0 s`.
- Base simulation timestep is `0.005 s`, with `decimation=4` (`step_dt=0.02 s`).

## 5) Practical Reading of the Current Reward Design

1. Positive signal is dominated by yaw tracking and upright stability.
2. Translation/motion are penalized continuously (`drift`, `xy_speed`) and area escape is penalized/terminated.
3. The design strongly favors stationary readiness with ball-facing alignment, matching E1 intent.
