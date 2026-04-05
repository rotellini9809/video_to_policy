# E1V2 Mezzaluna Reward Report (Current Implementation)

This report reflects the current `e1V2_mezzaluna` task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1V2_mezzaluna/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1V2_mezzaluna/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## 1) Reward Aggregation

Per RL step:

`R_step = dt * sum_i (w_i * raw_i)`

Current timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 4.0`

Current `RewardManager` behavior:
- each term is multiplied by `weight * dt`
- `torch.nan_to_num(...)` is applied before accumulation
- terms with `weight = 0.0` are skipped at compute time
- episodic reward logs are normalized by episode length in seconds

Current zero-weight configured terms:
- `body_ang_vel`
- `stance_center_home_x_progress`
- `stance_center_home_y_progress`
- `stance_center_move_toward_home`
- `stance_ortho_progress`
- `pelvis_between_feet`

Implemented in `mdp.py` but not currently configured in `cfg.rewards`:
- `outside_keeper_area_penalty`
- `stance_center_home_x_asymmetric_abs_penalty`
- `stance_ortho_to_ball_reward`

## 2) Task Context

This task is not using a fixed home point for shaping. The fixed home point still exists as a visual reference, but reward shaping uses the moving mezzaluna point.

Relevant constants from `env_cfgs.py`:
- fixed home point visual reference: `(KEEPER_HOME_POINT_X, KEEPER_HOME_POINT_Y) = (6.55, 0.0)`
- keeper area bounds: `x in [6.0, 7.5]`, `y in [-2.0, 2.0]`
- shared band radius: `HOME_POINT_BAND_RADIUS = 0.20`
- mezzaluna ellipse center: `(E1_MEZZALUNA_CENTER_X, E1_MEZZALUNA_CENTER_Y) = (6.8, 0.0)`
- mezzaluna apex: `E1_MEZZALUNA_APEX_X = 5.95`
- mezzaluna half-width: `E1_MEZZALUNA_HALF_WIDTH_Y = 1.65`
- upright constants:
  - `roll_band = 0.10`
  - `roll_sigma = 0.12`
  - `pitch_target = 0.25`
  - `pitch_band = 0.20`
  - `pitch_sigma = 0.30`

Body-name settings used by stance-related rewards:
- left foot: `^left_foot_link$`
- right foot: `^right_foot_link$`
- waist: `(?i)^waist$`

## 3) Reward Target Used By Shaping

In this task:

`reward_target_xy = mezzaluna_point_xy`

The mezzaluna point is the intersection between:
- the mezzaluna half ellipse
- the ray from ellipse center to current ball position

Important detail:
- if the ball moves "behind" the ellipse center, the helper reflects only the ray `x` component, so the target stays on the same upper/lower side of the mezzaluna and does not jump across the arc

So when reward names still say "home", they now mean:
- the moving mezzaluna target
- not the fixed home-point dot

## 4) Global Gates / Shared Helpers

### Reward active mask

In `e1V2_mezzaluna`, the reward active mask is currently always on:

`reward_active_mask = 1`

So unlike older E1 variants, there is no dynamic command-phase gating right now.

### Alignment ramp

Several shaping terms are multiplied by `_alignment_home_ramp(...)`, which is centered on the moving mezzaluna target:

- `home_x_err = |target_x - stance_center_x|`
- `home_y_err = |target_y - stance_center_y|`
- `alpha_x = clamp(1 - home_x_err / 0.30, 0, 1)`
- `alpha_y = clamp(1 - home_y_err / 0.25, 0, 1)`
- `alpha = alpha_x * alpha_y`
- `align_mult = 0.2 + 0.8 * alpha`

So the multiplier is:
- `1.0` near the target
- `0.2` far away

### Standing gate

Some terms have `apply_standing_gate=True`.

That helper computes:
- a posture score from projected gravity
- a height score from base height
- `stand_score = posture_score * height_score`
- `gate = stand_score^2`

with:
- `h_low = 0.40`
- `h_good = 0.62`

This is a soft multiplicative gate, not a hard boolean switch.

## 5) Configured Reward Terms

Current configured reward-rate expression:

`R_rate = -0.004*action_rate_l2 -0.005*angular_momentum +0.0*body_ang_vel -6.0*fallen -0.5*joint_pos_limits -1.6*low_height_soft_penalty -0.35*stance_center_home_x_abs_pen +0.0*stance_center_home_x_progress -1.10*stance_center_home_y_abs_pen +0.0*stance_center_home_y_progress +0.0*stance_center_move_toward_home -0.65*stance_ortho_abs_pen +0.0*stance_ortho_progress -0.3*stance_width_band_pen +0.0*pelvis_between_feet +0.8*upright -0.10*waist_ready_twist_abs_pen`

| Name | Weight | Function | Main params |
|---|---:|---|---|
| `action_rate_l2` | `-0.004` | `action_rate_l2` | none |
| `angular_momentum` | `-0.005` | `angular_momentum_penalty` | `sensor_name=robot/root_angmom` |
| `body_ang_vel` | `0.0` | `body_ang_vel_penalty` | none |
| `fallen` | `-6.0` | `fallen_indicator` | `min_height=0.32`, `max_roll_deg=100.0` |
| `joint_pos_limits` | `-0.5` | `joint_pos_limits` | all robot joints |
| `low_height_soft_penalty` | `-1.6` | `low_height_soft_penalty` | `h_soft=0.48` |
| `stance_center_home_x_abs_pen` | `-0.35` | `stance_center_home_axis_abs_penalty` | `axis=x` |
| `stance_center_home_x_progress` | `0.0` | `stance_center_home_axis_progress_reward` | `axis=x`, `max_delta=0.12`, `apply_standing_gate=True` |
| `stance_center_home_y_abs_pen` | `-1.10` | `stance_center_home_axis_abs_penalty` | `axis=y` |
| `stance_center_home_y_progress` | `0.0` | `stance_center_home_axis_progress_reward` | `axis=y`, `max_delta=0.20`, `apply_standing_gate=True` |
| `stance_center_move_toward_home` | `0.0` | `stance_center_move_toward_home_reward` | `r_deadband=0.20`, `v_cap=0.3`, `apply_standing_gate=True` |
| `stance_ortho_abs_pen` | `-0.65` | `stance_ortho_abs_penalty` | `ortho_deadband=0.10` |
| `stance_ortho_progress` | `0.0` | `stance_ortho_progress_reward` | `ortho_deadband=0.10`, `max_delta=0.20`, `apply_standing_gate=True` |
| `stance_width_band_pen` | `-0.3` | `stance_width_band_penalty` | `w_min=0.23`, `w_max=0.45` |
| `pelvis_between_feet` | `0.0` | `pelvis_between_feet_reward` | `waist_body_name=(?i)^waist$`, `apply_standing_gate=True` |
| `upright` | `+0.8` | `upright_stability_reward` | upright constants above |
| `waist_ready_twist_abs_pen` | `-0.10` | `waist_ready_twist_abs_penalty` | `k=2.5`, `apply_standing_gate=True` |

## 6) Raw Reward Definitions

Conventions:
- `center_xy = 0.5 * (left_foot_xy + right_foot_xy)`
- `target_xy = moving mezzaluna point`
- `ReLU(x) = max(x, 0)`
- `clamp(x, a, b)` clips to `[a, b]`

### Regularization

`action_rate_l2`
- `raw = sum((a_t - a_{t-1})^2)`

`joint_pos_limits`
- `raw = sum_j [ (low_j - q_j)_+ + (q_j - high_j)_+ ]`

`angular_momentum`
- `raw = ||L||^2`
- reads builtin sensor `robot/root_angmom`
- returns zeros if the sensor is missing

`body_ang_vel`
- `raw = wx^2 + wy^2`
- currently configured but skipped because weight is `0.0`

### Fall / posture / height

`fallen`
- `height = root_link_pos_w[:, 2]`
- `torso_roll_deg = abs(rad2deg(roll(root_link_quat_w)))`
- `raw = 1` if `(height < 0.32) OR (torso_roll_deg > 100.0)`, else `0`

`low_height_soft_penalty`
- `raw = ReLU(0.48 - base_height)^2`

`upright`
- `sagittal = projected_gravity_b[:, 0]`
- `lateral = projected_gravity_b[:, 1]`
- `vertical = projected_gravity_b[:, 2]`
- `roll_error = ReLU(|lateral| - 0.10)`
- `roll_score = exp(-(roll_error^2) / 0.12^2)`
- `pitch_error = ReLU(|sagittal - 0.25| - 0.20)`
- `pitch_score = exp(-(pitch_error^2) / 0.30^2)`
- `upright_sign_score = clamp(-vertical, 0, 1)`
- `raw = roll_score * pitch_score * upright_sign_score`

The `upright_sign_score` factor is important:
- upside-down poses now get zero upright reward

### Stance-center positioning

`stance_center_home_x_abs_pen`
- `raw = |target_x - center_x|`

`stance_center_home_y_abs_pen`
- `raw = |target_y - center_y|`

`stance_center_home_axis_progress_reward`
- stateful previous absolute-error buffer per axis
- `err_abs = |target_axis - center_axis|`
- `effective_prev = err_abs` on the first step, else stored previous error
- `raw = clamp(effective_prev - err_abs, 0, max_delta)`
- standing gate is applied for the configured variants
- currently configured but skipped because both progress weights are `0.0`

`stance_center_move_toward_home`
- `to_target = target_xy - center_xy`
- `dist = ||to_target||`
- if `dist <= r_deadband`, direction is zeroed
- `v_center_xy = 0.5 * (v_left_foot_xy + v_right_foot_xy)`
- `toward_speed = dot(v_center_xy, dir_to_target)`
- `raw = clamp(toward_speed, 0, v_cap)`
- standing gate is then applied
- currently skipped because weight is `0.0`

### Stance geometry

Shared helper:
- `stance_dir = normalize(right_foot_xy - left_foot_xy)`
- `ball_dir = normalize(ball_xy - center_xy)`
- `dot = dot(stance_dir, ball_dir)`
- `ortho_err = ReLU(|dot| - 0.10)`

Interpretation:
- `0` means stance is orthogonal to the ball direction within the deadband
- positive values mean the foot line is too aligned with the ball direction

`stance_ortho_abs_pen`
- `raw = ortho_err`
- then multiplied by the alignment ramp

`stance_ortho_progress`
- stateful previous `ortho_err` buffer
- `effective_prev = ortho_err` on the first step, else stored previous error
- `raw = clamp(effective_prev - ortho_err, 0, max_delta)`
- standing gate is applied
- then multiplied by the alignment ramp
- currently skipped because weight is `0.0`

`stance_width_band_pen`
- `width = ||right_foot_xy - left_foot_xy||`
- `raw = ReLU(0.23 - width)^2 + ReLU(width - 0.45)^2`

`pelvis_between_feet`
- projects pelvis offset into support-frame coordinates
- `lateral_offset = dot(pelvis_offset, support_normal)`
- `longitudinal_offset = dot(pelvis_offset, support_dir)`
- current reward uses only the lateral component
- `lat_term = (lateral_offset / lateral_sigma)^2`
- `raw = exp(-lateral_weight * lat_term)`
- standing gate is applied
- then multiplied by the alignment ramp
- currently skipped because weight is `0.0`

### Waist ready-twist term

`waist_ready_twist_abs_pen`
- computes the support-line normal that faces the same side as the ball
- defines a desired ready yaw from that normal
- `twist_err = wrap_to_pi(waist_yaw - desired_ready_yaw)`
- `raw = 1 - exp(-2.5 * twist_err^2)`
- standing gate is applied
- then multiplied by the alignment ramp

This is the only active waist-related reward still in the task.

## 7) Termination Context Relevant To Rewards

The reward-side `fallen` indicator and the termination-side `FallTermination` use the same condition:
- `height < 0.32` or `abs(torso_roll_deg) > 100`

Termination requires persistence:
- `consecutive_steps = 6`

So the reward can penalize a fall immediately, while termination waits for the condition to last for several steps.

## 8) Notes Specific To E1V2

- Reward shaping is centered on the moving mezzaluna point, not the fixed home-point dot.
- Zeroed waist-yaw rewards have been removed completely from `e1V2`.
- Several legacy shaping terms remain implemented but disabled via `weight = 0.0`.
- Because the reward active mask is always on in this task, the meaningful gates are:
  - standing gate for selected terms
  - alignment ramp for selected terms
  - per-term deadbands and saturations
