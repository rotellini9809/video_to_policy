# Motion Controller (Implementation + Concept)

This document explains the motion controller as implemented in this repo, and why it is structured this way.

## Math Box (Quick Reference)

Symbols:
- `o_t`: student motor observation at time `t`
- `o_{t:t+K}`: future observation window of length `K = k_future`
- `a_t`: clean action target at time `t`
- `z_t`: latent motor variable at time `t`
- `q`: posterior, `p`: prior

NPMP distributions:
- Prior: `p(z_t | z_{t-1})`
- Posterior: `q(z_t | o_{t:t+K}, z_{t-1})`

Decoder:
- `a_hat_t = D(o_t, z_t)`

KL term (per step):
- `KL_t = KL(q(z_t | o_{t:t+K}, z_{t-1}) || p(z_t | z_{t-1}))`

Training objective (chunk):
- `L_bc = (1/T) * sum_t ||a_hat_t - a_t||^2`
- `L_kl = (1/T) * sum_t KL_t`
- `L = L_bc + beta_kl * L_kl`

Runtime decode path:
- `o_t_norm = (o_t - mu_obs) / sigma_obs`
- `a_t_norm = D(o_t_norm, z_t)`
- `a_t = a_t_norm * sigma_act + mu_act`

## 1) Conceptual role in the stack

The controller is hierarchical:

1. High-level policy outputs a latent command `z`.
2. Stage-1 motion controller decodes `(motor_obs, z)` into joint targets.
3. Simulator/robot applies those targets.

Conceptually, this separates:
- strategy (high-level decision about behavior),
- motor execution (stable whole-body mapping to joints).

This is useful because strategy changes often, while low-level motor consistency should remain stable.

## 2) What Stage-1 model is actually trained

Code:
- `mjlab/src/mjlab/motor_controller_stage1/model.py`
- `mjlab/src/mjlab/motor_controller_stage1/trainer.py`

The default runtime-compatible model is `NPMPLatentMotorPrimitive` (`latent_type=npmp`).

### 2.1 NPMP architecture

For each timestep in a chunk:
- Prior network: `p(z_t | z_{t-1})`
- Posterior network: `q(z_t | obs_future_t, z_{t-1})`
- Decoder: `a_t = decoder(obs_t, z_t)`

Where:
- `obs_t`: current student observation
- `obs_future_t`: next `k_future` observations flattened
- `a_t`: predicted clean action (normalized in training space)

In code, this is implemented with:
- `self.prior` (MLP),
- `self.posterior` (MLP),
- `self.decoder` (ActionDecoder MLP).

### 2.2 Training objective

At training time:
- behavior cloning term: MSE between predicted and clean actions
- KL regularization: `KL(q || p)` per timestep

Total loss:
- `loss = bc_loss + beta_kl * kl_loss`

`beta_kl` can be warmed up over iterations.

### 2.3 Important train/runtime difference

During training, posterior and prior are used to shape latent dynamics.

During runtime in `MotorLatentAction`, only decoder path is used:
- normalize motor observation,
- call `model.decoder(obs_norm, z)`,
- denormalize to action space.

So runtime is deterministic conditional decoding from `(obs, z)`.

## 3) Motor observation and action pipeline at runtime

Code:
- `mjlab/src/mjlab/motor_controller_stage1/latent_action.py`

`MotorLatentAction.process_actions` does:

1. Validate latent action shape.
2. Build motor observation terms:
   - `base_lin_vel`
   - `base_ang_vel`
   - `joint_pos` (relative to defaults)
   - `joint_vel` (relative to defaults)
   - previous decoded `actions`
   - optional `command` (if layout requires it)
3. Normalize with `obs_mean/std` from Stage-1 run.
4. Decode with frozen Stage-1 decoder.
5. Denormalize with `act_mean/std`.
6. Apply scale/offset.

`apply_actions` then:
- compensates encoder bias,
- sends joint position targets to selected actuators.

## 4) Rollout ("rollour") pipeline used to train Stage-1

