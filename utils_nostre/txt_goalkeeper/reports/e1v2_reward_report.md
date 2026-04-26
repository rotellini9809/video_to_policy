# E1V2 Mezzaluna Reward Report

This report reflects the current `e1V2_mezzaluna` implementation in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1V2_mezzaluna/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1V2_mezzaluna/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## Reward Model

Per control step:

`R_step = dt * sum_i (w_i * raw_i)`

Current timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 4.0`

Current `RewardManager` behavior:
- each configured term contributes `weight * raw * dt`
- NaN/Inf contributions are zeroed with `torch.nan_to_num(...)`
- zero-weight terms are skipped at compute time
- episodic reward logs are normalized by episode length in seconds

Current zero-weight configured terms:
- `stance_center_target_progress`
- `ball_in_fov`
- `stance_width_band_pen`
- `pelvis_between_feet`
- `waist_ready_twist_abs_pen`

Implemented in `mdp.py` but not currently configured:
- `outside_keeper_area_penalty`
- `stance_center_home_x_asymmetric_abs_penalty`

## Task Context

This task uses the moving mezzaluna point as the stance target. The fixed home point still exists for visualization and reset context, but the active stance shaping terms use:

`reward_target_xy = mezzaluna_point_xy`

Relevant constants from `env_cfgs.py`:
- fixed home-point marker: `(KEEPER_HOME_POINT_X, KEEPER_HOME_POINT_Y) = (6.55, 0.0)`
- keeper area bounds: `x in [6.0, 7.5]`, `y in [-2.0, 2.0]`
- mezzaluna center: `(E1_MEZZALUNA_CENTER_X, E1_MEZZALUNA_CENTER_Y) = (6.8, 0.0)`
- mezzaluna apex: `E1_MEZZALUNA_APEX_X = 5.95`
- mezzaluna half-width: `E1_MEZZALUNA_HALF_WIDTH_Y = 1.65`

Body-name settings used by the stance terms:
- left foot: `^left_foot_link$`
- right foot: `^right_foot_link$`
- waist: `(?i)^waist$`

## Current Weighted Reward Set

Current reward-rate expression depends on curriculum stage only through
`action_rate_l2`:

Stage 1:

`R_rate = -0.002*action_rate_l2 -0.01*body_ang_vel -20.0*fallen -0.5*joint_pos_limits -1.6*low_height_soft_penalty -0.45*stance_center_target_xy_abs_pen +1.5*stance_ortho_to_ball_reward +0.8*upright`

Stage 2+:

`R_rate = -0.004*action_rate_l2 -0.01*body_ang_vel -20.0*fallen -0.5*joint_pos_limits -1.6*low_height_soft_penalty -0.45*stance_center_target_xy_abs_pen +1.5*stance_ortho_to_ball_reward +0.8*upright`

Configured reward table:

| Name | Weight | Function | Main params |
|---|---:|---|---|
| `action_rate_l2` | `-0.002` in stage 1, `-0.004` in stage 2+ | `action_rate_l2` | none |
| `body_ang_vel` | `-0.01` | `body_ang_vel_penalty` | none |
| `fallen` | `-20.0` | `fallen_indicator` | `min_height=0.32`, `max_roll_deg=100.0` |
| `joint_pos_limits` | `-0.5` | `joint_pos_limits` | all robot joints |
| `low_height_soft_penalty` | `-1.6` | `low_height_soft_penalty` | `h_soft=0.48` |
| `stance_center_target_xy_abs_pen` | `-0.45` | `stance_center_target_xy_abs_penalty` | `command_name=set_square`, stance feet from `^left_foot_link$` / `^right_foot_link$` |
| `stance_center_target_progress` | `0.0` | `stance_center_target_progress_reward` | `command_name=set_square`, stance feet from `^left_foot_link$` / `^right_foot_link$` |
| `stance_ortho_to_ball_reward` | `+1.5` | `stance_ortho_to_ball_reward` | `command_name=set_square`, `ortho_deadband=0.10` |
| `ball_in_fov` | `0.0` | `ball_in_fov_reward` | `command_name=set_square` |
| `stance_width_band_pen` | `0.0` | `stance_width_band_penalty` | `w_min=0.23`, `w_max=0.45` |
| `pelvis_between_feet` | `0.0` | `pelvis_between_feet_reward` | `waist_body_name=(?i)^waist$`, `apply_standing_gate=True` |
| `upright` | `+0.8` | `upright_stability_reward` | `roll_band=0.10`, `roll_sigma=0.12`, `pitch_target=0.25`, `pitch_band=0.20`, `pitch_sigma=0.30` |
| `waist_ready_twist_abs_pen` | `0.0` | `waist_ready_twist_abs_penalty` | `k=2.5`, `apply_standing_gate=True` |

## Raw Reward Notes

`action_rate_l2`
- `raw = sum((a_t - a_{t-1})^2)`

`fallen`
- `raw = 1` if base height `< 0.32` or torso roll `> 100 deg`, else `0`

`joint_pos_limits`
- generic joint-limit pressure penalty across all robot joints

`low_height_soft_penalty`
- `raw = relu(0.48 - base_height)^2`

`stance_center_target_xy_abs_pen`
- `raw = ||reward_target_xy - stance_center_xy||_2`
- this replaces the older split x/y absolute penalties

`stance_center_target_progress`
- rewards positive reduction in stance-center error to the current reward target
- currently configured off because weight is `0.0`

`stance_ortho_to_ball_reward`
- rewards keeping the foot-line orthogonal to the ball direction
- uses the current stance center and the ball direction from that stance center
- respects the configured `ortho_deadband`

`ball_in_fov`
- binary visibility reward based on the configured planar FOV mask
- currently configured off because weight is `0.0`

`stance_width_band_pen`
- `raw = relu(0.23 - width)^2 + relu(width - 0.45)^2`
- currently configured off because weight is `0.0`

`pelvis_between_feet`
- lateral pelvis-centering reward in the support frame
- currently configured off because weight is `0.0`

`upright`
- smooth torso posture reward with strict lateral tilt and a mild forward-lean target
- upside-down poses receive zero upright reward through the sign term on projected gravity

`waist_ready_twist_abs_pen`
- penalizes waist yaw that deviates from the ball-facing ready orientation
- applies the standing gate before accumulation
- currently configured off because weight is `0.0`

## Shared Helpers And Gates

Reward target:
- the mezzaluna point is the intersection of the mezzaluna half-ellipse with the ray from ellipse center toward the current ball position
- if the ball moves behind the ellipse center, only the ray `x` component is reflected, so the target stays on the same upper/lower side of the arc

Reward active mask:
- in `e1V2_mezzaluna`, the reward active mask is currently always on

Alignment ramp:
- some stance terms use `_alignment_home_ramp(...)`
- it is centered on the moving mezzaluna target, not the fixed home-point marker

Standing gate:
- used by `pelvis_between_feet_reward` and `waist_ready_twist_abs_penalty`
- posture and height are combined into a soft multiplicative gate, not a hard on/off mask

## Current Terminations

| Termination | Trigger |
|---|---|
| `time_out` | episode length reached |
| `nan_detection` | invalid physics state |
| `fallen` | low height or excessive roll persists for `6` consecutive RL steps |
