# E1 Reward Report (Current Implementation)

This report reflects the current code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## 1) Reward Aggregation

Per RL step, the environment reward is:

`R_step = dt * sum_i (w_i * raw_i)`

Where:
- `raw_i` is the value returned by the reward term function.
- `w_i` is the configured reward weight.
- `dt` is the control-step duration because `RewardManager(scale_by_dt=True)` is the default behavior.

Current E1 timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 4.0`

Current `RewardManager` behavior:
- `compute()` multiplies each term by `weight * dt`.
- `torch.nan_to_num(...)` is applied to each weighted term contribution before accumulation.
- `_step_reward` stores the unscaled reward rate `weight * raw`, not the `dt`-scaled step reward.
- `Episode_Reward/*` logs are episodic sums divided by `max_episode_length_s`.
- Terms with weight `0.0` are skipped at compute time.

Current E1 has two zero-weight reward terms:
- `stance_center_move_toward_home`
- `yaw_align_waist`

## 2) E1 Reward Context

Relevant current constants from `env_cfgs.py`:
- home point: `(KEEPER_HOME_POINT_X, KEEPER_HOME_POINT_Y) = (6.75, 0.0)`
- soft keeper area: `x in [6.0, 7.5]`, `y in [-2.0, 2.0]`
- home-point deadband / viz radius: `HOME_POINT_BAND_RADIUS = 0.10`
- upright shaping:
  - `roll_band = 0.06981317007977318`
  - `roll_sigma = 0.12`
  - `pitch_target = 0.25`
  - `pitch_band = 0.15`
  - `pitch_sigma = 0.30`

Body-name settings used by stance rewards:
- left foot: `^left_foot_link$`
- right foot: `^right_foot_link$`
- waist: `(?i)^waist$`

Current reset behavior relevant to reward interpretation:
- E1 currently mixes reset poses with `P_READY = 0.5`:
  - `50%` ready pose
  - `50%` default pose

## 3) Active Reward Terms

Configured reward-rate expression:

`R_rate = -0.008*action_rate_l2 -0.005*angular_momentum -0.01*body_ang_vel -6.0*fallen -0.5*joint_pos_limits -1.6*low_height_soft_penalty -0.2*stance_center_home_x_abs_pen +0.3*stance_center_home_x_progress -0.7*stance_center_home_y_abs_pen +1.0*stance_center_home_y_progress +0.0*stance_center_move_toward_home -0.8*stance_ortho_abs_pen +1.0*stance_ortho_progress -0.3*stance_width_band_pen +0.15*pelvis_between_feet +1.0*upright -0.05*waist_ready_twist_abs_pen +0.0*yaw_err_abs_pen +0.2*yaw_progress`

| Name | Weight | Function | Current params |
|---|---:|---|---|
| `action_rate_l2` | `-0.008` | `action_rate_l2` | none |
| `angular_momentum` | `-0.005` | `angular_momentum_penalty` | `sensor_name=robot/root_angmom` |
| `body_ang_vel` | `-0.01` | `body_ang_vel_penalty` | none |
| `fallen` | `-6.0` | `fallen_indicator` | `min_height=0.32`, `max_tilt=1.25` |
| `joint_pos_limits` | `-0.5` | `joint_pos_limits` | all robot joints |
| `low_height_soft_penalty` | `-1.6` | `low_height_soft_penalty` | `h_soft=0.48` |
| `stance_center_home_x_abs_pen` | `-0.2` | `stance_center_home_axis_abs_penalty` | `axis=x` |
| `stance_center_home_x_progress` | `+0.3` | `stance_center_home_axis_progress_reward` | `axis=x`, `max_delta=0.12`, `apply_standing_gate=True` |
| `stance_center_home_y_abs_pen` | `-0.7` | `stance_center_home_axis_abs_penalty` | `axis=y` |
| `stance_center_home_y_progress` | `+1.0` | `stance_center_home_axis_progress_reward` | `axis=y`, `max_delta=0.2`, `apply_standing_gate=True` |
| `stance_center_move_toward_home` | `0.0` | `stance_center_move_toward_home_reward` | `r_deadband=0.10`, `v_cap=0.3`, `apply_standing_gate=True` |
| `stance_ortho_abs_pen` | `-0.8` | `stance_ortho_abs_penalty` | foot-body defaults |
| `stance_ortho_progress` | `+1.0` | `stance_ortho_progress_reward` | `max_delta=0.2`, `apply_standing_gate=True` |
| `stance_width_band_pen` | `-0.3` | `stance_width_band_penalty` | `w_min=0.23`, `w_max=0.45` |
| `pelvis_between_feet` | `+0.15` | `pelvis_between_feet_reward` | `waist_body_name=(?i)^waist$`, `apply_standing_gate=True` |
| `upright` | `+1.0` | `upright_stability_reward` | current upright constants above |
| `yaw_align_waist` | `0.0` | `yaw_alignment_waist_reward` | `k=2.5`, `apply_standing_gate=True` |
| `yaw_err_abs_pen` | `-0.1` | `waist_yaw_abs_penalty` | `upright_gate=0.0`; active posture defaults `tilt_target=0.0`, `tilt_band=-1.0`, `tilt_sigma=0.5` |
| `yaw_progress` | `+0.2` | `waist_yaw_progress_reward` | `err_gate=0.0`, `upright_gate=0.0`, `max_delta=0.2`, `apply_standing_gate=True`; active posture defaults `tilt_target=0.0`, `tilt_band=-1.0`, `tilt_sigma=0.5` |

## 4) Exact Raw Definitions

Conventions:
- `home_xy = env_origin_xy + (6.75, 0.0)`
- `center_xy = 0.5 * (left_foot_xy + right_foot_xy)`
- `ReLU(x) = max(x, 0)`
- `clamp(x, a, b)` clips to `[a, b]`
- `projected_gravity_b[:, 0]` is sagittal
- `projected_gravity_b[:, 1]` is lateral

### Regularization terms

`action_rate_l2`
- `raw = sum((a_t - a_{t-1})^2)`

`joint_pos_limits`
- `raw = sum_j [ (low_j - q_j)_+ + (q_j - high_j)_+ ]`

`body_ang_vel`
- `raw = wx^2 + wy^2`
- uses root-link angular velocity in world XY

`angular_momentum`
- `raw = ||L||^2`
- reads sensor `robot/root_angmom`
- if the sensor is missing, the function returns zeros

`low_height_soft_penalty`
- `raw = ReLU(h_soft - base_height)^2`
- current `h_soft = 0.48`

### Fall terms

`fallen`
- `height = root_link_pos_w[:, 2]`
- `tilt = ||projected_gravity_b[:, :2]||`
- `raw = 1` if `(height < 0.32) OR (tilt > 1.25)`, else `0`

### Upright posture and standing gate

Posture score components:
- `sagittal = projected_gravity_b[:, 0]`
- `lateral = projected_gravity_b[:, 1]`
- `roll_error = ReLU(|lateral| - roll_band)`
- `roll_score = exp(-(roll_error^2) / roll_sigma^2)`
- `pitch_error = ReLU(|sagittal - pitch_target| - pitch_band)`
- `pitch_score = exp(-(pitch_error^2) / pitch_sigma^2)`
- `posture_score = roll_score * pitch_score`

`upright`
- `raw = posture_score`
- there is no hard upright cutoff in this reward

`standing_gate`
- used only by terms with `apply_standing_gate=True`
- current helper defaults:
  - `h_low = 0.40`
  - `h_good = 0.62`
  - `s_min = 0.40`
  - `roll_band = 0.05`
  - `roll_sigma = 0.12`
  - `pitch_target = 0.10`
  - `pitch_band = 0.15`
  - `pitch_sigma = 0.30`
- computation:
  - `height_score = clamp((base_height - h_low)/(h_good - h_low), 0, 1)`
  - `stand_score = posture_score * height_score`
  - `gate_pre = clamp((stand_score - s_min)/(1 - s_min), 0, 1)`
  - `gate = gate_pre^2`
  - gated term output is `raw * gate`

Current gated terms:
- `yaw_align_waist`
- `yaw_progress`
- `stance_center_home_x_progress`
- `stance_center_home_y_progress`
- `stance_center_move_toward_home`
- `stance_ortho_progress`
- `pelvis_between_feet`

### Waist-yaw shaping

All three waist-yaw terms use the anatomical waist heading toward the current ball position.

`yaw_align_waist`
- `yaw_error = signed waist yaw error to the ball`
- `raw = exp(-k * yaw_error^2)`
- current `k = 2.5`
- standing gate is then applied

`yaw_err_abs_pen`
- posture/upright gate uses:
  - `band = max(tilt_band, 0.0)`
  - `sigma = max(tilt_sigma, 1e-6)`
  - `roll_error = ReLU(|projected_gravity_b[:, 1]| - band)`
  - `roll_score = exp(-(roll_error^2) / sigma^2)`
  - `pitch_error = ReLU(|projected_gravity_b[:, 0] - tilt_target| - band)`
  - `pitch_score = exp(-(pitch_error^2) / sigma^2)`
  - `posture_score = clamp_min(roll_score * pitch_score, finfo(dtype).tiny)`
- `raw = |yaw_error|` if `posture_score > upright_gate`, else `0`
- current E1 config passes `upright_gate = 0.0`

`yaw_progress`
- stateful previous absolute error buffer
- `err_abs = |yaw_error|`
- `effective_prev = err_abs` on first active reward step, otherwise previous stored error
- `prog_raw = effective_prev - err_abs`
- `progress = clamp(prog_raw, 0, max_delta)`
- current `max_delta = 0.2`
- explicit gates before standing gate:
  - error gate: require `err_abs > err_gate`
  - posture/upright gate: require `posture_score > upright_gate`
- `raw_pre_standing = progress` if both gates pass, else `0`
- standing gate is then applied if `apply_standing_gate=True`
- with current E1 config, `err_gate = 0.0` and `upright_gate = 0.0`

### Home-point shaping

`stance_center_home_x_abs_pen`
- `raw = |home_x - center_x|`
- this is now symmetric in x

`stance_center_home_y_abs_pen`
- `raw = |home_y - center_y|`

`stance_center_home_axis_progress_reward`
- used for both x and y variants
- `err_abs = |home_axis - center_axis|`
- stateful previous absolute-error buffer
- `effective_prev = err_abs` on first active reward step, otherwise previous stored error
- `raw = clamp(effective_prev - err_abs, 0, max_delta)`
- standing gate is then applied for the active variants
- current `max_delta`: x `0.12`, y `0.2`

`stance_center_move_toward_home`
- `to_home = home_xy - center_xy`
- `dist = ||to_home||`
- direction is active only when `dist > r_deadband`
- `v_center_xy = 0.5 * (v_left_foot_xy + v_right_foot_xy)`
- `toward_speed = dot(v_center_xy, dir_to_home)`
- `raw = clamp(toward_speed, 0, v_cap)`
- standing gate is then applied
- current `r_deadband = 0.10`, `v_cap = 0.3`

### Stance geometry shaping

Helper quantity used by the stance-orthogonality terms:
- `stance_dir = normalize(right_foot_xy - left_foot_xy)`
- `ball_dir = normalize(ball_xy - center_xy)`
- `ortho_err = |dot(stance_dir, ball_dir)|`

Important interpretation:
- `ortho_err = 0` is perfect left-right stance orthogonal to the ball direction
- `ortho_err = 1` is stance axis aligned with the ball direction

`stance_ortho_abs_pen`
- `raw = ortho_err`

`stance_ortho_progress`
- stateful previous `ortho_err` buffer
- `effective_prev = ortho_err` on first active reward step, otherwise previous stored error
- `raw = clamp(effective_prev - ortho_err, 0, max_delta)`
- current `max_delta = 0.2`
- standing gate is then applied

`stance_width_band_pen`
- `width = ||right_foot_xy - left_foot_xy||`
- `raw = ReLU(w_min - width)^2 + ReLU(width - w_max)^2`
- current `w_min = 0.23`
- current `w_max = 0.45`
- penalizes both too-narrow and too-wide stance widths

`pelvis_between_feet`
- `center_xy = 0.5 * (left_foot_xy + right_foot_xy)`
- `pelvis_xy = waist_body_xy`
- `support_dir = normalize(right_foot_xy - left_foot_xy)`
- `support_normal = (-support_dir_y, support_dir_x)`
- `pelvis_offset = pelvis_xy - center_xy`
- `longitudinal_offset = dot(pelvis_offset, support_dir)`
- `lateral_offset = dot(pelvis_offset, support_normal)`
- `lat_term = (lateral_offset / lateral_sigma)^2`
- `long_term = (longitudinal_offset / longitudinal_sigma)^2`
- `err = lateral_weight * lat_term + longitudinal_weight * long_term`
- `raw = exp(-err)`
- current defaults: `lateral_sigma = 0.09`, `longitudinal_sigma = 0.16`, `lateral_weight = 1.0`, `longitudinal_weight = 0.35`
- standing gate is then applied, followed by the home-alignment ramp

## 5) Stateful Terms and First-Step Behavior

Per-environment state buffers are used by:
- `yaw_progress`
- `stance_center_home_axis_progress_reward`
- `stance_ortho_progress`

Current first-step behavior:
- E1 no longer uses any post-reset settle window or reward-masking phase.
- progress terms use `episode_length_buf <= 1` as the first-step condition.

## 6) Reward-Related Logging

Current reward code emits the following `extras["log"]` metrics:
- `Metrics/e1_stand_score_mean`
- `Metrics/e1_stand_gate_mean`
- `Metrics/e1_height_score_mean`
- `Metrics/e1_base_height_mean`
- `Metrics/e1_roll_score_mean`
- `Metrics/e1_pitch_score_mean`
- `Metrics/e1_lateral_posture_component_mean`
- `Metrics/e1_sagittal_posture_component_mean`
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

Notes:
- `fallen`, `body_ang_vel`, and `stance_width_band_pen` do not currently emit dedicated reward logs from `mdp.py`.
- `stance_center_move_toward_home` and `yaw_align_waist` are configured but currently skipped by reward computation because their weights are `0.0`.
- the standing-gate metrics are written by `_standing_gate()`, so they are refreshed whenever any gated term is evaluated.

## 7) Reward-Adjacent Terminations

Configured terminations:
- `time_out`
- `fallen` via `FallTermination(min_height=0.32, max_tilt=1.25, consecutive_steps=6)`

Important distinction:
- reward `fallen` is an instantaneous indicator
- termination `fallen` requires the fallen condition to persist for 6 consecutive steps

`out_of_area_hard` is not currently configured as an E1 termination.

## 8) Home-Point Band Coupling

`HOME_POINT_BAND_RADIUS = 0.10` is shared by:
- `stance_center_move_toward_home.r_deadband`
- `SetSquareCommandCfg.VizCfg.home_point_radius`

So the visual home-point cue radius and the movement-to-home reward deadband are intentionally coupled in the current implementation.
