# E2 Ball Launcher Report (Current Implementation)

This report reflects the centralized launcher currently used by E2:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/launcher.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e2_stand_block/mdp.py`
- `mjlab/src/mjlab/scripts/validate_gk_e2_launcher.py`

## 1) Architecture and API

Launcher classes:
- `GoalkeeperBallLauncherCfg`
- `GoalkeeperBallLauncher`

Core API:
- `reset(env_ids)`: samples and stores full per-env launch plan once at episode reset.
- `step(time_s)`: applies scheduled launch and optional deflection events.
- `validation_report()` and `mode_histogram()`: diagnostics for distribution/constraints.

Vectorization:
- Sampling and event handling are batched in torch over all envs.
- No Python loops over env indices in reset/step paths.

## 2) Per-Episode Flow in E2

At reset:
1. Sample launch family by weighted categorical.
2. Sample spawn, target, launch velocity, estimated `t_goal`, launch delay.
3. Sample optional rare deflection schedule and delta-v.
4. Write ball root state at sampled spawn with zero linear/angular velocity.

During stepping:
- Launch when `time_s >= launch_time_s` and not launched yet.
- Deflect once when `time_s >= deflect_time_s` and env has deflection.
- Velocity writes are clamped to launcher safety limits.

## 3) E2 Default Mix and Core Constraints

E2 config defaults:
- Family weights `(ground, one_bounce, lob_chip, cross, long_driven) = (0.50, 0.15, 0.15, 0.10, 0.10)`
- Delay range `U(0.10, 0.35)` s
- Commit-window band `t_goal in [0.35, 1.00]` s
- Rare deflection probability `0.06`
- Deflection timing after launch `U(0.08, 0.22)` s
- Deflection magnitude `U(0.35, 1.25)` m/s

Global clamps:
- `max_speed = 8.5` m/s
- `max_abs_vz = 5.5` m/s
- `min_toward_goal_speed = 0.8` m/s
- Rejection iterations: `4`

Notes on `long_driven`:
- This family is intended to represent **faster launches from a farther origin** (long-range hit / hard throw).
- It still respects the same E2 commit-window constraint (`t_goal` band), so it remains a “commit now” drill rather than a positioning drill.

## 4) Launch Families Implemented

### 4.1 `ground_shot` (family 0)
- Ground spawn (`z = ball_radius`) from near/far depth + center/left/right channels.
- Target sampled on goal plane using near-post/far-post/center modes.
- Mostly low z targets; optional mid z bucket.
- Tiered `t_goal` sampling enforces E2 commit-window behavior.

### 4.2 `one_bounce_shot` (family 1)
- Ground spawn; low goal-plane target.
- XY from target/time; `v_z` sampled from conservative positive range.
- Extra validity check enforces first-bounce fraction before/near goal.

### 4.3 `lob_chip` (family 2)
- Ground spawn with airborne goal target up to near-crossbar band.
- Ballistic velocity from sampled target + time-of-flight.
- Target z capped by `goal_z_max - ball_radius`.

### 4.4 `cross` (family 3)
- Wing spawn (left/right wide channels).
- Target corridor supports corridor/far-post patterns.
- Driven vs lofted variants via different TOF and target-z bands.
- Uses ballistic target+TOF solve.

### 4.5 `long_driven` (family 4) — NEW
Purpose: represent **harder, faster launches from farther distance** while keeping E2’s “commit window” nature.

Behavior:
- Spawn is sampled from a **farther depth band** than `ground_shot` (long-range origin zones).
  - Typically more central, but can include mild lateral offset for angled long shots.
- Targeting is on-goal (same goal-plane targeting modes as `ground_shot`), with emphasis on:
  - low and mid-height targets (depending on desired difficulty),
  - near-post/far-post variety for reaction training.
- Velocity selection is biased to produce **higher pace** while staying inside:
  - global `max_speed` clamp,
  - E2 `t_goal` commit band.
- Optional: raise the *family-specific* “minimum toward-goal speed” used during sampling/validity so `long_driven` never collapses into slow long shots.

Validity intent:
- `long_driven` should almost always “feel fast” even though it spawns farther away.
- If a sampled far spawn would require violating `max_speed` to meet `t_goal`, the sampler should adjust (or reject/resample) so the final sample still respects both constraints.

## 5) Rare Deflection Modifier

- After launch, with low probability per env, schedule one deflection event.
- At deflection time apply one `delta_v` then mark deflection done.
- Direction sampling includes configurable bias away from goal side.

## 6) Goal Plane and Direction Assumptions in E2

E2 uses:
- `goal_toward_positive_x = True`
- goal plane aperture:
  - `x = 7.0`
  - `y center = 0.0`, `half width = 1.30`
  - `z range = [0.0, 1.85]`

These parameters drive both:
- goal detection logic in command/reward/termination
- launcher targeting and time-to-goal validity checks

## 7) Visual/Debug Aids Coupled to E2

- Goal plane is visible in scene through non-colliding overlay geom.
- Debug visualizer in task draws:
  - goal plane wire rectangle
  - ball velocity arrow
  - goal cue sphere (green normally, red flash on goal detection)
- Keeper area and hard-area overlays are also visible in field spec.

## 8) Validation Script

Script:
- `mjlab/src/mjlab/scripts/validate_gk_e2_launcher.py`

What it checks:
- histogram of sampled families over many resets (now includes `long_driven`)
- pass rate for speed/vz/toward-goal/t_goal constraints
- step-event sanity for launch and deflection scheduling

Example run:
- `uv run python src/mjlab/scripts/validate_gk_e2_launcher.py --num-resets 200 --num-envs 512`