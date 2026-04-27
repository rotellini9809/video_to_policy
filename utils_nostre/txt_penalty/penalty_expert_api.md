# Penalty Expert API / Runbook - Booster T1_23

## 1. Purpose
This document explains how to:
- activate the penalty expert task;
- connect it to the Stage-1 decoder;
- run play and training;
- reproduce the **two-stage training workflow**;
- understand which files control the expert behavior.

---

## 2. Main project files

| File | Role |
|---|---|
| `task.py` | registers the task `Mjlab-Penalty-Booster-T1_23` |
| `rl_cfg.py` | defines the PPO runner |
| `env_cfgs.py` | active task configuration |
| `env_cfgs_3000.py` | Train 1 snapshot (pre-kick) |
| `env_cfgs_10000.py` | Train 2 snapshot (kick / high shot) |
| `mdp.py` | command term, observation helpers, reward helpers, and termination helpers |

---

## 3. Prerequisites

## 3.1 Stage-1 decoder
The task uses `MotorLatentActionCfg`, so before launching the expert you must export the W&B path of the Stage-1 motor decoder:

```bash
export ENTITY=<your_wandb_entity>
export STAGE1_RUN_ID=<stage1_run_id>
export MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY="$ENTITY/motor_controller_stage1/$STAGE1_RUN_ID"
```

If your fork supports Stage-1 checkpoint selection, you can also keep a variable such as:

```bash
export MJLAB_STAGE1_CHECKPOINT=best
```

> Note: `MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY` is the variable actually read by the penalty-task configuration files.

---

## 4. Task ID

The registered task is:

```text
Mjlab-Penalty-Booster-T1_23
```

The registration happens in `task.py`.

---

## 5. Sanity play

To verify that the task loads correctly:

```bash
uv run play Mjlab-Penalty-Booster-T1_23 \
  --agent random \
  --num-envs 1 \
  --viewer viser
```

Recommended usage:
- `--num-envs 1` to inspect the behavior clearly;
- `--viewer viser` for visual debugging of the target.

---

## 6. Basic training

To launch standard training:

```bash
uv run train Mjlab-Penalty-Booster-T1_23 \
  --env.scene.num-envs 512 \
  --agent.max_iterations 3000 \
  --agent.run_name title_of_run_3000
```

These values are consistent with:
- `num_envs = 512`
- `max_iterations = 3000`

defined in the configuration files.

---

## 7. Playing a trained policy

Generic template:

```bash
uv run play Mjlab-Penalty-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/penalty/<run_id>"
```

Replace `<run_id>` with the correct W&B run.

---

## 8. Recommended two-stage workflow

The project is intended to run in **two phases**.

## 8.1 Train 1 - Pre-kick
Use as reference:
- `env_cfgs_3000.py`

Objective:
- learn shot setup;
- learn left-foot support;
- learn the first correct strike;
- learn lateral shot direction.

### Practical procedure
1. Use `env_cfgs_3000.py` as the active configuration.
2. Train the task.
3. Save the checkpoint / run.

## 8.2 Train 2 - Kick refinement
Use as reference:
- `env_cfgs_10000.py`

Objective:
- raise the shot;
- improve launch angle;
- improve left-foot control in post-strike;
- reduce bounce and premature ground touches.

### Practical procedure
1. Replace the active configuration with the Train 2 configuration.
2. Resume from the Train 1 checkpoint.
3. Continue training until convergence.

```bash
uv run train Mjlab-Penalty-Booster-T1_23 \
  --agent.run_name name_of_run_10000 \
  --agent.resume True \
  --wandb-run-path <ENTITY/PROJECT/RUN_ID_3000> \
  --wandb-checkpoint-name <CHECKPOINT_NAME> \
  --agent.max_iterations 10000
```

> Important note: `task.py` imports `env_cfgs.py`.  
> In practice, to switch from Train 1 to Train 2 you must **align the contents of `env_cfgs.py`** with the stage you want to run, or manage two task versions externally in your branch.

---

## 9. Common task parameters

## 9.1 Geometry
- `GOAL_X_LINE = 7.0`
- `GOALPOST_X = 7.3`
- `goal_y_half = 1.55`
- `goal_z_max = 1.85`

