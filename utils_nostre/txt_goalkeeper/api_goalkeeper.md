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

## Resume Existing Run

Resume from W&B:

```bash
# E1
MJLAB_E1_RESET_CURRICULUM_STAGE=<1|2|3> \
uv run train Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --agent.resume True \
  --wandb-checkpoint-name last \
  --wandb-run-path "$ENTITY/e1_goalkeeper_expert/<run_id>" 
  
```

Notes:
- `--wandb-checkpoint-name` accepts `latest`, `best`, `last`, or a concrete file such as `model_5000.pt`.
- For E1 and E2, the curriculum stage is still controlled by `MJLAB_E1_RESET_CURRICULUM_STAGE` / `MJLAB_E2_RESET_CURRICULUM_STAGE` on the resumed launch.

## E1 - SetSquare

Task ID: `Mjlab-GK-Expert-SetSquare-Booster-T1_23`

### Sanity play (random policy)

```bash
uv run play Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --agent random \
  --no-fall-termination False \
  --num-envs 1 \
  --viewer native
```

### Train

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=1 \
uv run train Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max_iterations 5000


uv run python src/mjlab/scripts/auto_promote_gk_e1_curriculum.py \
  --current-stage 1 \
  --num-envs 4096 \
  --train-iterations-per-stage 5000
```

Use `MJLAB_E1_RESET_CURRICULUM_STAGE=<1|2|3>` to select the E1 curriculum stage for that run.
### Play trained policy

```bash
uv run play Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --viewer viser \
  --wandb-run-path "$ENTITY/e1_goalkeeper_expert/<run_id>" 
```

## E1V2 - Mezzaluna

Task ID: `Mjlab-GK-Expert-E1V2-Mezzaluna-Booster-T1_23`

### Dry run

```bash
uv run play Mjlab-GK-Expert-E1V2-Mezzaluna-Booster-T1_23 \
  --agent zero \
  --num-envs 1 \
  --viewer native \
  --no-fall-termination
```

### Train stage 3 from zero

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=3 \
uv run train Mjlab-GK-Expert-E1V2-Mezzaluna-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max_iterations 5000
```

### Play trained policy from W&B

```bash
MJLAB_E1_RESET_CURRICULUM_STAGE=3 \
uv run play Mjlab-GK-Expert-E1V2-Mezzaluna-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/e1_goalkeeper_expert/<run_id>"
```

## E2 - StandBlock

Task ID: `Mjlab-GK-Expert-StandBlock-Booster-T1_23`

### Sanity play (random policy)

```bash
uv run play Mjlab-GK-Expert-StandBlock-Booster-T1_23 \
  --agent random \
  --no-fall-termination True \
  --num-envs 1 \
  --viewer viser
```

### Train

```bash
uv run train Mjlab-GK-Expert-StandBlock-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max_iterations 5000
```

### E2 curriculum helper

Start from stage 1:

```bash
uv run python src/mjlab/scripts/promote_gk_e2_curriculum.py \
  --current-stage 1 \
  --num-envs 4096 \
  --train-iterations-per-stage 7000 
```

Start from a previous W&B run:

```bash
uv run python src/mjlab/scripts/promote_gk_e2_curriculum.py \
  --current-stage 1 \
  --num-envs 4096 \
  --train-iterations-per-stage 5000 \
  --wandb-run-path "$ENTITY/e2_goalkeeper_expert/<old_run_id>" \
```

### Play trained policy

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=1
uv run play Mjlab-GK-Expert-StandBlock-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/e2_goalkeeper_expert/<run_id>" 
```

### Launcher validation

```bash
uv run python src/mjlab/scripts/validate_gk_e2_launcher.py \
  --num-resets 200 \
  --num-envs 4096
```

## E2V2 - Mezzaluna

Task ID: `Mjlab-GK-Expert-E2V2-Mezzaluna-Booster-T1_23`

### Dry run

```bash
MJLAB_E2V2_MEZZALUNA_RESET_CURRICULUM_STAGE=2 \
uv run play Mjlab-GK-Expert-E2V2-Mezzaluna-Booster-T1_23 \
  --agent zero \
  --num-envs 1 \
  --viewer viser
```

### Train stage 2 from zero

```bash
MJLAB_E2V2_MEZZALUNA_RESET_CURRICULUM_STAGE=2 \
uv run train Mjlab-GK-Expert-E2V2-Mezzaluna-Booster-T1_23 \
  --agent.run-name e2v2_mezzaluna_stage2_from_scratch \
  --agent.max-iterations 20000
```

### Play trained policy from W&B

```bash
MJLAB_E2V2_MEZZALUNA_RESET_CURRICULUM_STAGE=2 \
uv run play Mjlab-GK-Expert-E2V2-Mezzaluna-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser \
  --wandb-run-path "$ENTITY/e2_goalkeeper_expert/<run_id>"
```

## E3 - ClearAway

Task ID: `Mjlab-GK-Expert-ClearAway-Booster-T1_23`

### Sanity play (random policy)

```bash
uv run play Mjlab-GK-Expert-ClearAway-Booster-T1_23 \
  --agent random \
  --no-fall-termination True \
  --num-envs 1 \
  --viewer native
```

### Train

```bash
uv run train Mjlab-GK-Expert-ClearAway-Booster-T1_23 \
  --env.scene.num-envs 4096 \
  --agent.max_iterations 500
```

### Play trained policy

```bash
uv run play Mjlab-GK-Expert-ClearAway-Booster-T1_23 \
  --num-envs 1 \
  --wandb-run-path "$ENTITY/e3_goalkeeper_expert/<run_id>" 
```