Code:
- `mjlab/src/mjlab/scripts/collect_rollouts.py`
- `mjlab/src/mjlab/motor_controller_stage1/dataset.py`
- `mjlab/src/mjlab/motor_controller_stage1/obs_views.py`

### 4.1 What is collected

Rollout collector runs a trained policy and stores shard files `rollouts_*.npz`.

Per step it now saves at least:
- `obs_student`
- `a_clean`
- `a_exec`
- `episode_id`
- `step_in_episode`
- `clip_id`
- `clip_len_steps`
- `phase_idx`
- `phase_norm`
- `steps_to_clip_end`
- `terminated`
- `truncated`
- `done_reason`

Common optional fields:
- `env_id`
- `noise_level_id`
- `noise_norm`
- `future_valid_len_hint`

Legacy `done` is not stored in shards anymore.

### 4.2 Why `obs_student` exists

Collector creates student obs via `build_student_obs(...)` and removes terms such as:
- `command`
- `motion_anchor_pos_b`
- `motion_anchor_ori_b`

This intentionally trains Stage-1 on a reduced motor-focused view.

### 4.3 Clip-aware rollout logic (Stage-1/NPMP friendly)

Collector is clip-aware and avoids invalid starts near clip tail:

- `min_remaining = stage1_chunk_len_hint + stage1_k_future_hint + stage1_start_margin`
- If `clip_len_steps >= min_remaining`: start is sampled uniformly in valid range.
- Else (short clips): start is forced to `0` (clip is still kept).

Termination is explicit:

- `terminated=true` for failure-like conditions (`fall`, `invalid_state`, `nan`, ...).
- `truncated=true` for non-failure boundary (`clip_end`, optional timeout).
- `done_reason` stores explicit reason (`clip_end`, `fall`, `invalid_state`, `timeout`, `nan`, ...).

Action targets vs execution:

- `a_clean`: noiseless target used for supervision.
- `a_exec`: action actually executed in env (`a_clean + noise`).
- Noise metadata can be logged per step/episode (`noise_level_id`, `noise_norm`).

### 4.4 Metadata contract

Collector writes `metadata.json` with:
- `collector_version`
- `control_dt` (expected `0.03`)
- `stage1_chunk_len_hint`
- `stage1_k_future_hint`
- `stage1_start_margin`
- noise config (`noise_std_default`, `noise_std_levels`, `noise_level_probs`)
- `obs_dim`, `act_dim`,
- observation view description (`obs_student_view`),
- run/source info.

Trainer writes additional Stage-1 metadata and stats:
- `normalization_stats.npz`,
- `model_best.pt` / `model_last.pt`,
- `metrics.csv`,
- `metadata.json`.

These are later required by runtime loader.

For code that still needs a boolean episode boundary, compute:
- `done = terminated | truncated`

## 5) How Stage-1 artifacts are loaded for experts/final policy

`MotorLatentAction` downloads from W&B run:
- `metadata.json`
- `normalization_stats.npz`
- checkpoint (`best`/`last`/`latest`)

Resolution sources:
- config `stage1_wandb_run_path`,
- env var `MJLAB_STAGE1_WANDB_RUN_PATH`,
- checkpoint selector (`stage1_checkpoint` or `MJLAB_STAGE1_CHECKPOINT`).

## 6) Hard contracts enforced by implementation

Runtime raises if:
- `latent_type` is not compatible (expects NPMP flow),
- Stage-1 `act_dim` != environment controlled action dimension,
- recovered observation layout does not match expected dims/terms,
- required artifacts are missing in W&B run.

This strictness is intentional: it prevents silent mismatch between collected data, trained model, and runtime env config.

## 7) Why this design works conceptually

The motion controller acts as a reusable motor manifold:
- `z` parameterizes behavior modes in a compact way,
- decoder enforces joint-level coherence conditioned on current body state,
- high-level policy explores/selects in latent space rather than raw joints.

Practical effect:
- better stability and smoother motion than direct high-level-to-joint mapping,
- easier transfer of motor competence across drills/tasks,
- clearer debugging boundaries (rollout data, Stage-1 training, runtime decoding).
