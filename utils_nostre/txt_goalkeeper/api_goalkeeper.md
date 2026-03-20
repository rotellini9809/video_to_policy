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
uv run train Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --env.scene.num-envs 512 \
  --agent.max_iterations 20000
```

### Play trained policy

```bash
uv run play Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --viewer native \
  --wandb-run-path "$ENTITY/goalkeeper_experts/<run_id>" 
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
  --agent.max_iterations 500
```

### E2 curriculum helper

Start from stage 1:

```bash
uv run python src/mjlab/scripts/promote_gk_e2_curriculum.py \
  --current-stage 1 \
  --num-envs 4096 \
  --train-iterations-per-stage 500 \
  --execute
```

Start from a previous W&B run:

```bash
uv run python src/mjlab/scripts/promote_gk_e2_curriculum.py \
  --current-stage 1 \
  --num-envs 4096 \
  --train-iterations-per-stage 500 \
  --wandb-run-path "$ENTITY/goalkeeper_experts/<old_run_id>" \
  --execute
```

### Play trained policy

```bash
MJLAB_E2_RESET_CURRICULUM_STAGE=1
uv run play Mjlab-GK-Expert-StandBlock-Booster-T1_23 \
  --num-envs 1 \
  --viewer viser
  --wandb-run-path "$ENTITY/goalkeeper_experts/<run_id>" 
```

### Launcher validation

```bash
uv run python src/mjlab/scripts/validate_gk_e2_launcher.py \
  --num-resets 200 \
  --num-envs 4096
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
  --wandb-run-path "$ENTITY/goalkeeper_experts/<run_id>" 
```
