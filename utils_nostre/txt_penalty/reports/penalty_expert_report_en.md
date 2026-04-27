# Penalty Expert Report - Booster T1_23

## Purpose of the document
This report describes the **penalty shot** expert for the **Booster T1 23-DoF** robot, with particular attention to:
- the overall task structure;
- scene geometry and target semantics;
- actions, observations, and the logic of the `set_shot` command;
- the **training split into two phases** (`env_cfgs_3000.py` and `env_cfgs_10000.py`);
- the rewards actually used in the **pre-kick** phase and in the **kick** phase;
- terminations, PPO hyperparameters, and operational notes.

The operational reference is provided by the task/configuration files and the two reward snapshots:
- `task.py`
- `rl_cfg.py`
- `env_cfgs_3000.py`
- `env_cfgs_10000.py`
- `mdp.py`

---

## 1. Expert objective

The expert models a **right-footed penalty shot** from a static start, with an intentionally progressive structure:

1. **Pre-kick / biomechanical setup**  
   The robot learns to position itself correctly with respect to the ball, keep the **left support foot** close to the ball, prepare the right foot, and strike in the desired direction without immediately requiring a high, highlight-style shot.

2. **Kick / action refinement**  
   Once the robot has learned the correct preparation, training moves to a second phase in which the robot is asked to:
   - strike more cleanly and repeatably;
   - maintain left-foot support even **after** impact;
   - give the ball a consistent **launch angle**, **lift**, and trajectory toward a high target.

This split into two training stages dramatically reduces optimization difficulty: if the policy had to learn **setup + impact + lift + final precision** all at once, it would likely converge too early to easy but incorrect solutions (for example: low central shots, dirty contact, losing left-foot support, or excessive crouching).

---

## 2. Overall pipeline structure

The pipeline has two levels.

### 2.1 Stage-1 motor decoder
The policy action does not command the 23 actuators directly in raw joint space.  
The task uses `MotorLatentActionCfg`, so the policy operates in a **latent space** decoded by an external Stage-1 controller, referenced through:

- environment variable `MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY`;
- `stage1_wandb_run_path=os.environ.get("MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY")`.

In practice:
- **Stage-1** provides a reusable motor decoder;
- **Stage-2 (this expert)** trains the PPO policy on the penalty-shot behavior itself.

### 2.2 Stage-2 PPO expert
The registered task is:

- `Mjlab-Penalty-Booster-T1_23`

and uses a PPO configuration with:
- actor and critic MLPs `(512, 256, 128)`, `ELU` activation;
- `entropy_coef = 0.02`;
- `num_steps_per_env = 24`;
- `max_iterations = 30000`.

---

## 3. Scene geometry and coordinates

The scene uses the frame convention already consistent with the other RoboCup tasks.

### 3.1 Goal line and visual asset
It is important to distinguish between:
- **logical goal line**: `GOAL_X_LINE = 7.0`
- **goal mesh / visual asset**: `GOALPOST_X = 7.3`

Therefore:
- the ball is evaluated as a goal when it crosses **x >= 7.0** inside the valid opening;
- the visual goal mesh is placed slightly farther forward, at **x = 7.3**.

### 3.2 Valid goal opening
The valid goal window is:
- `|y| <= 1.55`
- `0 <= z <= 1.85`

### 3.3 Initial ball and robot positions
Common data for both stages:
- penalty distance from the goal line: `2.5 m`
- nominal ball position: `(x=4.5, y=0.0, z=0.11)`
- nominal robot position: `(x=4.12, y=0.04, z=default_root_height)`
- jitter:
  - ball x: `+/- 0.01`
  - robot x: `+/- 0.01`
  - robot y: `+/- 0.01`
  - yaw: `+/- 0.03`

### 3.4 Working area
The task uses:
- a test field with half-size `7.0 x 4.5`;
- a goal opening consistent with `goal_opening_half_width = 1.55`;
- a `ball_out` termination when the ball leaves the useful field area;
- a `hard_outside_area` termination if the robot leaves the hard striker area.

---

## 4. `set_shot` command term

The core of the task is the `SetShotCommand` command.

### 4.1 What it contains
The command defines:
- ball position;
- shot target on the goal;
- robot reset;
- target-side sampling mode;
- the possibility of entering directly into **kick-only reset**.

### 4.2 Target on the goal line
In both stages the target is defined directly on the **goal line**:
- `x = GOAL_X_LINE`
- `y = visual_left_corner_y` or `visual_right_corner_y`
- `z = AIM_Z`

This choice is important because it keeps the following coherent:
- robot orientation;
- final rewards (`lateral_goal`, `underbar_goal`, `goal_target_from_command`);
- any debug visualization marker of the target.

