# MJLAB / VIDEO_TO_POLICY - General API

## Velocity

```bash
uv run train Mjlab-Velocity-Flat-Unitree-G1 --env.scene.num-envs 4096

uv run play Mjlab-Velocity-Flat-Unitree-G1 \
  --wandb-run-path <entity>/mjlab/<run_id>
```

## Tracking (Booster T1_23)

### 1) CSV -> NPZ artifact (required before tracking training)

```bash
# Single CSV (Booster T1 23 dof)
uv run src/mjlab/scripts/csv_to_npz_booster_t1_23dof.py \
  --input-file human_to_robot_output/booster_t1/my_motion.csv \
  --input-fps 30 \
  --output-fps 50

# Batch folder (recursive)
uv run src/mjlab/scripts/csv_to_npz_booster_t1_23dof.py \
  --root-dir human_to_robot_output/booster_t1 \
  --input-fps 30 \
  --output-fps 50

# Optional mirror generation (single file)
uv run src/mjlab/scripts/mirror_csv_booster_t1_23dof.py \
  --input-file human_to_robot_output/booster_t1/my_motion.csv

# Optional mirror generation (batch folder)
uv run src/mjlab/scripts/mirror_csv_booster_t1_23dof.py \
  --root-dir human_to_robot_output/booster_t1
```

### 2) Train

```bash
uv run train Mjlab-Tracking-Flat-Booster-T1_23 \
  --registry-name <entity>/csv_to_npz/<artifact_name>:v0 \
  --env.scene.num-envs 4096 \
  --agent.max_iterations 15000 \
  --agent.run_name <run_name>
```

### 3) Play

```bash
uv run play Mjlab-Tracking-Flat-Booster-T1_23 \
  --wandb-run-path <entity>/mjlab/<run_id>
```

### 4) Batch tracking training

```bash
artifacts=(
  "<entity>/wandb-registry-Motions/clip_run_01:v0"
  "<entity>/wandb-registry-Motions/clip_run_02:v0"
  "<entity>/wandb-registry-Motions/clip_run_03:v0"
)

for artifact in "${artifacts[@]}"; do
  uv run train Mjlab-Tracking-Flat-Booster-T1_23 \
    --registry-name "$artifact" \
    --env.scene.num-envs 4096 \
    --agent.num_steps_per_env 25 \
    --agent.max_iterations 15000 \
    --agent.run_name "$artifact"
done
```

## Stage-1 Motor Controller

### 1) Rollout collection from a tracking policy

```bash
uv run collect-rollouts Mjlab-Tracking-Flat-Booster-T1_23 \
  --wandb-run-path <entity>/<project>/<run_id> \
  --num-episodes 200 \
  --num-envs 64 \
  --output-dir ./data/motor_controller_rollouts/training_dataset1
```

Batch:

```bash
rollout_runs=(
  "<entity>/<project>/<run_id_01>"
  "<entity>/<project>/<run_id_02>"
  "<entity>/<project>/<run_id_03>"
)

DATASET_ROOT=./data/motor_controller_rollouts/training_dataset1

for run_path in "${rollout_runs[@]}"; do
  uv run collect-rollouts Mjlab-Tracking-Flat-Booster-T1_23 \
    --wandb-run-path "$run_path" \
    --num-episodes 200 \
    --num-envs 64 \
    --output-dir "$DATASET_ROOT"
done
```

Batch from W&B workspace/group (no explicit run list):

```bash
uv run collect-rollouts Mjlab-Tracking-Flat-Booster-T1_23 \
  --wandb-workspace <entity>/<project> \
  --wandb-group <group_name> \
  --num-episodes 200 \
  --num-envs 64 \
  --output-dir ./data/motor_controller_rollouts/training_dataset1
```

### 2) Train Stage-1

NPMP (recommended):

```bash
uv run train-motor-stage1 \
  --data-root ./data/motor_controller_rollouts/training_dataset1 \
  --latent-type npmp \
  --sample-mode chunk \
  --chunk-len 32 \
  --k-future 10 \
  --max-iters 5000 \
  --val-frac 0.1 \
  --seed 0 \
  --run-name final_test_npmp_chunk32_k10_seed0 \
  --beta-kl-end 1e-3 \
  --beta-kl-warmup-iters 2000 \
  --log-every 50
```

VAE-lite (step mode):

```bash
uv run train-motor-stage1 \
  --data-root ./data/motor_controller_rollouts/training_dataset1 \
  --latent-type vae \
  --sample-mode step \
  --k-future 10 \
  --max-iters 200
```

Dry-run:

```bash
uv run train-motor-stage1 \
  --data-root ./data/motor_controller_rollouts/training_dataset1 \
  --latent-type npmp \
  --sample-mode chunk \
  --chunk-len 32 \
  --k-future 10 \
  --dry-run
```

### 3) Evaluate / play Stage-1

```bash
# Metrics-only eval (no render)
uv run eval-motor-stage1 \
  --wandb-run-path <entity>/motor_controller_stage1/<run_id> \
  --num-steps 5000 \
  --num-envs 32 \
  --checkpoint best

# Render
uv run play-motor-stage1 \
  --wandb-run-path <entity>/motor_controller_stage1/<run_id> \
```

Useful env vars:

```bash
export MJLAB_MOTOR_CONTROLLER_TASK_ID=Mjlab-Tracking-Flat-Booster-T1_23
export MJLAB_MOTOR_CONTROLLER_MOTION_FILE=/path/to/motion.npz
export MJLAB_STAGE1_WANDB_RUN_PATH_GOALKEEPER=<entity>/motor_controller_stage1/<run_id>
export MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY=<entity>/motor_controller_stage1/<run_id>
```

If you start MuJoCo with `utils_nostre/mujocolab_start.sh`, set them once in:

```bash
cp utils_nostre/stage1_expert_paths.env.example utils_nostre/stage1_expert_paths.env
# then edit utils_nostre/stage1_expert_paths.env with your run ids
./utils_nostre/mujocolab_start.sh
```

## Push GetUp

```bash
uv run train Mjlab-PushGetUp-Flat-Booster-T1_23 \
  --env.scene.num-envs 4096

uv run play Mjlab-PushGetUp-Flat-Booster-T1_23 \
  --wandb-run-path <entity>/mjlab/<run_id>

uv run python -m mjlab.scripts.play_push_getup \
  --viewer native \
  --wandb-run-path <entity>/mjlab/<run_id>
```

## Human to Robot

```bash
cd human_to_robot

# Single video (from videos[] in config.yaml)
python video_to_robot.py config.yaml --rewrite

# Batch folder
python batch_video_to_robot.py /abs/path/to/video_folder config.yaml

# Batch with forced rewrite
python batch_video_to_robot.py /abs/path/to/video_folder config.yaml --rewrite
```

## Git workflow (submodule)

```bash
# Inside mjlab: always work on main
cd mjlab
git switch main
git pull --ff-only

# Commit/push mjlab
git add .
git commit -m "Describe your change"
git push --force-with-lease origin main

# Update parent repo pointer
cd ..
git add mjlab
git commit -m "Update mjlab submodule"
git push
```
