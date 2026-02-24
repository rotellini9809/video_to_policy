# Goalkeeper RL - Short Introduction

This file is a compact introduction to the training stack used in this repo.
It is not the detailed design spec.

## What We Are Building

The final goalkeeper policy is hierarchical:

1. A high-level policy picks a latent command `z`.
2. A frozen low-level motor controller maps `(body observation, z)` to joint targets.
3. The robot executes those targets in the tracking environment.

The key idea is separation of concerns:
- high level learns task strategy (when/where/how much),
- low level handles stable whole-body motor execution.

## Pipeline in Practice

1. Collect rollout data from tracking policies (`collect_rollouts.py`) and save `.npz` shards.
2. Train Stage-1 motor controller offline (`train_motor_controller_stage1.py`).
3. Save Stage-1 artifacts (`model_best.pt`, `model_last.pt`, `normalization_stats.npz`, `metadata.json`).
4. In expert/final tasks, load the frozen Stage-1 decoder and use latent actions through `MotorLatentAction`.

## Why This Matters

- Better stability: motor behavior is learned once and reused.
- Faster task iteration: experts/final policy operate in latent space.
- Cleaner debugging: dataset/model/runtime interfaces are explicit.

## Where to Read Next

- Expert-drill design: `expert_plan.md`
- Implementation-level motor-controller notes: `motion_controller.md`
