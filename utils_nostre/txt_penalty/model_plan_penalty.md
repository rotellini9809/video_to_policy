# Penalty RL – Short Introduction

The penalty expert is trained in the same hierarchical stack used across the repo:

1. A high-level policy outputs a latent command `z`.
2. A frozen Stage‑1 motor controller decodes `(motor_obs, z)` into joint targets.
3. The robot executes those targets in simulation.

## Why this helps

- **Stability:** Stage‑1 handles balance and coordinated whole‑body motion.
- **Faster iteration:** the penalty expert learns *what* to do (approach/kick/aim) without relearning low-level locomotion.
- **Cleaner debugging:** observation/action interfaces are explicit and checked (`strict_obs_layout`).

## Penalty-specific constraints

- 6 second horizon.
- One-touch (terminate on second contact).
- Out-of-play termination for the ball.
- No termination on goal; goal rewards must be event-based.
