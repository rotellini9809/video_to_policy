# E1 Reward Report (Current Implementation)

This report reflects the active E1 Set Square task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/mdp.py`
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
- `compute()` multiplies each reward term by `weight * dt`
- `torch.nan_to_num(...)` is applied to each weighted contribution before accumulation
- `_step_reward` stores the unscaled reward rate `weight * raw`, not the `dt`-scaled step reward
- `Episode_Reward/*` logs are episodic sums divided by `max_episode_length_s`
- terms with weight `0.0` are skipped at compute time

Current zero-weight configured terms:
- `body_ang_vel`
- `stance_center_home_x_progress`
- `stance_center_home_y_progress`
- `stance_center_move_toward_home`
- `stance_ortho_progress`
- `pelvis_between_feet`
- `yaw_err_abs_pen`
- `yaw_progress`

Implemented in `mdp.py` but not currently configured in `cfg.rewards`:
- `yaw_alignment_waist_reward`
- `outside_keeper_area_penalty`

## 2) Task Context

Relevant active constants from `env_cfgs.py`:
- home point: `(KEEPER_HOME_POINT_X, KEEPER_HOME_POINT_Y) = (6.70, 0.0)`
- keeper area: `x in [6.0, 7.5]`, `y in [-2.0, 2.0]`
- home-point band / viz radius: `HOME_POINT_BAND_RADIUS = 0.20`
- upright reward constants:
  - `roll_band = 0.10`
  - `roll_sigma = 0.12`
  - `pitch_target = 0.25`
  - `pitch_band = 0.20`
  - `pitch_sigma = 0.30`

Relevant reset behavior:
- `P_READY = 0.5`
- half of resets start from the tracked ready pose
- half of resets start from the default pose

Body-name settings used by stance-related rewards:
- left foot: `^left_foot_link$`
- right foot: `^right_foot_link$`
- waist: `(?i)^waist$`

## 3) Active Reward Terms

Current configured reward-rate expression:

`R_rate = -0.008*action_rate_l2 -0.005*angular_momentum +0.0*body_ang_vel -6.0*fallen -0.5*joint_pos_limits -1.6*low_height_soft_penalty -0.2*stance_center_home_x_abs_pen +0.0*stance_center_home_x_progress -0.7*stance_center_home_y_abs_pen +0.0*stance_center_home_y_progress +0.0*stance_center_move_toward_home -0.9*stance_ortho_abs_pen +0.0*stance_ortho_progress -0.3*stance_width_band_pen +0.0*pelvis_between_feet +1.0*upright -0.05*waist_ready_twist_abs_pen +0.0*yaw_err_abs_pen +0.0*yaw_progress`

| Name | Weight | Function | Active params |
|---|---:|---|---|
| `action_rate_l2` | `-0.008` | `action_rate_l2` | none |
| `angular_momentum` | `-0.005` | `angular_momentum_penalty` | `sensor_name=robot/root_angmom` |
| `body_ang_vel` | `0.0` | `body_ang_vel_penalty` | none |
| `fallen` | `-6.0` | `fallen_indicator` | `min_height=0.32`, `max_tilt=1.25` |
| `joint_pos_limits` | `-0.5` | `joint_pos_limits` | all robot joints |
| `low_height_soft_penalty` | `-1.6` | `low_height_soft_penalty` | `h_soft=0.48` |
| `stance_center_home_x_abs_pen` | `-0.2` | `stance_center_home_axis_abs_penalty` | `axis=x` |
| `stance_center_home_x_progress` | `0.0` | `stance_center_home_axis_progress_reward` | `axis=x`, `max_delta=0.12`, `apply_standing_gate=True` |
| `stance_center_home_y_abs_pen` | `-0.7` | `stance_center_home_axis_abs_penalty` | `axis=y` |
| `stance_center_home_y_progress` | `0.0` | `stance_center_home_axis_progress_reward` | `axis=y`, `max_delta=0.20`, `apply_standing_gate=True` |
| `stance_center_move_toward_home` | `0.0` | `stance_center_move_toward_home_reward` | `r_deadband=0.20`, `v_cap=0.3`, `apply_standing_gate=True` |
| `stance_ortho_abs_pen` | `-0.9` | `stance_ortho_abs_penalty` | foot-body defaults |
| `stance_ortho_progress` | `0.0` | `stance_ortho_progress_reward` | `max_delta=0.20`, `apply_standing_gate=True` |
| `stance_width_band_pen` | `-0.3` | `stance_width_band_penalty` | `w_min=0.23`, `w_max=0.45` |
| `pelvis_between_feet` | `0.0` | `pelvis_between_feet_reward` | `waist_body_name=(?i)^waist$`, `apply_standing_gate=True` |
| `upright` | `+1.0` | `upright_stability_reward` | upright constants above |
| `waist_ready_twist_abs_pen` | `-0.05` | `waist_ready_twist_abs_penalty` | `k=2.5`, `apply_standing_gate=True` |
| `yaw_err_abs_pen` | `0.0` | `waist_yaw_abs_penalty` | `upright_gate=0.0` |
| `yaw_progress` | `0.0` | `waist_yaw_progress_reward` | `err_gate=0.0`, `upright_gate=0.0`, `max_delta=0.20`, `apply_standing_gate=True` |

## 4) Core Raw Definitions

Conventions:
- `home_xy = env_origin_xy + (6.70, 0.0)`
- `center_xy = 0.5 * (left_foot_xy + right_foot_xy)`
- `ReLU(x) = max(x, 0)`
- `clamp(x, a, b)` clips to `[a, b]`

Regularization and stability:

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
- uses root-link angular velocity in world XY

`low_height_soft_penalty`
- `raw = ReLU(0.48 - base_height)^2`

`fallen`
- `height = root_link_pos_w[:, 2]`
- `tilt = ||projected_gravity_b[:, :2]||`
- `raw = 1` if `(height < 0.32) OR (tilt > 1.25)`, else `0`

Upright posture reward:

`upright`
- `sagittal = projected_gravity_b[:, 0]`
- `lateral = projected_gravity_b[:, 1]`
- `roll_error = ReLU(|lateral| - 0.10)`
- `roll_score = exp(-(roll_error^2) / 0.12^2)`
- `pitch_error = ReLU(|sagittal - 0.25| - 0.20)`
- `pitch_score = exp(-(pitch_error^2) / 0.30^2)`
- `raw = roll_score * pitch_score`

Home-point shaping:

`stance_center_home_x_abs_pen`
- `raw = |home_x - center_x|`

`stance_center_home_y_abs_pen`
- `raw = |home_y - center_y|`

`stance_center_home_axis_progress_reward`
- stateful previous absolute-error buffer per axis
- `err_abs = |home_axis - center_axis|`
- `effective_prev = err_abs` on the first active reward step, else the stored previous error
- `raw = clamp(effective_prev - err_abs, 0, max_delta)`
- standing gate is then applied for the configured active variants

`stance_center_move_toward_home`
- `to_home = home_xy - center_xy`
- `dist = ||to_home||`
- if `dist <= r_deadband`, direction is zeroed
- `v_center_xy = 0.5 * (v_left_foot_xy + v_right_foot_xy)`
- `toward_speed = dot(v_center_xy, dir_to_home)`
- `raw = clamp(toward_speed, 0, v_cap)`
- standing gate is then applied
- currently skipped because weight is `0.0`

Stance-shape terms:

Helper quantity:
- `stance_dir = normalize(right_foot_xy - left_foot_xy)`
- `ball_dir = normalize(ball_xy - center_xy)`
- `ortho_err = |dot(stance_dir, ball_dir)|`

Interpretation:
- `0` is perfect left-right stance orthogonal to the ball direction
- `1` is stance axis aligned with the ball direction

`stance_ortho_abs_pen`
- `raw = ortho_err`

`stance_ortho_progress`
- stateful previous `ortho_err` buffer
- `effective_prev = ortho_err` on the first active reward step, else the stored previous error
- `raw = clamp(effective_prev - ortho_err, 0, max_delta)`
- standing gate is then applied

`stance_width_band_pen`
- `width = ||right_foot_xy - left_foot_xy||`
- `raw = ReLU(w_min - width)^2 + ReLU(width - w_max)^2`

`pelvis_between_feet`
- compute pelvis offset in the support-frame coordinates
- `lateral_offset = dot(pelvis_offset, support_normal)`
- `longitudinal_offset = dot(pelvis_offset, support_dir)`
- current reward uses only the lateral component
- `lat_term = (lateral_offset / lateral_sigma)^2`
- `raw = exp(-lateral_weight * lat_term)`
- longitudinal offset is still logged, but it does not contribute to the reward anymore
- standing gate and home-alignment ramp are applied
- currently skipped because weight is `0.0`

Waist-orientation shaping:

`waist_ready_twist_abs_pen`
- computes the support-line normal that faces the same side as the ball
- defines a desired ready yaw from that normal
- `twist_err = wrap_to_pi(waist_yaw - desired_ready_yaw)`
- `raw = 1 - exp(-k * twist_err^2)`
- standing gate is applied, then the home-alignment ramp

`yaw_progress`
- tracks reduction in absolute waist yaw error to the current ball position
- `err_abs = |yaw_error|`
- `effective_prev = err_abs` on the first active reward step, else the stored previous error
- `prog_raw = effective_prev - err_abs`
- `progress = clamp(prog_raw, 0, max_delta)`
- explicit gates are applied before the standing gate:
  - require `err_abs > err_gate`
  - require `posture_score > upright_gate`
- current config uses `err_gate = 0.0` and `upright_gate = 0.0`
- standing gate is applied next, then the home-alignment ramp

`yaw_err_abs_pen`
- `raw = |yaw_error|` if `posture_score > upright_gate`, else `0`
- current config uses `upright_gate = 0.0`
- the home-alignment ramp is applied
- currently skipped because weight is `0.0`

## 5) Standing Gate and Home-Alignment Ramp

Standing gate is currently applied to:
- `stance_center_home_x_progress`
- `stance_center_home_y_progress`
- `stance_center_move_toward_home`
- `stance_ortho_progress`
- `pelvis_between_feet`
- `waist_ready_twist_abs_pen`
- `yaw_progress`

Active standing-gate constants from `_standing_gate(...)`:
- `h_low = 0.40`
- `h_good = 0.62`
- `roll_band = 0.10`
- `roll_sigma = 0.12`
- `pitch_target = 0.25`
- `pitch_band = 0.20`
- `pitch_sigma = 0.30`

Computation:
- `height_score = clamp((base_height - h_low) / (h_good - h_low), 0, 1)`
- `posture_score = upright-style posture score with the gate constants above`
- `stand_score = posture_score * height_score`
- `standing_gate = stand_score^2`

If a term enables `apply_standing_gate=True`, its raw reward is multiplied by this factor.

Separate home-alignment ramp used by orientation-sensitive terms:
- `home_x_err = |home_x - center_x|`
- `home_y_err = |home_y - center_y|`
- `alpha_x = clamp(1 - home_x_err / 0.30, 0, 1)`
- `alpha_y = clamp(1 - home_y_err / 0.25, 0, 1)`
- `align_mult = 0.2 + 0.8 * (alpha_x * alpha_y)`

This ramp is currently applied to:
- `waist_ready_twist_abs_pen`
- `yaw_progress`
- `yaw_err_abs_pen`
- `stance_ortho_abs_pen`
- `stance_ortho_progress`
- `pelvis_between_feet`
- `yaw_alignment_waist_reward`, if it is re-enabled later

## 6) Stateful Terms and First-Step Behavior

Per-environment state buffers are used by:
- `yaw_progress`
- `stance_center_home_axis_progress_reward`
- `stance_ortho_progress`

Current first-step behavior:
- E1 has no separate post-reset settle window
- `_reward_active_mask(...)` is always all-ones
- progress rewards treat `episode_length_buf <= 1` as the first active step

## 7) Reward-Adjacent Terminations

Configured terminations:
- `time_out`
- `nan_detection`
- `fallen` via `FallTermination(min_height=0.32, max_tilt=1.25, consecutive_steps=6)`

Important distinction:
- reward `fallen` is instantaneous
- termination `fallen` requires the same condition for `6` consecutive RL steps

Not currently configured:
- no hard out-of-area termination, even though helper code exists

## 8) Reward Logging

Current E1 reward code writes these reward-adjacent metrics into `extras["log"]`:
- `Metrics/e1_stand_score_mean`
- `Metrics/e1_stand_gate_mean`
- `Metrics/e1_height_score_mean`
- `Metrics/e1_base_height_mean`
- `Metrics/e1_roll_score_mean`
- `Metrics/e1_pitch_score_mean`
- `Metrics/e1_lateral_posture_component_mean`
- `Metrics/e1_sagittal_posture_component_mean`
- `Metrics/e1_align_home_ramp_mean`
- `Metrics/e1_home_x_err_for_align_mean`
- `Metrics/e1_home_y_err_for_align_mean`
- `Metrics/e1_waist_ready_twist_abs_err_mean`
- `Metrics/e1_waist_ready_twist_abs_pen_mean`
- `Metrics/e1_waist_yaw_abs_pen_raw_mean`
- `Metrics/e1_low_height_soft_pen_mean`
- `Metrics/e1_home_x_err_mean`
- `Metrics/e1_home_y_err_mean`
- `Metrics/e1_home_x_progress_mean`
- `Metrics/e1_home_y_progress_mean`
- `Metrics/e1_move_toward_home_mean`
- `Metrics/e1_stance_ortho_err_mean`
- `Metrics/e1_stance_ortho_progress_mean`
- `Metrics/e1_pelvis_between_feet_mean`
- `Metrics/e1_pelvis_between_feet_lateral_offset_mean`
- `Metrics/e1_pelvis_between_feet_longitudinal_offset_mean`
- `Metrics/e1_angular_momentum_mean`

Terms without dedicated extra logging in `mdp.py`:
- `action_rate_l2`
- `joint_pos_limits`
- `body_ang_vel`
- `stance_width_band_pen`
- `fallen`

## 9) Coupled Visualization Constant

`HOME_POINT_BAND_RADIUS = 0.20` is shared by:
- `stance_center_move_toward_home.r_deadband`
- `SetSquareCommandCfg.VizCfg.home_point_radius`

So the visual home-point radius and the movement-to-home deadband are intentionally coupled in the current implementation.
