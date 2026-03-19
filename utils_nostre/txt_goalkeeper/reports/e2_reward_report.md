# E2 Reward Report (Current Implementation)

This report reflects the active E2 Stand Block task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## 1) Reward Terms Configured in E2

Per RL step, the environment reward is:

`R_step = dt * R_rate`

Current configured reward-rate expression:

`R_rate = -300*goal_conceded + 120*save_success + 40*deflect_away - 1.6*low_height_soft_penalty + 1.0*upright - 60*fallen`

Current E2 timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 2.0`

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

### 2.2 `save_success` (weight `+120`)
Function:
- `save_success_reward(..., resolution_term_name="contact_resolution_window", apply_standing_gate=True)`

Raw term:
- `1.0` only when:
  - `contact_resolution_window` termination is active for that step, and
  - goal is not conceded
- else `0.0`
- final raw is `success_indicator * standing_gate`

Effect:
- Gives sparse success credit at the end of the fixed post-contact resolution window.

### 2.3 `deflect_away` (weight `+40`)
Function:
- `deflect_away_from_goal_reward(..., only_on_first_contact=True)`

Raw term:
- On first keeper-ball contact only, compute away-from-goal X speed
- for the defended `+x` goal: `clamp(-v_x, 0, clip_speed)` with `clip_speed=4.0`
- multiplied by first-contact mask
- final raw is `away_speed_on_contact`

Effect:
- Rewards redirection quality at the first block contact.

### 2.4 `low_height_soft_penalty` (weight `-1.6`)
Function:
- `low_height_soft_penalty(h_soft=0.48)`

Raw term:
- `height = root_link_pos_w[:, 2]`
- `low = ReLU(0.48 - height)`
- `raw = low^2`

Effect:
- Penalizes crouching/collapse before the hard fallen condition triggers.

### 2.5 `upright` (weight `+1.0`)
Function:
- `upright_stability_reward`

Raw term:
- anisotropic posture score from body-frame projected gravity:
  - `sagittal = projected_gravity_b[:, 0]`
  - `lateral = projected_gravity_b[:, 1]`
  - `roll_error = ReLU(|lateral| - 0.1)`
  - `roll_score = exp(-(roll_error^2) / 0.12^2)`
  - `pitch_error = ReLU(|sagittal - 0.25| - 0.20)`
  - `pitch_score = exp(-(pitch_error^2) / 0.30^2)`
  - `raw = roll_score * pitch_score`

Effect:
- Rewards upright trunk posture continuously.

### 2.6 `fallen` (weight `-60`)
Function:
- `fallen_indicator(min_height=0.32, max_tilt=1.25)` via config override

Raw term:
- `1.0` if `(height < 0.32) OR (tilt > 1.25)`, else `0.0`

Effect:
- Strong per-step penalty for unstable or fallen poses.

## 3) Terminations That Interact With Reward

Configured terminations:
- `time_out`
- `goal_conceded`
- `contact_resolution_window` via `ContactResolutionTermination`
- `fallen` via `FallTermination(..., consecutive_steps=6)`

Not currently configured:
- no `outside_area` reward term
- no hard out-of-area termination

### Contact-resolution logic
- First keeper-ball contact is detected by sensor `ball_robot_contact`
- sensor match is ball geom `soccer_ball/ball_collision` vs robot subtree `Trunk`
- `t_contact` is latched once per env and then not overwritten
- termination fires when `t_now - t_contact >= 0.8 s`
- on reset, `t_contact` is restored to unset
- goal termination remains separate and immediate

## 4) Standing Gate on Sparse Rewards

Standing gate is applied to:
- `save_success`

Current implementation uses:
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
- the standing gate and visible `upright` reward now use the same posture constants
- both use `(roll_band=0.1, pitch_target=0.25, pitch_band=0.20)`

## 5) Visual / Area Constraints

Current E2 implementation still has:
- goal-plane overlay geometry in the field asset
- launcher status GUI markdown in the command panel

Removed from current implementation:
- no goal-cue sphere flash visual
- no outside-area reward term
- no out-of-area hard termination

## 6) Episode Timing Context

- Episode length is `2.0 s`
- sim `dt = 0.005 s`
- control decimation is `4`
- RL step `step_dt = 0.02 s`
- resolution window is `0.8 s` and is quantized at step resolution

## 7) Practical Reading of Current Reward Design

1. E2 is dominated by sparse outcome events: large fail (`goal_conceded`) and large success (`save_success`).
2. First-contact mechanics are explicitly incentivized through `deflect_away`, not long-horizon ball interaction.
3. Stability is shaped both continuously (`upright`) and through the standing gate on sparse task rewards, using the same posture target.
4. Area violations are no longer part of the reward or termination logic.
5. Collapse is discouraged by both `low_height_soft_penalty` and `fallen`.
