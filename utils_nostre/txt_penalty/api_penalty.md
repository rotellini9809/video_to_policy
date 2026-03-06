# Penalty Expert API

## Shared prerequisites

```bash
export ENTITY=<your_wandb_entity>
export STAGE1_RUN_ID=<stage1_run_id>

# Required by penalty expert (Stage-1 decoder source)
export MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY="$ENTITY/motor_controller_stage1/$STAGE1_RUN_ID"

# Optional: best | last | latest (default: best)
export MJLAB_STAGE1_CHECKPOINT=best
```

## P1 - SetShot (Penalty Kick)

Task ID: `Mjlab-Penalty-Booster-T1_23`

### Sanity play (random policy)

```bash
uv run play Mjlab-Penalty-Booster-T1_23 \
  --agent random \
  --no-fall-termination True \
  --num-envs 1 \
  --viewer native
```

### Train

```bash
uv run train Mjlab-Penalty-Booster-T1_23 \
  --agent.run_name P1_penalty_expert_v0 \
  --env.scene.num-envs 500 \
  --agent.max_iterations 500

```

### Play trained policy

```bash
uv run play Mjlab-Penalty-Booster-T1_23 \
  --wandb-run-path "$ENTITY/penalty_experts/<run_id>" \
  --num-envs 1 \
  --viewer native
```

## Environment rules (design intent)

- Max episode length: **6 seconds**.
- The striker should hit the ball **at most once** (terminate on 2nd touch).
- Episode terminates if the ball goes **out of the playable field**.
- Episode **does not terminate on goal**; goal rewards are **event-based** (fire once on goal-line crossing).
