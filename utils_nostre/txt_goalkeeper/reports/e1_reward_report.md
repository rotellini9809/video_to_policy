# E1 Reward Report (Current Implementation)

This report reflects the active E1 Set&Square task code in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/mdp.py`

## 1) Reward Terms Configured in E1

Per-step total reward is the weighted sum of active terms.

Training (`play=False`):
`R = 1.8*yaw_align_torso + 1.2*yaw_align_waist + 5.0*waist_yaw_progress - 1.2*waist_yaw_abs_pen - 0.10*foot_yaw_slip_contact_pen + 0.5*foot_contact_switch_bonus + 0.4*stance_ortho_to_ball + 1.0*upright - 0.05*twist_pen - 2.0*outside_area - 4.0*fallen`

Play (`play=True`):
`R = 1.8*yaw_align_torso + 1.2*yaw_align_waist + 5.0*waist_yaw_progress - 1.2*waist_yaw_abs_pen - 0.10*foot_yaw_slip_contact_pen + 0.5*foot_contact_switch_bonus + 0.4*stance_ortho_to_ball + 1.0*upright - 0.05*twist_pen - 2.0*outside_area - 8.0*fallen`

Disabled reward entries in config:
- `drift_deadzone`: `None` (inactive)
- `xy_speed_deadzone`: `None` (inactive)

## 2) Term-by-Term Definition

## 2.1 `yaw_align_torso` (weight `+1.8`)
Function:
- `yaw_alignment_torso_reward(..., k=2.5)`

Raw term:
- `exp(-k * yaw_err_torso^2)` with `k=2.5`
- `yaw_err_torso` is signed yaw-only angle between torso heading and ball direction in XY.

Range and effect:
- Raw range `(0, 1]`
- Weighted contribution `(0, 1.8]`
- Primary alignment objective: torso faces the ball.

## 2.2 `yaw_align_waist` (weight `+1.2`)
Function:
- `yaw_alignment_waist_reward(..., k=2.5)`

Raw term:
- `exp(-k * yaw_err_waist^2)` with `k=2.5`
- `yaw_err_waist` is signed yaw-only angle between Waist heading and ball direction in XY.

Range and effect:
- Raw range `(0, 1]`
- Weighted contribution `(0, 1.2]`
- Secondary whole-body/pelvis alignment objective.

## 2.3 `waist_yaw_progress` (weight `+5.0`)
Function:
- `waist_yaw_progress_reward(..., err_gate=0.25, upright_gate=0.80, max_delta=0.35)`

Raw term:
- `e = abs(yaw_err_waist)`
- Stateful buffer per env: `e_prev`
- First step handling: `effective_prev = e` when `episode_length_buf <= 1`
- `prog_raw = effective_prev - e`
- `prog = clamp(prog_raw, min=0.0, max=0.35)`
- `upright = exp(-(tilt^2) / tilt_sigma^2)`, `tilt_sigma=0.5`
- `mask = (upright > 0.80) & (e > 0.25)`
- `waist_yaw_progress = mask.float() * prog`

Range and effect:
- Raw range `[0, 0.35]` (after gating/clamp)
- Weighted contribution `[0, 1.75]`
- Rewards positive step-to-step reduction in waist yaw error when upright and meaningfully misaligned.

## 2.4 `waist_yaw_abs_pen` (weight `-1.2`)
Function:
- `waist_yaw_abs_penalty(..., upright_gate=0.85)`

Raw term:
- `err_abs = abs(yaw_err_waist)`
- `upright = exp(-(tilt^2) / tilt_sigma^2)`, `tilt_sigma=0.5`
- `waist_yaw_abs_pen = err_abs` when `upright > 0.85`, else `0`

Range and effect:
- Raw range `[0, +inf)`
- Weighted contribution `(-inf, 0]`
- Adds persistent pressure to reduce waist yaw error even when progress signal plateaus.

## 2.5 `foot_yaw_slip_contact_pen` (weight `-0.10`)
Function:
- `foot_yaw_slip_contact_pen(..., fz_thresh=40.0, support_sign="neg")`

Raw term:
- Left/right foot body ids resolved from:
  - `left_foot_body_name="^left_foot_link$"`
  - `right_foot_body_name="^right_foot_link$"`
- Support contact is force-thresholded (from contact sensors with net force):
  - `left_foot_ground_contact`, `right_foot_ground_contact`
  - with default sign convention `support_sign="neg"`:
    - `support = (fz < -fz_thresh)`, `fz_thresh=40.0`
  - fallback to `found > 0` if force is missing/non-finite
- Yaw slip proxy uses foot angular velocity around world z:
  - `slip_L = abs(body_link_ang_vel_w[left_foot, z])`
  - `slip_R = abs(body_link_ang_vel_w[right_foot, z])`
- `pen = 0.5 * (support_L * slip_L^2 + support_R * slip_R^2)`

Range and effect:
- Raw range `[0, +inf)` (non-negative penalty magnitude)
- Weighted contribution `(-inf, 0]`
- Penalizes yaw correction achieved by spinning feet while in contact.

## 2.6 `foot_contact_switch_bonus` (weight `+0.5`)
Function:
- `foot_contact_switch_bonus(..., upright_gate=0.85, err_gate=0.25, fz_thresh=40.0, support_sign="neg")`

Raw term:
- Stateful previous-contact buffers per env (`prev_contact_L`, `prev_contact_R`)
- First step handling uses current contacts to avoid reset artifact switch.
- `switch_L = xor(support_L, prev_support_L_eff)`
- `switch_R = xor(support_R, prev_support_R_eff)`
- `switch = (switch_L | switch_R).float()`
- Gating:
  - `upright > 0.85`
  - `abs(yaw_err_waist) > 0.25`
- `bonus = gate.float() * switch`

Range and effect:
- Raw range `{0, 1}`
- Weighted contribution `{0, 0.5}`
- Small exploration incentive for lift/replant contact transitions when correction is needed.

## 2.7 `stance_ortho_to_ball` (weight `+0.4`)
Function:
- `stance_ortho_to_ball_reward(...)`

Raw term:
- `s = normalize(pR_xy - pL_xy)` (stance axis)
- `b = normalize(ball_xy - root_xy)` (ball direction)
- `stance_ortho = 1 - (dot(s, b))^2`
- Gating in implementation:
  - `stance_width > 0.10`
  - `ball_dist > 0.35`
  - `neutral_when_mask_off=True`

Range and effect:
- Raw range `[0, 1]`
- Weighted contribution `[0, 0.4]`
- Encourages goalkeeper-squared stance with feet line orthogonal to ball direction.

## 2.8 `upright` (weight `+1.0`)
Function:
- `upright_stability_reward(...)`

Raw term:
- `upright = exp(-(tilt^2) / tilt_sigma^2)`, `tilt_sigma=0.5`
- `tilt = ||projected_gravity_b_xy||`
- Height component is currently disabled (tilt-only upright shaping).

Range and effect:
- Raw range `(0, 1]`
- Weighted contribution `(0, 1]`
- Encourages upright torso.

## 2.9 `drift_deadzone` (disabled)
Function:
- `xy_drift_deadzone(..., r_free=0.10)`

Effect:
- Implemented but inactive (`None` in reward config), so no reward contribution.
- `Episode_Reward/drift_deadzone` is not emitted.

## 2.10 `xy_speed_deadzone` (disabled)
Function:
- `xy_speed_deadzone(..., v_free=0.12)`

Effect:
- Implemented but inactive (`None` in reward config), so no reward contribution.
- `Episode_Reward/xy_speed_deadzone` is not emitted.

## 2.11 `twist_pen` (weight `-0.05`)
Function:
- `torso_waist_twist_penalty(...)`

Raw term:
- `twist = (yaw_err_torso - yaw_err_waist)^2`

Range and effect:
- Raw range `[0, +inf)`
- Weighted contribution `(-inf, 0]`
- Small penalty against excessive torso-waist yaw mismatch.

## 2.12 `outside_area` (weight `-2.0`)
Function:
- `outside_keeper_area_penalty`

Raw term:
- L1-style violation magnitude outside keeper bounds:
  - `x_low + x_high + y_low + y_high`, each clamped at zero.
- Bounds (env-local XY):
  - `x in [6.0, 7.5]`
  - `y in [-2.0, 2.0]`

Range and effect:
- Raw range `[0, +inf)`
- Weighted contribution `(-inf, 0]`
- Soft penalty outside allowed keeper area.

## 2.13 `fallen` (weight `-4.0` in training, `-8.0` in play)
Function:
- `fallen_indicator(min_height=0.32, max_tilt=1.25)`

Raw term:
- `1.0` if `(height < 0.32) OR (tilt > 1.25)`, else `0.0`

Range and effect:
- Raw range `{0, 1}`
- Weighted contribution `{0, -4}` in training, `{0, -8}` in play
- Large discrete per-step penalty in fallen states.

## 3) Logging Signals Added by Reward Terms

From waist shaping:
- `Metrics/e1_waist_yaw_abs_pen_raw_mean`

From foot-contact shaping:
- `Metrics/e1_foot_yaw_slip_contact_pen_raw_mean`
- `Metrics/e1_foot_contact_switch_bonus_raw_mean`
- `Metrics/e1_left_foot_fz_mean`, `Metrics/e1_right_foot_fz_mean`
- `Metrics/e1_left_foot_fz_min`, `Metrics/e1_left_foot_fz_max`
- `Metrics/e1_right_foot_fz_min`, `Metrics/e1_right_foot_fz_max`
- `Metrics/e1_left_foot_force_norm_mean`, `Metrics/e1_right_foot_force_norm_mean`
- `Metrics/e1_left_support_frac`, `Metrics/e1_right_support_frac`
- `Metrics/e1_support_switch_frac`
- `Metrics/e1_foot_contact_left_frac`
- `Metrics/e1_foot_contact_right_frac`
- `Metrics/e1_foot_contact_switch_frac`

## 4) Terminations That Interact with Reward

Configured terminations:
- `time_out` (episode timeout)
- `fallen` from `FallTermination` with `min_height=0.32`, `max_tilt=1.25`, `consecutive_steps=6`
- `out_of_area_hard` from `outside_keeper_area_hard`

Hard out-of-area bounds:
- Soft bounds expanded by margin `0.3`:
  - `x in [5.7, 7.8]`
  - `y in [-2.3, 2.3]`
- Episode terminates as soon as any violation is positive.

Important:
- Falling is both penalized by reward and used for early termination.

## 5) Spawn Randomization

- Keeper spawn XY (world frame before env origins):
  - `x in [6.8, 7.2]`
  - `y in [-0.6, 0.6]`
- Keeper spawn yaw:
  - `yaw in [pi - 75deg, pi + 75deg]` (±75 deg around facing-opposite-field baseline)
- Spawn z:
  - `z = 0.658`

## 6) Observation Vector Recap

Actor and critic use the same 9-term concatenated vector (shape `86`):
- `base_lin_vel` `(3,)`
- `base_ang_vel` `(3,)`
- `projected_gravity` `(3,)`
- `joint_pos` `(23,)`
- `joint_vel` `(23,)`
- `decoded_actions` `(23,)`
- `target_dir_xy` `(2,)`
- `ball_pos_rel_xyz` `(3,)`
- `ball_vel_rel_xyz` `(3,)`

## 7) Episode Timing Context

- Episode length is `4.0 s`.
- Base simulation timestep is `0.005 s`, with `decimation=4` (`step_dt=0.02 s`).

## 8) Practical Reading of the Current Reward Design

1. Alignment is driven by torso and waist yaw terms, with extra shaping for incremental waist-error reduction.
2. Foot mechanics are now shaped explicitly: contact-time yaw slip is penalized, while gated contact switching gets a small bonus.
3. Stance orthogonality shaping is active; drift deadzone and speed deadzone remain inactive.
4. Safety/role constraints are still enforced by area penalties/termination and fallen penalty/termination.
