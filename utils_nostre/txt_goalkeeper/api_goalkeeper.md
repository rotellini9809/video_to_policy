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
  --no-fall-termination True \
  --num-envs 1 \
  --viewer native
```

### Train

```bash
uv run train Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
  --env.scene.num-envs 512 \
  --agent.max_iterations 500
```

### Play trained policy

```bash
uv run play Mjlab-GK-Expert-SetSquare-Booster-T1_23 \
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
  --viewer native
```

### Train

```bash
uv run train Mjlab-GK-Expert-StandBlock-Booster-T1_23 \
  --env.scene.num-envs 512 \
  --agent.max_iterations 500
```

### Play trained policy

```bash
uv run play Mjlab-GK-Expert-StandBlock-Booster-T1_23 \
  --wandb-run-path "$ENTITY/goalkeeper_experts/<run_id>" 
```

### Launcher validation

```bash
uv run python src/mjlab/scripts/validate_gk_e2_launcher.py \
  --num-resets 200 \
  --num-envs 512
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
  --env.scene.num-envs 512 \
  --agent.max_iterations 500
```

### Play trained policy

```bash
uv run play Mjlab-GK-Expert-ClearAway-Booster-T1_23 \
  --wandb-run-path "$ENTITY/goalkeeper_experts/<run_id>" 
```
