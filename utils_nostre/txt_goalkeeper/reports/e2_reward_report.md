# E2 Reward Report (Current Implementation)

This report reflects the active E2 Stand Block task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## 1) Reward Terms Configured in E2

Per RL step, the environment reward is:

`R_step = dt * R_rate`

Current configured reward-rate expression:

`R_rate = -300*goal_conceded - 0.008*action_rate_l2 + 120*save_success + 40*deflect_away + 20*clearance_quality - 1.6*low_height_soft_penalty - 0.5*joint_pos_limits + 1.0*upright - 4.0*outside_area - 60*fallen`

Current E2 timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 5.0`

Current `RewardManager` behavior:
- `compute()` multiplies each term by `weight * dt`
- `torch.nan_to_num(...)` is applied to each weighted term contribution before accumulation
- `_step_reward` stores the unscaled reward rate `weight * raw`, not the `dt`-scaled step reward
- `Episode_Reward/*` logs are episodic sums divided by `max_episode_length_s`
- terms with weight `0.0` are skipped at compute time

## 2) Term-by-Term Definition

### 2.1 `goal_conceded` (weight `-300`)
Function:
- `goal_conceded_indicator(...)`

Raw term:
- `1.0` if the ball crosses the defended goal plane aperture, else `0.0`

Goal plane used by reward/termination:
- defended side is `+x`
- `x >= 7.0`
- `|y - 0.0| <= 1.30`
- `z in [0.0, 1.85]`

Effect:
- Large immediate penalty on conceded goals.

### 2.2 `action_rate_l2` (weight `-0.008`)
Function:
- `action_rate_l2(command_name="stand_block")`

Raw term:
- base raw is `sum((action_t - action_{t-1})^2)` over the policy action vector
- implemented through the generic MDP reward helper
- current E2 wrapper applies an all-ones reward-active mask, so the term is effectively always on

Effect:
- Penalizes abrupt action changes and smooths the stand-block response.

### 2.3 `save_success` (weight `+120`)
Function:
- `save_success_reward(..., resolution_term_name="contact_resolution_window", apply_standing_gate=True)`

Raw term:
- `success = 1.0` only when:
  - `contact_resolution_window` termination is active for that step, and
  - goal is not conceded
- else `success = 0.0`
- final raw is `success * standing_gate`

Effect:
- Gives sparse success credit at the end of the fixed post-contact resolution window, but discounts it when the keeper is too low or poorly aligned.

### 2.4 `deflect_away` (weight `+40`)
Function:
- `deflect_away_from_goal_reward(..., only_on_first_contact=True)`

Raw term:
- on first keeper-ball contact only, compute away-from-goal X speed
- for the defended `+x` goal: `clamp(-v_x, 0, clip_speed)` with `clip_speed=4.0`
- final raw is `away_speed * first_contact_mask`
- current config does not apply the standing gate to this term

Effect:
- Rewards redirection quality at the first save contact.

### 2.5 `clearance_quality` (weight `+20`)
Function:
- `ClearanceQualityReward(command_name="stand_block")`

Raw term:
- uses the command danger area bounds:
  - `x in [5.2, 7.3]`
  - `y in [-2.5, 2.5]`
- after first contact has been latched by `contact_resolution_window`, tracks whether the ball exits that danger area
- requires the ball to stay outside for `outside_steps_required = 2` RL steps before rewarding
- reward is emitted once per episode
- current raw is:
  - `exit_event * time_factor * vel_factor`
  - `time_factor = clamp(1 - t_clear / 1.5, 0, 1)`
  - `vel_factor = clamp(v_away / 4.0, 0, 1)`
  - `t_clear = current_time - t_contact`
  - `v_away = clamp(-v_x, 0, 4.0)` for the defended `+x` goal

Effect:
- Rewards not just touching the ball, but clearing it out of the immediate danger zone quickly and with away-from-goal velocity.

### 2.6 `low_height_soft_penalty` (weight `-1.6`)
Function:
- `low_height_soft_penalty(h_soft=0.48)`

Raw term:
- `height = root_link_pos_w[:, 2]`
- `low = ReLU(0.48 - height)`
- `raw = low^2`

Effect:
- Penalizes crouching/collapse before the hard fallen condition triggers.

### 2.7 `joint_pos_limits` (weight `-0.5`)
Function:
- `joint_pos_limits(asset_cfg=SceneEntityCfg("robot", joint_names=(".*",)), command_name="stand_block")`

Raw term:
- uses the generic soft joint-limit penalty over all robot joints
- for each joint, accumulates violation beyond the configured soft lower/upper position limits
- current E2 wrapper applies an all-ones reward-active mask, so the term is effectively always on

Effect:
- Discourages using joint-end-range postures while blocking.

### 2.8 `upright` (weight `+1.0`)
Function:
- `upright_stability_reward`

Raw term:
- anisotropic posture score from body-frame projected gravity:
  - `sagittal = projected_gravity_b[:, 0]`
  - `lateral = projected_gravity_b[:, 1]`
  - `roll_error = ReLU(|lateral| - 0.1)`
  - `roll_score = exp(-(roll_error^2) / 0.12^2)`
  - `pitch_error = ReLU(|sagittal - 0.10| - 0.25)`
  - `pitch_score = exp(-(pitch_error^2) / 0.30^2)`
  - `raw = roll_score * pitch_score`

Effect:
- Rewards upright trunk posture continuously, with stricter lateral alignment than sagittal alignment.

### 2.9 `outside_area` (weight `-4.0`)
Function:
- `outside_area_penalty(command_name="stand_block")`

Raw term:
- keeper area bounds are:
  - `x in [6.0, 7.6]`
  - `y in [-2.0, 2.0]`
- compute base position in env-local XY
- measure distance outside the rectangular bounds:
  - `x_out = ReLU(x_min - x) + ReLU(x - x_max)`
  - `y_out = ReLU(y_min - y) + ReLU(y - y_max)`
- `raw = x_out^2 + y_out^2`

Effect:
- Softly penalizes drifting out of the intended keeper zone without terminating the episode.

### 2.10 `fallen` (weight `-60`)
Function:
- `fallen_indicator(min_height=0.32, max_tilt=1.25)` via config override

Raw term:
- `1.0` if `(height < 0.32) OR (tilt > 1.25)`, else `0.0`
- `tilt = norm(projected_gravity_b[:, :2])`

Effect:
- Strong per-step penalty for unstable or fallen poses.

## 3) Terminations That Interact With Reward

Configured terminations:
- `time_out`
- `goal_conceded`
- `contact_resolution_window` via `ContactResolutionTermination`
- `fallen` via `FallTermination(..., consecutive_steps=6)`

Not currently configured:
- no hard out-of-area termination

### Contact-resolution logic
- first keeper-ball contact is detected by sensor `ball_robot_contact`
- sensor match is ball geom `ball_collision` on entity `soccer_ball` vs robot subtree `Trunk`
- `t_contact` is latched once per env and then not overwritten
- termination fires when `t_now - t_contact >= 1.5 s`
- on reset, `t_contact` is restored to unset
- goal termination remains separate and immediate

### Fall-termination logic
- fallen state is based on the same thresholds used by the `fallen` reward term in config:
  - `height < 0.32` or `tilt > 1.25`
- termination requires this condition to persist for `6` consecutive RL steps

## 4) Standing Gate on Sparse Rewards

Standing gate is currently applied to:
- `save_success`

Current standing-gate constants:
- `h_low = 0.36`
- `h_good = 0.56`
- `roll_band = 0.1`
- `roll_sigma = 0.12`
- `pitch_target = 0.25`
- `pitch_band = 0.20`
- `pitch_sigma = 0.30`

Computation:
- `height_score = clamp((base_height - h_low)/(h_good - h_low), 0, 1)`
- `posture_score = posture(projected_gravity_b; 0.1, 0.12, 0.25, 0.20, 0.30)`
- `stand_score = posture_score * height_score`
- `standing_gate = stand_score`

Current relationship to `upright`:
- roll settings still match
- pitch settings do not match anymore
- `upright` uses `pitch_target = 0.10` and `pitch_band = 0.25`
- the sparse-reward standing gate uses `pitch_target = 0.25` and `pitch_band = 0.20`

## 5) Visual / Area Constraints

Current E2 implementation includes:
- goal-plane overlay geometry in the field asset
- danger-area overlay geometry in the field asset
- keeper-area overlay geometry in the field asset
- launcher status GUI markdown in the command panel

Area logic currently used by reward:
- danger area drives `clearance_quality`
- keeper area drives `outside_area`

Not currently configured:
- no hard out-of-area termination

## 6) Episode Timing Context

- Episode length is `5.0 s`
- sim `dt = 0.005 s`
- control decimation is `4`
- RL step `step_dt = 0.02 s`
- resolution window is `1.5 s` and is quantized at step resolution

## 7) Practical Reading of Current Reward Design

1. E2 is still dominated by sparse outcome events: large fail (`goal_conceded`) and large success (`save_success`).
2. First-contact block mechanics are rewarded directly through `deflect_away`.
3. Post-contact ball safety is now shaped explicitly through `clearance_quality`, which rewards clearing the ball out of the danger zone after contact.
4. Stability is shaped continuously by `upright`, `low_height_soft_penalty`, and `fallen`, while `save_success` is additionally filtered by the standing gate.
5. Keeper positioning discipline is now part of reward shaping through `outside_area`, but it is still not a termination condition.
6. Action smoothness and joint-end-range usage remain explicitly regularized through `action_rate_l2` and `joint_pos_limits`.