## 9.2 Spawn
- nominal ball: `x = 4.5`, `y = 0.0`, `z = 0.11`
- nominal robot: `x = 4.12`, `y = 0.04`

## 9.3 Randomization
- ball X jitter: `+/- 0.01`
- robot X jitter: `+/- 0.01`
- robot Y jitter: `+/- 0.01`
- yaw jitter: `+/- 0.03`

## 9.4 Reset shortcut
- `kick_only_reset_prob = 0.6`

Interpretation:
- many resets start directly in the kick-ready phase;
- this accelerates impact learning.

---

## 10. How to change the shot target

The key parameters are in `env_cfgs.py` or in the stage snapshots:

```python
VISUAL_LEFT_CORNER_Y = 1.0
VISUAL_RIGHT_CORNER_Y = -1.0
TARGET_MODE = "random_binary"
FIXED_TARGET_CORNER = "left"
AIM_Z = ...
```

### Meaning
- `VISUAL_LEFT_CORNER_Y` / `VISUAL_RIGHT_CORNER_Y`  
  define the lateral targets on the **goal line**.
- `TARGET_MODE = "fixed"`  
  always uses `FIXED_TARGET_CORNER`.
- `TARGET_MODE = "random_binary"`  
  samples left/right at every reset.
- `AIM_Z` defines the vertical target.

### Difference between the two stages
- Train 1: `AIM_Z = 0.35`
- Train 2: `AIM_Z = 1.45`

---

## 11. How the `set_shot` command works

The command:
1. resets the ball;
2. samples the lateral target;
3. builds `aim_pos_w` directly on the **goal line**;
4. resets the robot behind the ball with right-foot shot offsets;
5. optionally enters `kick_only_reset`.

This is the point where the task decides:
- **where** the robot is supposed to shoot;
- **how** the shot frame is defined.

---

## 12. Observations used by the policy

The policy receives:
- base velocities;
- projected gravity;
- joint positions and velocities;
- last decoded actions;
- target direction (`target_dir_xy`);
- ball position and velocity;
- kick-phase flags;
- yaw error;
- foot-to-ball features;
- latched left-support error.

These observations are sufficient for:
- pre-kick;
- strike;
- post-strike stabilization.

---

## 13. High-level reward strategy

## Train 1
Main rewards:
- `strike_event`
- `support_plant_at_strike`
- `goal_target_from_command`
- `lateral_goal`

Target:
- learn **direction + support placement + first clean strike**

## Train 2
Additional rewards:
- `underbar_launch`
- `ball_power_lift`
- `underbar_goal`
- `post_strike_left_support_*`
- `right_knee_straight_at_strike`

Target:
- learn **lift + height + support control**

---

## 14. Consistency checks before launch

Before every training run, verify the following.

### 14.1 Stage-1 path
```bash
echo $MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY
```

### 14.2 Active task
Check that `task.py` points to the correct task:
- `Mjlab-Penalty-Booster-T1_23`

### 14.3 Active stage config
Check which reward snapshot is currently inside `env_cfgs.py`:
- Train 1 / `env_cfgs_3000.py`
- or Train 2 / `env_cfgs_10000.py`

### 14.4 `env_cfgs.py` <-> `mdp.py` alignment
Every reward referenced by the config must actually exist in `mdp.py`.

This check is essential when you switch stages or cherry-pick new rewards.

---

## 15. Recommended runbook

## Minimal runbook
```bash
export ENTITY=<your_wandb_entity>
export STAGE1_RUN_ID=<stage1_run_id>
export MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY="$ENTITY/motor_controller_stage1/$STAGE1_RUN_ID"

uv run play Mjlab-Penalty-Booster-T1_23 \
  --agent random \
  --num-envs 1 \
  --viewer viser
```

## Train 1
1. activate the pre-kick config;
2. train;
3. save the checkpoint.

## Train 2
1. activate the kick/high-shot config;
2. resume from the Train 1 checkpoint;
3. continue training.

---

## 16. Conclusion
The penalty expert API is simple to use, but the project works well only if you keep the separation clear between:

- the **active task configuration**;
- the **stage 1 / stage 2 training snapshots**;
- the **Stage-1 decoder**;
- the **reward helpers defined in `mdp.py`**.

The practical rule is:
- **Train 1** teaches the movement;
- **Train 2** teaches the final shot quality.
