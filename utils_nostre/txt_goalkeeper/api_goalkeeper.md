# Goalkeeper API

## Shared prerequisites

```bash
export ENTITY=<your_wandb_entity>
export STAGE1_RUN_ID=<stage1_run_id>

# Required by goalkeeper experts (Stage-1 decoder source)
export MJLAB_STAGE1_WANDB_RUN_PATH_GOALKEEPER="$ENTITY/motor_controller_stage1/$STAGE1_RUN_ID"

# Optional: best | last | latest (default: best)
export MJLAB_STAGE1_CHECKPOINT=best
```

## Resume an existing run

Resume E1 from W&B:

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=<1|2|3> \
uv run train Mjlab-GK-Expert-E1-Repositioning-Booster-T1_23 \
  --agent.resume True \
  --wandb-checkpoint-name last \
  --wandb-run-path "$ENTITY/e1_goalkeeper_expert/<run_id>"
```

Resume E2 from W&B:

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=<1|2|3> \
uv run train Mjlab-GK-Expert-E2-BlockDeflect-Booster-T1_23 \
  --agent.resume True \
  --wandb-checkpoint-name last \
  --wandb-run-path "$ENTITY/e2_goalkeeper_expert/<run_id>"
```

Notes:
- `--wandb-checkpoint-name` accepts `latest`, `best`, `last`, or a concrete file such as `model_18000.pt`.
- Curriculum stage is selected on launch through the corresponding reset environment variable.

## E1 Repositioning

Task ID: `Mjlab-GK-Expert-E1-Repositioning-Booster-T1_23`

### Dry run

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=1 \
uv run play Mjlab-GK-Expert-E1-Repositioning-Booster-T1_23 \
  --agent zero \
  --num-envs 1 \
  --viewer viser \
  --no-fall-termination True
```

### Train from zero

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=1 \
uv run train Mjlab-GK-Expert-E1-Repositioning-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max_iterations 20000
```

### Continue training from W&B

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=1 \
uv run train Mjlab-GK-Expert-E1-Repositioning-Booster-T1_23 \
  --agent.resume True \
  --wandb-checkpoint-name model_18000.pt \
  --wandb-run-path "$ENTITY/e1_goalkeeper_expert/<run_id>" \
  --agent.max-iterations 30000
```

### Play trained policy from W&B

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=1 \
uv run play Mjlab-GK-Expert-E1-Repositioning-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/e1_goalkeeper_expert/<run_id>"
```

## E2 BlockDeflect

Task ID: `Mjlab-GK-Expert-E2-BlockDeflect-Booster-T1_23`

### Dry run

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=2 \
uv run play Mjlab-GK-Expert-E2-BlockDeflect-Booster-T1_23 \
  --agent zero \
  --num-envs 1 \
  --viewer viser
```

### Train from zero

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=1 \
uv run train Mjlab-GK-Expert-E2-BlockDeflect-Booster-T1_23 \
  --agent.run-name e2_block_deflect_stage2_from_scratch \
  --agent.max-iterations 30000 \
  --env.scene.num-envs 4096
```

### Continue training from W&B

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=2 \
uv run train Mjlab-GK-Expert-E2-BlockDeflect-Booster-T1_23 \
  --agent.resume True \
  --wandb-checkpoint-name last \
  --wandb-run-path "$ENTITY/e2_goalkeeper_expert/<run_id>"
```

### Play trained policy from W&B

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=2 \
uv run play Mjlab-GK-Expert-E2-BlockDeflect-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/e2_goalkeeper_expert/<run_id>"
```

## Efin Continuous Goalkeeper

Task ID: `Mjlab-GK-Expert-Efin-ContinuousGoalkeeper-Booster-T1_23`

Notes:
- This task currently uses a scripted stochastic ball state machine.
- It uses the same Stage-1 latent motor decoder path as E1/E2, so `MJLAB_STAGE1_WANDB_RUN_PATH_GOALKEEPER` is required unless passed explicitly to helper scripts.
- Current phases are `play_move -> approach_danger -> shot -> post_shot_timeout`.

### Dry run

```bash
uv run play Mjlab-GK-Expert-Efin-ContinuousGoalkeeper-Booster-T1_23 \
  --agent zero \
  --num-envs 1 \
  --viewer viser
```

### Train from zero

```bash
uv run train Mjlab-GK-Expert-Efin-ContinuousGoalkeeper-Booster-T1_23 \
  --env.scene.num-envs 256 \
  --agent.max-iterations 1000
```

### Play trained policy from W&B

```bash
uv run play Mjlab-GK-Expert-Efin-ContinuousGoalkeeper-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/goalkeeper_expert/<run_id>"
```

## E2 From Efin Snapshots

Task ID: `Mjlab-GK-Expert-E2-FromEfinSnapshots-Booster-T1_23`

This task trains an E2-style keeper from Efin handoff snapshots. The environment resets from snapshots captured when Efin enters `approach_danger`, then continues with Efin's `continuous_ball` dynamics while using an E2-like reward surface.

