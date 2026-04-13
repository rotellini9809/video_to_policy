# E2V2 Mezzaluna Reward Report

This document summarizes the current reward design for the `e2v2_mezzaluna` goalkeeper task.

Primary sources:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2v2_mezzaluna/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2v2_mezzaluna/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## Reward Model At A Glance

The task is a stand-block goalkeeper episode with three distinct phases:

1. Before contact: stay balanced, stay inside the keeper area, and prepare for the shot.
2. At first contact: prefer touches that redirect the ball away from goal, especially for high throws handled by the arms.
3. After contact: clear the danger zone, stabilize the body, and re-orient toward the ball.

Per control step:

`R_step = dt * sum_i (w_i * raw_i)`

Current timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 6.0`

Reward-manager behavior that matters here:
- each active term contributes `weight * raw * dt`
- NaN/Inf contributions are zeroed with `torch.nan_to_num(...)`
- `_step_reward` stores the unscaled reward rate `weight * raw`
- `Episode_Reward/*` logs are episodic sums normalized by episode length in seconds

## Current Weighted Reward Set

Current reward-rate expression:

`R_rate = -500.0*goal_conceded -0.005*action_rate_l2 +180.0*save_success +0.5*deflect_away +4.0*danger_reduction_on_first_contact_reward +6.0*arm_high_throw_deflect_reward +8.0*clearance_quality +2.0*stabilize_after_exit +0.0*face_ball_after_exit_reward -3.5*low_height_soft_penalty -0.35*joint_pos_limits +2.0*upright -0.01*body_ang_vel -6.0*head_contact_penalty -10.0*outside_area -90.0*fallen`

| Term | Weight | Type | Main role |
|---|---:|---|---|
| `goal_conceded` | `-500.0` | binary event | Large immediate failure signal if the ball enters the defended goal aperture |
| `action_rate_l2` | `-0.005` | dense penalty | Smooth control regularization |
| `save_success` | `+180.0` | binary event | Main positive outcome term after the post-contact resolution window ends without a goal |
| `deflect_away` | `+0.5` | first-contact event | Small directional bonus for sending the ball away from goal on keeper contact |
| `danger_reduction_on_first_contact_reward` | `+4.0` | delayed first-contact event | One-shot bridge reward for making the ball measurably less dangerous after first valid contact |
| `arm_high_throw_deflect_reward` | `+6.0` | first-contact event | Extra shaping for arm saves on high throws |
| `clearance_quality` | `+8.0` | latched event | Rewards fast, outward escape from the danger area after contact |
| `stabilize_after_exit` | `+2.0` | post-exit dense | Rewards standing quality after the ball has safely left the danger area |
| `face_ball_after_exit_reward` | `0.0` | post-exit dense | Currently configured off |
| `low_height_soft_penalty` | `-3.5` | dense penalty | Penalizes sagging base height before a full fall |
| `joint_pos_limits` | `-0.35` | dense penalty | Penalizes joint-limit pressure |
| `upright` | `+2.0` | dense reward | Encourages stable torso posture |
| `body_ang_vel` | `-0.01` | dense penalty | Penalizes root angular motion in roll/pitch axes |
| `head_contact_penalty` | `-6.0` | contact event | Discourages head-first saves |
| `outside_area` | `-10.0` | dense penalty | Penalizes leaving the keeper operating box |
| `fallen` | `-90.0` | binary indicator | Large per-step penalty when the robot is effectively down |

Current zero-weight reward term:
- `face_ball_after_exit_reward`

## Episode Logic That Shapes The Rewards

Several rewards only make sense because of the task's episode logic:

- `goal_conceded` is both a reward term and a termination.
- `contact_resolution_window` starts at the first keeper-ball contact and terminates the episode `1.5 s` later.
- `save_success` is evaluated against that resolution window, so it is effectively a post-contact outcome reward.
- `clearance_quality`, `stabilize_after_exit`, and `face_ball_after_exit_reward` are all driven by danger-area exit state, not by raw episode time.
- `fallen` has both a reward indicator and a separate termination with persistence, so the policy is punished immediately for bad posture and also terminated if it stays bad.

Current terminations:

| Termination | Trigger |
|---|---|
| `time_out` | episode length reached |
| `nan_detection` | invalid physics state |
| `goal_conceded` | ball crosses the defended goal aperture |
| `contact_resolution_window` | `1.5 s` elapsed since first keeper-ball contact |
| `fallen` | low height or excessive roll persists for `6` consecutive RL steps |

## Reward Terms By Phase

### 1. Pre-contact discipline

These terms are active regardless of whether contact has happened yet.

#### `action_rate_l2`

Purpose:
- discourage rapid control changes

Raw behavior:
- wraps the base action-rate L2 penalty from the environment MDP
- masked by the active command

#### `upright`

Purpose:
- keep the torso in a stable, slightly forward-leaning goalkeeper posture

Configuration:
- `roll_band = 0.10`
- `roll_sigma = 0.12`
- `pitch_target = 0.10`
- `pitch_band = 0.25`
- `pitch_sigma = 0.30`

Interpretation:
- lateral tilt is treated strictly
- sagittal posture is more tolerant and centered on a mild forward lean

#### `low_height_soft_penalty`

Purpose:
- penalize collapse before the hard fallen condition activates

Raw definition:
- `low = relu(h_soft - base_height)`
- `raw = low^2`

Current parameter:
- `h_soft = 0.55`

#### `joint_pos_limits`

Purpose:
- discourage operating near joint limits

Raw behavior:
- wraps the generic robot joint-limit penalty across all robot joints

#### `body_ang_vel`

Purpose:
- reduce root angular instability

Raw definition:
- sum of squared root angular velocity in the `x/y` axes

#### `outside_area`

Purpose:
- keep the goalkeeper inside its intended operating region in front of goal

Raw definition:
- compute squared distance outside the keeper-area bounds along `x` and `y`
- no penalty while inside the box

This is stronger than a soft centering cue: it only activates once the robot leaves the allowed area.

#### `fallen`

Purpose:
- heavily penalize states that are effectively unrecoverable for this task

Reward-side raw definition:
- `1.0` if either:
- base height `< 0.32`
- torso roll exceeds `100 deg`

This reward is immediate; termination is delayed by a persistence counter.

### 2. First-contact shaping

These terms are about the quality of the save itself, not just its final outcome.

#### `deflect_away`

Purpose:
- add a small positive bias toward sending the ball away from the goal immediately on contact

Current configuration:
- `only_on_first_contact = True`
- `clip_speed = 2.0`
- weight `= 0.5`

Raw definition for the defended `+x` goal:

`raw = clamp(-ball_vx, 0, clip_speed) * first_contact_mask`

Interpretation:
- only the first keeper-ball contact can trigger it
- only away-from-goal velocity matters
- the cap keeps this term small relative to the outcome rewards

#### `danger_reduction_on_first_contact_reward`

Purpose:
- provide a bridge reward between posture-only shaping and sparse save outcomes
- reward first contacts that make the shot materially less dangerous, even before the full save outcome is known

Current configuration:
- weight `= 4.0`
- `resolution_term_name = contact_resolution_window`
- `v_ref = 6.0`
- `min_forward_speed = 1.0`
- `projection_margin_y = 0.35`
- `projection_margin_z = 0.25`
- `post_contact_delay_steps = 2`

Core raw definition:

`raw = active_mask * clamp(danger_pre - danger_post, 0, 1)`

Danger score:

`danger = 0.5 * forward_speed_score + 0.3 * goal_projection_score + 0.2 * danger_area_score`

Behavior:
- it latches a pre-contact danger score only while the shot is actually threatening
- it reuses the same first-contact timing already used by `contact_resolution_window`
- it waits a few RL steps after contact before evaluating the post-contact danger
- it pays once per episode and then latches off
- repeated contacts cannot farm it

Threat gate used before arming:
- ball moving toward the defended goal
- minimum useful forward speed
- projected goal-plane crossing inside or near the goal aperture
- ball inside the relevant danger area

Why this is a bridge reward:
- unlike `deflect_away`, it is not just immediate X-velocity shaping
- unlike `save_success`, it does not wait for the end of the resolution window
- unlike `clearance_quality`, it does not require a full confirmed danger-area exit

So it answers a narrower question:
- did the first meaningful contact make the shot less dangerous shortly afterward?

Contact note:
- the reward no longer uses its own custom first-contact latch
- it keys off the already-working first-contact timestamp maintained by `contact_resolution_window`
- head touches are not separately suppressed in the current implementation

#### `arm_high_throw_deflect_reward`

Purpose:
- reward arm-based interventions on high shots that would otherwise be difficult to save cleanly

Current behavior:
- only active when the shot is classified as a high throw
- only pays on the first arm-contact event
- stronger deflection away from goal increases the reward through a saturated velocity factor

Raw structure:

`raw = high_throw_mask * first_arm_contact_mask * (0.2 + 0.8 * tanh(away_speed / 2.0))`

This is the most E2V2-specific reward term in the set. It explicitly promotes arm saves on elevated trajectories.

#### `head_contact_penalty`

Purpose:
- discourage saves that resolve through head contact

Raw definition:
- `1.0` on a new head-contact event, else `0.0`

This is event-based, not sustained. The intent is to suppress specific unsafe save strategies, not to punish lingering contact states repeatedly.

### 3. Post-contact outcome and clearance

These rewards evaluate whether contact actually turned into a usable save.

#### `save_success`

Purpose:
- provide the main sparse success reward for the episode

Raw definition:
- `1.0` when the `contact_resolution_window` termination fires and no goal has been conceded
- otherwise `0.0`

Important detail:
- this term uses `apply_standing_gate = False`
- success is therefore judged directly from the save outcome, not from a posture gate

#### `clearance_quality`

Purpose:
- reward fast and useful clearances, not just any touch

Internal logic:
- after first contact, track whether the ball exits the danger area
- require the ball to remain outside for `outside_steps_required = 2` RL steps
- when that exit is confirmed, reward the clearance once

Current parameters:
- `t_ref = 1.5`
- `t_clear_clip = 0.5`
- `clip_away_speed = 2.5`

Raw structure:

`raw = exit_event * time_factor * vel_factor`

where:
- `time_factor = clamp(1 - min(t_clear, t_clear_clip) / t_ref, 0, 1)`
- `vel_factor = clamp(v_away / clip_away_speed, 0, 1)`

Interpretation:
- earlier danger-zone exit is better
- stronger outward velocity is better
- the reward is event-like and latched, not paid every step forever

#### `stabilize_after_exit`

Purpose:
- encourage the robot to recover a useful stance after the ball is safely out

Active only when:
- the danger-area exit latch is active

Raw structure:

`raw = post_exit_active * (0.6*upright_score + 0.4*height_score - 0.30*stance_width_pen - 0.15*lin_speed_pen - 0.10*ang_speed_pen)`

Interpretation:
- upright posture and recovered base height are rewarded
- unstable foot spacing, translation, and angular motion are penalized

This makes the save look finished rather than chaotic.

#### `face_ball_after_exit_reward`

Purpose:
- re-orient the goalkeeper toward the live play after the clearance

Active only when:
- the post-exit latch is active

Current shaping:
- `deadband_deg = 12.0`
- `sigma_deg = 25.0`

Raw structure:
- compute the waist forward direction in world XY
- compare it to the waist-to-ball direction
- reward a Gaussian-like facing score after a small deadband

This is a recovery-and-readiness term, not a save term.

## Task Geometry That Directly Affects Rewards

### Defended goal aperture

The goal is treated as a plane at:
- `goal_plane_x = 7.0`
- `goal_plane_y in [-1.30, 1.30]`
- `goal_plane_z in [0.0, 1.85]`

Crossing this aperture triggers `goal_conceded`.

### Danger area used by clearance shaping

The clearance logic uses:
- `x in [4.7, 7.3]`
- `y in [-2.5, 2.5]`

The ball must leave this region and stay out briefly before the clearance is confirmed.

### Keeper area used by position discipline

The operating box for `outside_area` is:
- `x in [5.2, 7.6]`
- `y in [-2.0, 2.0]`

This penalty is about goalkeeper discipline, not ball safety.

## Launcher Context That Matters For Reward Interpretation

E2V2 uses its own mezzaluna reset and launcher curriculum.

Important current detail:
- all configured E2V2 launcher presets set `deflection_prob = 0.0`

So in the current task:
- "deflect" reward terms refer to the keeper's effect on the ball
- not to random launcher-side mid-flight deflections

Default preset if nothing overrides it:
- `e2v2_mezzaluna_stage1_ground_only`

That said, the report remains valid for later E2V2 presets because the reward table itself is defined independently from the family mix.

## Logged Diagnostics Worth Watching

Useful reward-adjacent metrics emitted by `mdp.py`:

### Clearance / post-contact
- `Metrics/e2_ball_in_danger_mean`
- `Metrics/e2_clearance_exit_event_mean`
- `Metrics/e2_clearance_exit_time_mean`
- `Metrics/e2_clearance_quality_raw_mean`
- `Metrics/e2_stabilize_after_exit_height_score_mean`
- `Metrics/e2_stabilize_after_exit_stance_width_mean`
- `Metrics/e2_stabilize_after_exit_stance_width_pen_mean`
- `Metrics/e2_face_ball_after_exit_yaw_err_mean`
- `Metrics/e2_face_ball_after_exit_score_mean`
- `Metrics/e2_face_ball_after_exit_raw_mean`

### Contact quality
- `Metrics/e2_high_throw_mask_mean`
- `Metrics/e2_first_arm_contact_event_mean`
- `Metrics/e2_arm_deflect_away_speed_mean`
- `Metrics/e2_arm_high_throw_deflect_raw_mean`
- `Metrics/e2_danger_pre_mean`
- `Metrics/e2_danger_post_mean`
- `Metrics/e2_danger_delta_mean`
- `Metrics/e2_danger_bridge_raw_mean`
- `Metrics/e2_head_contact_active_mean`
- `Metrics/e2_head_contact_event_mean`

### Posture / discipline
- `Metrics/e2_roll_score_mean`
- `Metrics/e2_pitch_score_mean`
- `Metrics/e2_lateral_posture_component_mean`
- `Metrics/e2_sagittal_posture_component_mean`
- `Metrics/e2_low_height_soft_pen_mean`
- `Metrics/e2_outside_area_penalty_mean`

## Practical Read

This reward set is still outcome-driven.

The strongest signals are:
- fail hard on conceding
- reward successful saves strongly
- punish falling and leaving the operating box

What E2V2 adds beyond plain E2 is not just another reward weight. It adds a more explicit save-quality hierarchy:
- small generic first-contact direction reward
- specialized high-throw arm reward
- explicit post-clear stabilization
- explicit post-clear facing recovery

So the intended policy is not merely "touch the ball somehow." The intended policy is:
- meet the shot from a stable stance
- prefer legal, outward redirections
- handle high throws with the arms when needed
- get the ball out of danger quickly
- recover into a goalkeeper-ready posture afterward

## Bottom Line

E2V2 is a staged goalkeeper reward:
- dense posture and discipline terms shape the approach
- event terms shape the quality of the save
- latched post-contact terms shape the quality of the clearance and recovery
- sparse win/loss terms still dominate the final objective

That makes it more behaviorally specific than the older E2 setup, especially on high-ball handling and post-save recovery.
