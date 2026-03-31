# E2 Reward Report (Current Implementation)

This report reflects the active E2 Stand Block task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## 1) Reward Aggregation

Per RL step:

`R_step = dt * sum_i (w_i * raw_i)`

Current timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 6.0`

Current `RewardManager` behavior:
- `compute()` multiplies each term by `weight * dt`
- `torch.nan_to_num(...)` is applied to each weighted contribution before accumulation
- `_step_reward` stores the unscaled reward rate `weight * raw`, not the `dt`-scaled step reward
- `Episode_Reward/*` logs are episodic sums divided by `max_episode_length_s`
- terms with weight `0.0` are skipped at compute time

Current zero-weight configured term:
- `deflect_away`

## 2) Active E2 Reward Terms

Current configured reward-rate expression:

`R_rate = -500.0*goal_conceded -0.005*action_rate_l2 +180.0*save_success +0.0*deflect_away +8.0*clearance_quality +2.5*stabilize_after_exit -3.0*low_height_soft_penalty -0.35*joint_pos_limits +2.0*upright -0.01*body_ang_vel -10.0*outside_area -90.0*fallen`

| Name | Weight | Function | Active params |
|---|---:|---|---|
| `goal_conceded` | `-500.0` | `goal_conceded_indicator` | `command_name=stand_block` |
| `action_rate_l2` | `-0.005` | `action_rate_l2` | `command_name=stand_block` |
| `save_success` | `+180.0` | `save_success_reward` | `resolution_term_name=contact_resolution_window`, `apply_standing_gate=False` |
| `deflect_away` | `0.0` | `deflect_away_from_goal_reward` | `only_on_first_contact=True` |
| `clearance_quality` | `+8.0` | `ClearanceQualityReward` | `t_clear_clip=0.5`, `clip_away_speed=2.5` |
| `stabilize_after_exit` | `+2.5` | `StabilizeAfterExitReward` | default stabilization params |
| `low_height_soft_penalty` | `-3.0` | `low_height_soft_penalty` | `h_soft=0.48` |
| `joint_pos_limits` | `-0.35` | `joint_pos_limits` | all robot joints |
| `upright` | `+2.0` | `upright_stability_reward` | `roll_band=0.10`, `roll_sigma=0.12`, `pitch_target=0.10`, `pitch_band=0.25`, `pitch_sigma=0.30` |
| `body_ang_vel` | `-0.01` | `body_ang_vel_penalty` | `command_name=stand_block` |
| `outside_area` | `-10.0` | `outside_area_penalty` | `command_name=stand_block` |
| `fallen` | `-90.0` | `fallen_indicator` | `min_height=0.32`, `max_tilt=1.25` |

## 3) Active Spatial and Timing Constants

Goal-plane aperture used by active E2 reward and termination:
- defended side is `+x`
- `goal_plane_x = 7.0`
- `goal_plane_y_center = 0.0`
- `goal_plane_y_half = 1.30`
- `goal_plane_z_min = 0.0`
- `goal_plane_z_max = 1.85`

Danger area used by clearance shaping:
- `x in [5.2, 7.3]`
- `y in [-2.5, 2.5]`

Keeper area used by `outside_area`:
- `x in [6.0, 7.6]`
- `y in [-2.0, 2.0]`

Other reward-adjacent constants:
- resolution window: `1.5 s`
- keeper spawn band: centered around E1 home point `(6.75, 0.0)` with radius `0.10`
- spawn yaw offset range: `[-0.1, 0.1]`

## 4) Term-by-Term Raw Definitions

`goal_conceded`
- `raw = 1.0` if the ball crosses the defended goal-plane aperture, else `0.0`
- this is also a termination condition

`action_rate_l2`
- base raw is `sum((action_t - action_{t-1})^2)`
- the E2 wrapper applies `_reward_active_mask(...)`
- current `_reward_active_mask(...)` is always all-ones, so this behaves like the base reward

`save_success`
- `resolution_done = termination_manager.get_term("contact_resolution_window")`
- `goal = goal_conceded_mask`
- `success = 1.0` only when the fixed post-contact resolution window ends and no goal was conceded
- final raw is just `success`

`deflect_away`
- on first keeper-ball contact only, compute away-from-goal X speed
- for the defended `+x` goal: `away_speed = clamp(-v_x, 0, clip_speed)`
- default `clip_speed = 4.0`
- raw is `away_speed * first_contact_mask`
- currently skipped because weight is `0.0`

`clearance_quality`
- after first contact, tracks whether the ball leaves the configured danger area
- requires the ball to stay outside for `outside_steps_required = 2` RL steps before confirming exit
- reward is emitted once per episode
- current raw is:
  - `exit_event * time_factor * vel_factor`
  - `t_clear = clamp(t_now - t_contact, min=0)`
  - `t_clear_reward = clamp(t_clear, max=0.5)`
  - `time_factor = clamp(1 - t_clear_reward / 1.5, 0, 1)`
  - `v_away = clamp(-v_x, 0, 2.5)` for the defended `+x` goal
  - `vel_factor = clamp(v_away / 2.5, 0, 1)`

`stabilize_after_exit`
- becomes active only after the same confirmed danger-area exit logic has latched a post-exit phase
- raw is:
  - `0.6 * upright_score`
  - `+ 0.4 * height_score`
  - `- 0.20 * stance_width_pen`
  - `- 0.15 * lin_speed_pen`
  - `- 0.10 * ang_speed_pen`
- where:
  - `height_score = clamp((base_height - 0.40) / (0.58 - 0.40), 0, 1)`
  - `stance_width_pen = ReLU(0.23 - stance_width)^2 + ReLU(stance_width - 0.45)^2`
  - `lin_speed_pen = vx^2 + vy^2`
  - `ang_speed_pen = wx^2 + wy^2 + 1.5 * wz^2`
- the posture part of this term uses its own defaults:
  - `roll_band = 0.10`
  - `roll_sigma = 0.12`
  - `pitch_target = 0.25`
  - `pitch_band = 0.20`
  - `pitch_sigma = 0.30`

`low_height_soft_penalty`
- `raw = ReLU(0.48 - base_height)^2`

`joint_pos_limits`
- generic soft position-limit violation sum over all robot joints
- wrapper is active but currently equivalent to the base reward because `_reward_active_mask(...)` is always true

`upright`
- anisotropic posture score from body-frame projected gravity:
  - `roll_error = ReLU(|lateral| - 0.10)`
  - `roll_score = exp(-(roll_error^2) / 0.12^2)`
  - `pitch_error = ReLU(|sagittal - 0.10| - 0.25)`
  - `pitch_score = exp(-(pitch_error^2) / 0.30^2)`
  - `raw = roll_score * pitch_score`

`body_ang_vel`
- `raw = wx^2 + wy^2`
- uses root-link angular velocity in world XY

`outside_area`
- compute keeper base position in env-local XY
- `x_out = ReLU(x_min - x) + ReLU(x - x_max)`
- `y_out = ReLU(y_min - y) + ReLU(y - y_max)`
- `raw = x_out^2 + y_out^2`

`fallen`
- `height = root_link_pos_w[:, 2]`
- `tilt = ||projected_gravity_b[:, :2]||`
- `raw = 1.0` if `(height < 0.32) OR (tilt > 1.25)`, else `0.0`

## 5) Sparse Reward Gating and Exit Logic

No active E2 reward term currently enables the standing gate in `env_cfgs.py`.

Active standing-gate constants from `_standing_gate(...)`:
- `h_low = 0.36`
- `h_good = 0.56`
- `roll_band = 0.10`
- `roll_sigma = 0.12`
- `pitch_target = 0.25`
- `pitch_band = 0.20`
- `pitch_sigma = 0.30`

Computation:
- `height_score = clamp((base_height - h_low) / (h_good - h_low), 0, 1)`
- `posture_score = posture(projected_gravity_b; 0.10, 0.12, 0.25, 0.20, 0.30)`
- `standing_gate = posture_score * height_score`

If a term enables `apply_standing_gate=True`, its raw reward is multiplied by this factor.

Current relationship to the main `upright` term:
- roll settings match
- pitch settings do not match
- `upright` uses `pitch_target = 0.10`, `pitch_band = 0.25`
- the sparse-reward standing gate still uses `pitch_target = 0.25`, `pitch_band = 0.20`

Confirmed danger-area exit behavior used by `clearance_quality` and `stabilize_after_exit`:
- first contact time is latched once by `ContactResolutionTermination`
- exit is only confirmed after the ball remains outside the danger area for `2` RL steps
- both reward classes maintain their own internal exit latch state, but they implement the same confirmation rule

## 6) Reward-Adjacent Terminations

Configured terminations:
- `time_out`
- `nan_detection`
- `goal_conceded`
- `contact_resolution_window`
- `fallen`

Goal termination:
- immediate once the goal-plane aperture is crossed

Contact-resolution termination:
- first keeper-ball contact is detected using sensor `ball_robot_contact`
- first contact time `t_contact` is latched once per env
- termination fires when `t_now - t_contact >= 1.5 s`

Fall termination:
- uses the same thresholds as the `fallen` reward term in config:
  - `height < 0.32` or `tilt > 1.25`
- termination requires the condition for `6` consecutive RL steps

Not currently configured:
- no hard out-of-area termination

## 7) Logging and Practical Reading

Current E2 reward code logs these reward-adjacent metrics into `extras["log"]`:
- `Metrics/e2_ball_in_danger_mean`
- `Metrics/e2_clearance_exit_event_mean`
- `Metrics/e2_clearance_exit_time_mean`
- `Metrics/e2_clearance_quality_raw_mean`
- `Metrics/e2_stabilize_after_exit_height_score_mean`
- `Metrics/e2_stabilize_after_exit_stance_width_mean`
- `Metrics/e2_stabilize_after_exit_stance_width_pen_mean`
- `Metrics/e2_roll_score_mean`
- `Metrics/e2_pitch_score_mean`
- `Metrics/e2_lateral_posture_component_mean`
- `Metrics/e2_sagittal_posture_component_mean`
- `Metrics/e2_low_height_soft_pen_mean`
- `Metrics/e2_outside_area_penalty_mean`

Standing-gate metrics are not currently emitted because no active E2 reward term calls `_standing_gate(...)`.

Current practical interpretation:
1. E2 is still dominated by sparse outcome terms: very large fail on `goal_conceded` and very large success on `save_success`.
2. `deflect_away` is implemented but currently disabled with weight `0.0`.
3. Post-contact ball safety is shaped by `clearance_quality`, and post-clear stabilization is shaped by `stabilize_after_exit`.
4. Continuous pose discipline is enforced by `upright`, `low_height_soft_penalty`, `body_ang_vel`, `outside_area`, and `fallen`.
5. Action smoothness and joint-limit use remain explicitly regularized through `action_rate_l2` and `joint_pos_limits`.