Files:
- task registration: `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_from_efin_snapshots/config/t1_23dof/task.py`
- env config and rewards: `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_from_efin_snapshots/config/t1_23dof/env_cfgs.py`
- snapshot reset logic: `mjlab/src/mjlab/tasks/goalkeeper_experts/efin_continuous_goalkeeper/mdp.py`
- snapshot collector: `mjlab/src/mjlab/scripts/collect_efin_approach_snapshots.py`

### Collect Efin approach snapshots with an E1 actor

```bash
uv run collect-efin-approach-snapshots \
  --wandb-run-path-e1 "$ENTITY/e1_goalkeeper_expert/<run_id_e1>" \
  --wandb-checkpoint-name-e1 latest \
  --stage1-goalkeeper-run-path "$MJLAB_STAGE1_WANDB_RUN_PATH_GOALKEEPER" \
  --num-envs 64 \
  --num-snapshots 10000 \
  --output-dir ./data/goalkeeper_teacher_switch/efin_approach_snapshots
```

The collector rejects unhealthy snapshots by default:
- robot height `< 0.32`
- absolute roll `> 100 deg`
- absolute joint velocity `> 20`
- robot outside a rough keeper-area sanity box

### Train from snapshots

```bash
MJLAB_EFIN_SNAPSHOT_DATASET_PATH=./data/goalkeeper_teacher_switch/efin_approach_snapshots/efin_approach_snapshots.npz \
uv run train Mjlab-GK-Expert-E2-FromEfinSnapshots-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max-iterations 20000
```

Inside the Docker container, use the container path:

```bash
MJLAB_EFIN_SNAPSHOT_DATASET_PATH=/app/data/goalkeeper_teacher_switch/efin_approach_snapshots/efin_approach_snapshots.npz \
uv run train Mjlab-GK-Expert-E2-FromEfinSnapshots-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max-iterations 20000
```

### Play trained policy from W&B

```bash
MJLAB_EFIN_SNAPSHOT_DATASET_PATH=/app/data/goalkeeper_teacher_switch/efin_approach_snapshots/efin_approach_snapshots.npz \
uv run play Mjlab-GK-Expert-E2-FromEfinSnapshots-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/goalkeeper_expert/<run_id>"
```


### Continue training from W&B

Resume with the same snapshot dataset path:

```bash
MJLAB_EFIN_SNAPSHOT_DATASET_PATH=/app/data/goalkeeper_teacher_switch/efin_approach_snapshots/efin_approach_snapshots.npz \
uv run train Mjlab-GK-Expert-E2-FromEfinSnapshots-Booster-T1_23 \
  --agent.resume True \
  --wandb-run-path "$ENTITY/goalkeeper_expert/<run_id>" \
  --wandb-checkpoint-name latest \
  --agent.max-iterations 40000
```


## Efin Teacher-Switch Distillation Data

Script: `src/mjlab/scripts/collect_efin_teacher_switch_rollouts.py`

Behavior:
- Runs `efin` in play mode.
- Uses frozen actor inference only.
- Hard switch:
  - `PLAY_MOVE` and `APPROACH_DANGER` -> E1 actor
  - `SHOT` and `POST_SHOT_TIMEOUT` -> E2 actor
- Saves `efin` actor observations with teacher latent actions (`motor_latent`, 32-D).


### Collect and upload as W&B artifact

```bash
uv run python src/mjlab/scripts/collect_efin_teacher_switch_rollouts.py \
  --wandb-run-path-e1 "$ENTITY/e1_goalkeeper_expert/<run_id_e1>" \
  --wandb-run-path-e2 "$ENTITY/e2_goalkeeper_expert/<run_id_e2>" \
  --efin-curriculum-stage 2 \
  --num-envs 64 \
  --num-steps 200000 \
  --output-dir ./data/goalkeeper_teacher_switch/efin_mix_run1 \
  --save-as-artifact True \
  --artifact-project goalkeeper_distillation
```

### Collect and launch live mixed-teacher play afterwards

```bash
uv run python src/mjlab/scripts/collect_efin_teacher_switch_rollouts.py \
  --wandb-run-path-e1 "$ENTITY/e1_goalkeeper_expert/<run_id_e1>" \
  --wandb-run-path-e2 "$ENTITY/e2_goalkeeper_expert/<run_id_e2>" \
  --efin-curriculum-stage 2 \
  --num-envs 64 \
  --num-steps 200000 \
  --output-dir ./data/goalkeeper_teacher_switch/efin_mix_run1 \
  --viewer viser
```

### Launch live mixed-teacher play only

If `--output-dir` is omitted, the script skips collection and starts the live mixed-teacher viewer directly.

```bash
uv run python src/mjlab/scripts/collect_efin_teacher_switch_rollouts.py \
  --wandb-run-path-e1 "$ENTITY/e1_goalkeeper_expert/<run_id_e1>" \
  --wandb-run-path-e2 "$ENTITY/e2_goalkeeper_expert/<run_id_e2>" \
  --efin-curriculum-stage 1 \
  --viewer viser
```

Notes:
- Output shards contain `obs_actor` and `action_teacher`.
- `teacher_id=0` means E1, `teacher_id=1` means E2.
- If `--output-dir` is set, viewer mode starts a fresh live mixed-teacher rollout after collection; it is not a replay of the saved dataset.
- If `--output-dir` is not set, no collection happens.
