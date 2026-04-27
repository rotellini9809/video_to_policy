# E2 Block Deflect Reward Report

This report reflects the current `e2_block_deflect` implementation in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_block_deflect/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_block_deflect/mdp.py`
- `mjlab/src/mjlab/managers/reward_manager.py`

## Reward Model

Per control step:

`R_step = dt * sum_i (w_i * raw_i)`

Current timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `dt = 0.02`
- `EPISODE_LENGTH_S = 6.0`

Current `RewardManager` behavior:
- each configured term contributes `weight * raw * dt`
- NaN/Inf contributions are zeroed with `torch.nan_to_num(...)`
- `_step_reward` stores the unscaled reward rate `weight * raw`
- episodic reward logs are normalized by episode length in seconds

Current zero-weight configured terms:
- `deflect_away`
- `clearance_quality`

## Task Context

This task is a stand-block goalkeeper episode with three broad phases:
- before contact: stay upright, stay inside the keeper area, and get ready for the shot
- at first contact: prefer contact that lowers shot danger, especially on high arm saves
- after contact: exit the danger zone, stabilize, and turn back toward the ball

Relevant constants from `env_cfgs.py`:
- danger area bounds: `x in [4.7, 7.3]`, `y in [-2.5, 2.5]`
- keeper area bounds: `x in [5.2, 7.6]`, `y in [-2.0, 2.0]`
- resolution window: `RESOLUTION_WINDOW_S = 3.0`
- upright target: `roll_band=0.10`, `roll_sigma=0.12`, `pitch_target=0.10`, `pitch_band=0.25`, `pitch_sigma=0.30`

Current launcher curriculum presets:
- stage 1: `e2_block_deflect_stage1_ground_only`
- stage 2: `e2_block_deflect_stage2_ground_long_driven`
- stage 3: `e2_block_deflect_stage3_long_driven_only`

Legacy preset aliases are still normalized to stage 2:
- `e2_block_deflect_stage1_ground`
- `e2_block_deflect_stage2_ground_air`

## Current Weighted Reward Set

Current reward-rate expression:

`R_rate = -500.0*goal_conceded -0.005*action_rate_l2 +180.0*save_success +0.0*deflect_away +4.0*danger_reduction_on_first_contact_reward +20.0*arm_high_throw_deflect_reward +0.0*clearance_quality +2.0*stabilize_after_exit +3.0*face_ball_after_exit_reward -3.5*low_height_soft_penalty -0.35*joint_pos_limits +2.0*upright -0.01*body_ang_vel -100.0*head_contact_penalty -10.0*outside_area -90.0*fallen`

| Term | Weight | Type | Main role |
|---|---:|---|---|
| `goal_conceded` | `-500.0` | binary event | Large failure signal if the ball enters the defended goal aperture |
| `action_rate_l2` | `-0.005` | dense penalty | Smooth control regularization |
| `save_success` | `+180.0` | binary event | Main positive outcome reward after the post-contact resolution window closes without a goal |
| `deflect_away` | `0.0` | first-contact event | Present but currently off |
| `danger_reduction_on_first_contact_reward` | `+4.0` | delayed first-contact event | Rewards first contacts that make the shot measurably less dangerous shortly afterward |
| `arm_high_throw_deflect_reward` | `+20.0` | first-contact event | Strong bonus for successful arm intervention on high throws |
| `clearance_quality` | `0.0` | latched event | Present but currently off |
| `stabilize_after_exit` | `+2.0` | post-exit dense | Rewards standing quality after the ball leaves the danger area |
| `face_ball_after_exit_reward` | `+3.0` | post-exit dense | Rewards turning back toward the ball after danger-area exit |
| `low_height_soft_penalty` | `-3.5` | dense penalty | Penalizes sagging base height before a hard fall |
| `joint_pos_limits` | `-0.35` | dense penalty | Penalizes joint-limit pressure |
| `upright` | `+2.0` | dense reward | Encourages stable torso posture |
| `body_ang_vel` | `-0.01` | dense penalty | Penalizes roll/pitch root angular velocity |
| `head_contact_penalty` | `-100.0` | contact event | Strongly discourages head-first saves |
| `outside_area` | `-10.0` | dense penalty | Penalizes leaving the keeper operating box |
| `fallen` | `-90.0` | binary indicator | Large per-step penalty when the robot is effectively down |

## Termination Logic That Shapes The Rewards

Current terminations:

| Termination | Trigger |
|---|---|
| `time_out` | episode length reached |
| `nan_detection` | invalid physics state |
| `goal_conceded` | ball crosses the defended goal aperture |
| `contact_resolution_window` | `3.0 s` elapsed since first keeper-ball contact |
| `fallen` | low height or excessive roll persists for `6` consecutive RL steps |

Important interactions:
- `goal_conceded` is both a reward term and a termination
- `save_success` is evaluated against the same resolution-window state, so it is effectively a post-contact outcome reward
- `stabilize_after_exit` and `face_ball_after_exit_reward` only become meaningful once the ball has confirmedly left the danger area after contact

## Raw Reward Notes

`goal_conceded`
- `raw = 1` when the projected ball state crosses the defended goal aperture, else `0`

`action_rate_l2`
- masked action-rate L2 penalty from the base environment

`save_success`
- pays once the resolution window ends without conceding a goal

`danger_reduction_on_first_contact_reward`
- one-shot bridge reward based on the drop in shot danger from shortly before first valid contact to shortly after it
- combines forward-speed, projected goal-crossing, and danger-area components

`arm_high_throw_deflect_reward`
- only active for high-throw families
- only pays on first arm contact
- stronger away-from-goal deflection gives a larger saturated bonus

`stabilize_after_exit`
- posture-and-height reward gated by confirmed danger-area exit

`face_ball_after_exit_reward`
- rewards yaw alignment back toward the ball after exit
- current stage scales are `0.0 / 1.0 / 1.0` for stages `1 / 2 / 3`

`low_height_soft_penalty`
- `raw = relu(0.55 - base_height)^2`

`joint_pos_limits`
- generic robot joint-limit pressure penalty

`upright`
- strict on lateral tilt, more tolerant in sagittal pitch

`body_ang_vel`
- sum of squared root angular velocity in the `x/y` axes

`head_contact_penalty`
- event reward: `1.0` on a new head-contact event, else `0.0`

`outside_area`
- squared distance outside the configured keeper-area bounds

`fallen`
- `raw = 1` if base height `< 0.32` or torso roll `> 100 deg`, else `0`

## Launcher Notes

This task uses only the local E2 launcher presets defined in the E2 task config, and preset selection resolves to the canonical stage names before launcher parameters are applied.