### 4.3 Side randomization
Both snapshots use:
- `TARGET_MODE = "random_binary"`

So the lateral target is sampled at reset between:
- `VISUAL_LEFT_CORNER_Y = +1.0`
- `VISUAL_RIGHT_CORNER_Y = -1.0`

This makes it possible to generalize the movement to both corners without changing the core right-foot biomechanics of the shot.

### 4.4 Two reset modes useful for learning
The command also supports `kick_only_reset_prob = 0.6`.  
Practical interpretation:
- in **40%** of resets the policy starts from the full pipeline (approach/pre-kick -> strike);
- in **60%** of resets it starts directly from a **kick-ready pose**, which speeds up learning for the impact phase.

This is a key component of the “pre-kick vs kick” split: the same task trains both the full preparation and a shorter sub-problem focused on the strike itself.

---

## 5. Actions and observations

## 5.1 Action
The task uses a single action:
- `motor_latent`

The policy therefore emits a latent command decoded by the Stage-1 motor controller.

## 5.2 Actor/critic observations
Actor and critic use essentially the same set of observations.

### Robot base
- `base_lin_vel`
- `base_ang_vel`
- `projected_gravity`
- `joint_pos`
- `joint_vel`
- `decoded_actions`

### Penalty-task-specific information
- `target_dir_xy`
- `ball_pos_rel_xyz`
- `ball_vel_w_xy`
- `kick_phase_flag`
- `kick_only_reset_flag`
- `yaw_error_abs`
- `ball_dist_xy`
- `right_foot_pos_rel_ball_xy`
- `left_foot_pos_rel_ball_xy`
- `left_support_latched_error_xy`

Interpretation:
- the policy knows **where it is supposed to shoot** (`target_dir_xy`);
- it knows **where the ball is** relative to the body;
- it knows whether it is already in **kick phase** or in **kick-only reset**;
- it receives explicit features about left-foot support and right-foot position.

---

## 6. Why training is split into two stages

In this project, the two files `env_cfgs_3000.py` and `env_cfgs_10000.py` represent two configuration snapshots to be used as **distinct training phases**.

## 6.1 Train 1 - Pre-kick / direction / basic impact
Reference:
- `env_cfgs_3000.py`

Idea:
- lateral target already active;
- vertical target still low (`AIM_Z = 0.35`);
- final height reward still disabled;
- focus on:
  - correct support-foot placement;
  - clean strike;
  - making the right foot actually contact the ball;
  - sending the ball laterally toward the desired side.

In other words: **first teach the robot how to set up and strike well**, not yet how to produce an immediate underbar shot.

## 6.2 Train 2 - Kick refinement / lift / high trajectory
Reference:
- `env_cfgs_10000.py`

Idea:
- higher vertical target (`AIM_Z = 1.45`);
- lift and launch-angle rewards activated;
- penalties for premature bounces and ground touches before the goal;
- left-foot support latched and monitored after the strike;
- final objective: turn the already-directed gesture into a **high, clean shot**.

In other words: **the second training stage does not re-teach direction**, but refines shot quality.

---

## 7. Train 1 (`env_cfgs_3000.py`) - pre-kick phase

### 7.1 General intuition
In the first training stage the robot must learn:
- not to “sit down” too much;
- not to touch the ball with the left foot too early;
- not to step over the ball;
- to build a right-footed movement with the left support foot close to the ball;
- to already shoot laterally toward the target;
- without yet emphasizing the final shot height.

### 7.2 Train 1 target parameters
- lateral target: `y = +/- 1.0` (random binary)
- vertical target: `z = 0.35`
- `underbar_launch = 0.0`
- `underbar_goal = 0.0`

This makes the task much simpler: it primarily trains **lateral control** and strike mechanics.

### 7.3 Train 1 rewards

| Reward | Weight | Purpose |
|---|---:|---|
| `right_foot_swing_intent_debug` | `+1.0` | Auxiliary signal to verify that the right foot really goes into swing. |
| `right_only_strike` | `+2.0` | Bonus if the first real strike is performed with the right foot, without left-foot contact. |
| `strike_event` | `+12.0` | Main event that recognizes the first robust strike (touch or clear ball departure). |
| `impact_foot_speed` | `+8.0` | Rewards high right-foot speed at impact. |
| `clean_strike` | `+10.0` | Favors clean impact, not just violent impact. |
| `ball_speed_to_goal` | `+6.0` | Rewards ball speed toward the goal after the strike. |
| `goal_scored` | `+12.0` | Main goal reward, in a soft target-aware form. |
| `upright` | `+0.55` | Keeps the body in a usable posture. |
| `low_height_soft_penalty` | `-1.8` | Penalizes collapse toward the ground. |
| `double_knee_crouch` | `-1.5` | Prevents excessive crouching on both knees. |
| `fallen` | `-4.0` | Fall penalty. |
| `left_pre_touch` | `-1.0` | Penalizes the left foot touching the ball before the correct strike. |
| `foot_over_ball` | `-2.0` | Prevents a foot from stepping over the ball. |
| `foot_contact_switch` | `+0.2` | Small bonus for support switches that help unlock the movement. |
| `support_plant_at_strike` | `+14.0` | Key reward: the left foot must be well planted next to the ball at the strike frame. |
| `underbar_launch` | `0.0` | Disabled in Train 1. |
| `underbar_goal` | `0.0` | Disabled in Train 1. |
| `goal_target_from_command` | `+20.0` | Final combined reward on Y and Z at goal-line crossing. |
| `lateral_goal` | `+18.0` | Final reward specifically for the lateral target. |

