# E2 Reward Report (Current Implementation)

This report reflects the active E2 Stand Block / Deflect task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/mdp.py`

## 1) Reward Terms Configured in E2

Per-step total reward is the weighted sum:

`R = -300*goal_conceded + 120*save_success + 40*deflect_away - 15*outside_area - 60*fallen`

## 2) Term-by-Term Definition

## 2.1 `goal_conceded` (weight `-300`)
Function:
- `goal_conceded_indicator`

Raw term:
- `1.0` if ball crosses E2 goal plane aperture, else `0.0`.

Goal plane used by reward/termination:
- `x >= 7.0` (defended side is `+x`)
- `|y - 0.0| <= 1.30`
- `z in [0.0, 1.85]`

Effect:
- Large immediate penalty on conceded goals.

## 2.2 `save_success` (weight `+120`)
Function:
- `save_success_reward(..., resolution_term_name="contact_resolution_window")`

Raw term:
- `1.0` only when:
  - `contact_resolution_window` termination is active for that step, and
  - goal is not conceded.
- Else `0.0`.

Effect:
- Gives sparse success credit at the end of the fixed post-contact resolution window.

## 2.3 `deflect_away` (weight `+40`)
Function:
- `deflect_away_from_goal_reward(..., only_on_first_contact=True)`

Raw term:
- On first keeper-ball contact only, compute away-from-goal X speed:
  - for `+x` defended goal: `clamp(-v_x, 0, clip_speed)` with `clip_speed=4.0`.
- Multiplied by first-contact mask.

Effect:
- Rewards redirection quality at the first block contact.

## 2.4 `outside_area` (weight `-15`)
Function:
- `outside_keeper_area_penalty`

Raw term:
- L1 violation outside keeper bounds:
  - bounds `x in [6.0, 7.6]`, `y in [-2.0, 2.0]`
  - violation `x_low + x_high + y_low + y_high`.

Effect:
- Penalizes leaving the designated keeper working area.

## 2.5 `fallen` (weight `-60`)
Function:
- `fallen_indicator(min_height=0.32, max_tilt=1.25)`

Raw term:
- `1.0` if `(height < 0.32) OR (tilt > 1.25)`, else `0.0`.

Effect:
- Strong per-step penalty for unstable/fallen poses.

## 3) Terminations That Interact with Reward

Configured terminations:
- `time_out`
- `goal_conceded` (immediate fail)
- `contact_resolution_window` via `ContactResolutionTermination`
- `fallen` via `FallTermination(..., consecutive_steps=6)`
- `out_of_area_hard`

Hard out-of-area bounds:
- Soft keeper bounds expanded by `0.35`:
  - `x in [5.65, 7.95]`
  - `y in [-2.35, 2.35]`

### Contact-resolution logic (E2 specific)
- First keeper-ball contact is detected by sensor `ball_robot_contact`.
- Sensor match is ball geom `soccer_ball/ball_collision` vs robot subtree `Trunk`.
- `t_contact` is latched once per env and then never overwritten.
- Termination fires when `t_now - t_contact >= 0.8 s`.
- On reset, `t_contact` is set back to `-1.0` (unset).
- Goal termination remains separate and immediate.

## 4) Episode Timing Context

- Episode length is `1.2 s`.
- Sim `dt=0.005 s`, `decimation=4`, RL step `step_dt=0.02 s`.
- Resolution window is `0.8 s` and therefore quantized at step resolution.

## 5) Practical Reading of Current Reward Design

1. E2 is dominated by outcome events: large fail (`goal_conceded`) and large success (`save_success`).
2. First-contact mechanics are explicitly incentivized (`deflect_away`) instead of prolonged interaction.
3. Stability and task envelope are enforced via `fallen` and `outside_area` penalties plus hard terminations.
