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