### 7.4 Most important Train 1 rewards to understand

#### `support_plant_at_strike`
This is one of the key rewards of the entire expert.  
It pays **only once**, at the frame in which the right foot truly strikes the ball, and requires that:
- the left foot is near the desired position relative to the ball;
- the left foot is on the ground;
- the left foot is not touching the ball;
- the right foot arrives with sufficient speed.

In practice, it forces the robot to build proper shot biomechanics instead of “shooting in any possible way.”

#### `strike_event`
This reward is used to determine whether a real kick has occurred.  
A noisy contact is not enough: the function uses both contact sensors and actual ball departure with minimum speed.

#### `goal_target_from_command` and `lateral_goal`
These two rewards provide the final signal that links the gesture to the intended direction:
- `lateral_goal` looks at the ball `y` coordinate when it crosses the goal line;
- `goal_target_from_command` combines `y` and `z`.

In Train 1 the `z` height is intentionally of little importance, so the dominant signal is lateral direction.

---

## 8. Train 2 (`env_cfgs_10000.py`) - kick / high-shot phase

### 8.1 General intuition
Once the robot has learned to:
- position itself correctly;
- strike with the right foot;
- stay laterally aligned with the target;

it moves to the second stage, where the required gesture becomes more refined:
- stable left-foot support even after the strike;
- right-foot velocity driven toward a target, not simply maximized;
- straighter right knee at impact;
- 3D trajectory coherent with the target;
- no premature bounces or ground touches;
- high finishing under the bar.

### 8.2 Train 2 target parameters
- lateral target: `y = +/- 1.0`
- vertical target: `z = 1.45`
- `underbar_launch` enabled
- `underbar_goal` enabled

This completely changes the nature of the task: the robot must **lift the shot**.

### 8.3 Train 2 rewards

| Reward | Weight | Purpose |
|---|---:|---|
| `strike_event` | `+12.0` | Robust strike event. |
| `impact_foot_speed` | `+4.0` | Does not maximize absolute speed: it aims for a target right-foot speed. |
| `ball_speed_to_left_aim_3d` | `+4.0` | Rewards 3D ball velocity toward the aim point after the strike. |
| `goal_scored` | `+12.0` | Main goal reward, target-aware and not hard-gated. |
| `post_strike_left_support_move` | `-3.0` | Penalizes the left foot if it moves too much after the strike. |
| `post_strike_left_support_speed` | `-1.5` | Penalizes excessive left-foot speed during the post-strike lock window. |
| `post_strike_left_support_lost_ground` | `-2.0` | Penalizes loss of left-foot ground contact after impact. |
| `upright` | `+0.55` | Overall body stability. |
| `low_height_soft_penalty` | `-2.2` | More severe than Train 1 against collapsing low. |
| `double_knee_crouch` | `-2.0` | More severe than Train 1 against crouching. |
| `fallen` | `-4.0` | Fall penalty. |
| `left_pre_touch` | `-1.0` | Penalty for left-foot pre-touch. |
| `foot_over_ball` | `-2.0` | Prevents the foot from stepping over the ball. |
| `foot_contact_switch` | `+0.2` | Small bonus for support switches. |
| `support_plant_at_strike` | `+14.0` | Still fundamental in the kick phase. |
| `right_knee_straight_at_strike` | `+6.0` | Rewards a straighter right leg at impact. |
| `bad_posture_at_strike` | `-6.0` | Penalizes striking from a wrong posture. |
| `underbar_launch` | `+10.0` | Rewards an initial launch angle consistent with an underbar shot. |
| `ball_power_lift` | `+6.5` | Rewards a mix of 3D speed, `vx`, and `vz` after the strike. |
| `ball_ground_touch_before_goal` | `-6.0` | Penalizes the ball touching the ground before the goal. |
| `ball_bounce_before_goal` | `-4.0` | Penalizes premature bounces. |
| `underbar_goal` | `+8.0` | Final reward specifically on the Z coordinate at goal-line crossing. |
| `goal_target_from_command` | `+14.0` | Full final reward on Y+Z. |
| `lateral_goal` | `+12.0` | Final lateral reward. |

