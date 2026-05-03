# E2 From Efin Snapshots Reward Report

This report reflects the current `e2_from_efin_snapshots` implementation in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_from_efin_snapshots/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/efin_continuous_goalkeeper/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## Short Description

`Mjlab-GK-Expert-E2-FromEfinSnapshots-Booster-T1_23` trains an E2-style goalkeeper from saved Efin handoff states. Each episode resets from a snapshot captured when Efin enters `approach_danger`, then continues with Efin's `continuous_ball` dynamics while using E2-style save, clearance, posture, and safety rewards.

The reward intent is to make the policy finish the handoff: block the incoming ball, avoid conceded goals and unsafe contacts, clear the ball out of the danger window, and recover into a stable keeper posture. The strongest signal is the discrete save/goal outcome; smaller shaping terms guide body posture, clearance direction, and post-clearance behavior.

## Reward Model

Per control step:

`R_step = dt * sum_i (w_i * raw_i)`

Current timing inherited from the Efin continuous goalkeeper task:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 17.0`

Current `RewardManager` behavior:
- each configured term contributes `weight * raw * dt`
- NaN/Inf contributions are zeroed with `torch.nan_to_num(...)`
- `_step_reward` stores the unscaled reward rate `weight * raw`
- episodic reward logs are normalized by episode length in seconds

Current zero-weight configured terms:
- none

## Task Context

This task starts from Efin approach snapshots rather than from the beginning of the whole goalkeeper sequence. The policy sees the same actor observation/action interface as the goalkeeper expert stack, but the reset state is already near the danger handoff.

Relevant constants:
- clearance danger window: `x in [5.05, 7.15]`, `y in [-2.7, 2.7]`
- outside-area bounds: `x in [5.2, 6.8]`, `y in [-2.3, 2.3]`
- outside-area visual cue: `efin_snapshot_outside_area_overlay`, drawn in viewer group `3` with the Efin keeper spawn overlay
- post-contact outcome window: `RESOLUTION_WINDOW_S = 3.0`
- fall indicator: base height `< 0.32` or absolute roll `> 100 deg`

## Current Weighted Reward Set

Current reward-rate expression:

`R_rate = -350.0*goal_conceded -0.005*action_rate_l2 +300.0*save_success +8.0*deflect_away +20.0*arm_contact_on_high_shot +5.0*clearance_quality +2.0*stabilize_after_exit +3.0*face_ball_after_exit -3.5*low_height_soft_penalty -0.35*joint_pos_limits +2.0*upright -0.01*body_ang_vel -100.0*head_contact_penalty -70.0*outside_keeper_area -70.0*fallen`

| Term | Weight | Type | Main role |
|---|---:|---|---|
| `goal_conceded` | `-350.0` | binary event | Large failure signal when the ball enters the defended goal |
| `action_rate_l2` | `-0.005` | dense penalty | Smooth control regularization on latent actions |
| `save_success` | `+300.0` | binary event | Main positive outcome reward when the post-contact outcome window finishes without a conceded goal, or when `fallen` fires after first ball contact without a conceded goal |
| `deflect_away` | `+8.0` | first-contact event | Rewards first-contact ball XY velocity projected away from the goal center, clipped at `1.0 m/s` |
| `arm_contact_on_high_shot` | `+20.0` | contact event | Bonus for useful arm-ball contact when `shot_target_z >= 0.45` |
| `clearance_quality` | `+5.0` | latched event | Small one-shot reward for clearing the ball out of the danger window with velocity away from goal |
| `stabilize_after_exit` | `+2.0` | post-exit dense | After danger-window exit, rewards upright posture and healthy base height |
| `face_ball_after_exit` | `+3.0` | post-exit dense | After danger-window exit, rewards turning back toward the ball |
| `low_height_soft_penalty` | `-3.5` | dense penalty | Penalizes sagging below `h_soft = 0.55` |
| `joint_pos_limits` | `-0.35` | dense penalty | Penalizes joint-limit pressure |
| `upright` | `+2.0` | dense reward | Continuous torso roll/pitch posture shaping |
| `body_ang_vel` | `-0.01` | dense penalty | Penalizes large root angular velocity |
| `head_contact_penalty` | `-100.0` | contact event | Strongly discourages head contact with the ball |
| `outside_keeper_area` | `-70.0` | dense penalty | Penalizes leaving the Efin keeper spawn area |
| `fallen` | `-70.0` | binary indicator | Large per-step penalty when the robot is effectively down |

## Clearance Quality

`clearance_quality` is a one-shot post-contact reward.

Trigger:
- the robot has contacted the ball
- the ball was in the danger window before
- the ball becomes outside the danger window for `2` consecutive steps

Raw value:

`raw = exit_event * time_factor * vel_factor`

Velocity factor:

`vel_factor = clamp(v_away / 2.5, 0, 1)`

Examples:
- `0.0 m/s` away from goal gives `0.0`
- `1.25 m/s` away from goal gives `0.5`
- `2.5 m/s` or faster away from goal gives `1.0`

Time factor:

`time_factor = 1 - min(t_clear, 0.5) / 1.5`

With `t_clear_clip = 0.5` and default `t_ref = 1.5`:
- immediate exit gives about `1.0`
- exit after `0.25s` gives about `0.83`
- exit after `0.5s` or more gives about `0.67`

Weighted contribution:

`clearance_quality_reward = 5.0 * raw * dt`

## Post-Exit Shaping

The post-exit latch activates only after the ball exits the danger window after robot contact.

`stabilize_after_exit`:

`raw = post_exit_active * (0.6*upright_score + 0.4*height_score)`

This term does not penalize body linear or angular speed.

`face_ball_after_exit`:
- active only after danger-window exit
- full score inside a `12 deg` yaw deadband
- decays with `sigma = 25 deg` outside the deadband

## Termination Logic That Shapes The Rewards

Current terminations:
- `time_out`
- `nan_detection`
- `goal_conceded`
- `outside_field`
- `post_contact_outcome_window`
- `fallen`

`post_contact_outcome_window` is the key save-success termination: after robot-ball contact, the episode waits up to the resolution window and then decides whether the save succeeded or the goal was conceded.