### 8.4 Most important Train 2 rewards to understand

#### `impact_foot_speed` (target-speed version)
In Train 1, right-foot speed is pushed upward.  
In Train 2 it changes into a **target-speed** version:
- a desired speed is specified (`target_speed=4.7`);
- the optimum is no longer “as fast as possible,” but “the correct and repeatable speed.”

This helps make the gesture more controlled.

#### `post_strike_left_support_*`
These rewards are essential to prevent the robot from “letting go of everything” immediately after impact.
The left foot is latched in position and then:
- it should not move too far;
- it should not accelerate too much;
- it should not lose ground contact.

These rewards are important because they tie shot quality to **movement stability**, not just to the instant of contact.

#### `underbar_launch` and `ball_power_lift`
These two rewards introduce the “high-shot” physics:
- `underbar_launch` favors the correct launch angle;
- `ball_power_lift` rewards a combination of 3D speed, `vx`, and `vz`.

These are the reasons why Train 2 can be seen as the phase that “teaches the robot to lift the ball.”

#### `ball_ground_touch_before_goal` and `ball_bounce_before_goal`
These penalties clean up the behavior:
- a high shot should not become a dirty lob that bounces before the goal;
- the ball should reach the goal with a cleaner trajectory.

---

## 9. Final rewards on the goal line

An important architectural point is that the shot target is placed directly on the **goal line**.  
This makes three final rewards coherent.

### `lateral_goal`
Rewards the proximity of the ball `y` coordinate to the lateral target when the ball crosses the goal line.

### `underbar_goal`
Rewards the proximity of the ball `z` coordinate to the vertical target when the ball crosses the goal line.

### `goal_target_from_command`
Rewards the joint quality on `y` and `z`.

This choice removes the old ambiguity in which the ball on the goal line was compared to an aim point located farther forward in the world.

---

## 10. Main goal reward: why it was made “soft”
During the evolution of the task, the pure goal reward (`goal_scored_event_reward`) was progressively made less “blind” to the target.  
The intended version is a **soft target-aware** goal reward:

- scoring is still worth something;
- scoring near the lateral target is worth more;
- scoring near the vertical target is worth more;
- scoring well on both is worth the maximum.

This solution is much better than a hard gate because it:
- does not switch off the learning signal early on;
- but still teaches the policy that the “correct” goal is worth more than an easy central goal.

---

## 11. Terminations and episode dynamics

The terminations common to both stages are:

| Termination | Meaning |
|---|---|
| `fallen` | persistent robot fall (low height / high tilt for multiple consecutive steps) |
| `hard_outside_area` | robot outside the hard striker area |
| `ball_out` | ball outside the useful field area |

Timing:
- `SIM_TIMESTEP_S = 0.005`
- `CONTROL_DECIMATION = 4`
- `RL dt = 0.02 s`
- `EPISODE_LENGTH_S = 5.0`

---

## 12. PPO / RL configuration

The PPO configuration is unique for this task.

| Parameter | Value |
|---|---:|
| Actor hidden dims | `(512, 256, 128)` |
| Critic hidden dims | `(512, 256, 128)` |
| Activation | `ELU` |
| Learning rate | `1e-3` |
| Schedule | `adaptive` |
| Entropy coef | `0.02` |
| Gamma | `0.99` |
| Lambda | `0.95` |
| Num learning epochs | `5` |
| Num mini-batches | `4` |
| Num steps per env | `24` |
| Save interval | `500` |
| Max iterations | `30000` |

Interpretation:
- the two stages do not change the PPO runner;
- what changes is primarily the **reward landscape**.

---

## 13. Overall reading of the design

The expert is not “a single reward hack,” but a well-scaled pipeline.

### Train 1
It teaches:
- posture;
- left-foot support;
- real strike execution;
- lateral direction;
- absence of major errors.

### Train 2
It teaches:
- high shot;
- better extension of the right leg;
- post-strike stability;
- fewer bounces;
- finishing consistent with the 3D target.

This division makes sense because:
- pre-kick is a problem of **body setup and contact**;
- the high kick is a problem of **ball dynamics** and **gesture refinement**.

---

## 14. Conclusion

The Booster T1 penalty-shot expert is built as a progressively more complex task:
- first the robot learns **how to set up** and **how to strike**;
- then it learns **how to refine the strike** to obtain a high, clean shot consistent with the target.

The split into two training stages is not an implementation detail, but a strong methodological choice:  
**it separates the biomechanics of the movement from the final ball trajectory**, improving learning stability and making the reward design easier to interpret.

---
