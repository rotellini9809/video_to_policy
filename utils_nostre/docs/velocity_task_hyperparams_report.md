# Velocity Task Hyperparameter Report

Focus task: `Mjlab-Velocity-Flat-Unitree-G1`

This report documents effective hyperparameters for the flat G1 velocity task, including inherited values from:

- base: `mjlab/src/mjlab/tasks/velocity/velocity_env_cfg.py`
- G1 rough override: `mjlab/src/mjlab/tasks/velocity/config/g1/env_cfgs.py` (`unitree_g1_rough_env_cfg`)
- G1 flat override: `mjlab/src/mjlab/tasks/velocity/config/g1/env_cfgs.py` (`unitree_g1_flat_env_cfg`)
- RL cfg: `mjlab/src/mjlab/tasks/velocity/config/g1/rl_cfg.py`

Task registration source:

- `mjlab/src/mjlab/tasks/velocity/config/g1/__init__.py`

## 1) Task IDs and runner

Registered G1 velocity tasks:

- `Mjlab-Velocity-Rough-Unitree-G1`
- `Mjlab-Velocity-Flat-Unitree-G1`

Runner class:

- `VelocityOnPolicyRunner`
- On save, it exports ONNX and attaches metadata.

## 2) RL (PPO) hyperparameters

From `unitree_g1_ppo_runner_cfg()`:

- actor network:
- hidden dims `(512, 256, 128)`
- activation `elu`
- stochastic `True`
- `obs_normalization=True`
- `init_noise_std=1.0`
- critic network:
- hidden dims `(512, 256, 128)`
- activation `elu`
- stochastic `False`
- `obs_normalization=True`
- `init_noise_std=1.0`
- PPO algorithm:
- `value_loss_coef=1.0`
- `use_clipped_value_loss=True`
- `clip_param=0.2`
- `entropy_coef=0.01`
- `num_learning_epochs=5`
- `num_mini_batches=4`
- `learning_rate=5e-4`
- `schedule=adaptive`
- `gamma=0.99`
- `lam=0.95`
- `desired_kl=0.01`
- `max_grad_norm=1.0`
- runner:
- `experiment_name="g1_velocity"`
- `save_interval=50`
- `num_steps_per_env=24`
- `max_iterations=30000`

## 3) Effective env config for `Mjlab-Velocity-Flat-Unitree-G1`

## 3.1 Simulation and episode

Base defaults:

- `sim.mujoco.timestep=0.005`
- `sim.mujoco.iterations=10`
- `sim.mujoco.ls_iterations=20`
- `sim.nconmax=35`
- `sim.njmax=1500`
- `decimation=4`
- `episode_length_s=20.0`

G1 rough overrides:

- `sim.mujoco.ccd_iterations=500`
- `sim.contact_sensor_maxmatch=500`
- `sim.nconmax=45`

G1 flat overrides (final for this task):

- `sim.njmax=300`
- `sim.mujoco.ccd_iterations=50`
- `sim.contact_sensor_maxmatch=64`
- `sim.nconmax=None`

## 3.2 Terrain

Base:

- terrain importer uses generator (`ROUGH_TERRAINS_CFG`)
- `max_init_terrain_level=5`

G1 rough:

- terrain curriculum enabled if generator exists

G1 flat (final):

- `terrain_type="plane"`
- `terrain_generator=None`
- removes `terrain_levels` curriculum term
- removes terrain scan sensor and observation terms

## 3.3 Entities, actions, sensors

Entities:

- robot entity is `get_g1_robot_cfg()`

Actions:

- `joint_pos` action term
- actuator names: `(".*",)`
- scale set to `G1_ACTION_SCALE`
- `use_default_offset=True`

Notes on `G1_ACTION_SCALE`:

- computed per actuator regex as `0.25 * effort_limit / stiffness`.

Sensors (effective flat task):

- rough adds:
- `feet_ground_contact`:
- primary body subtree pattern `^(left_ankle_roll_link|right_ankle_roll_link)$`
- secondary body `terrain`
- fields `("found", "force")`, `reduce="netforce"`, `track_air_time=True`
- `self_collision`:
- pelvis subtree vs pelvis subtree
- fields `("found",)`
- flat removes `terrain_scan` raycast sensor

## 3.4 Observations (actor/critic)

Base actor terms:

- `base_lin_vel` with uniform noise `[-0.5, 0.5]`
- `base_ang_vel` with uniform noise `[-0.2, 0.2]`
- `projected_gravity` with uniform noise `[-0.05, 0.05]`
- `joint_pos` with uniform noise `[-0.01, 0.01]`
- `joint_vel` with uniform noise `[-1.5, 1.5]`
- `actions`
- `command` (generated `twist` command)
- `height_scan` (removed in flat)

Base critic terms:

- all actor terms
- plus `foot_height`, `foot_air_time`, `foot_contact`, `foot_contact_forces`
- plus uncorrupted `height_scan` (removed in flat)

Corruption flags:

- actor: `enable_corruption=True` (train)
- critic: `enable_corruption=False`

G1 rough detail:

- `foot_height` site names set to `("left_foot", "right_foot")`

G1 flat final:

- `height_scan` removed from actor and critic

## 4) Commands and velocity randomization

Command term: `twist` (`UniformVelocityCommandCfg`)

Base settings:

- resampling interval `resampling_time_range=(3.0, 8.0)`
- `rel_standing_envs=0.1`
- `rel_heading_envs=0.3`
- `heading_command=True`
- `heading_control_stiffness=0.5`
- debug visualization enabled

Base command ranges (initial):

- `lin_vel_x=(-1.0, 1.0)`
- `lin_vel_y=(-1.0, 1.0)`
- `ang_vel_z=(-0.5, 0.5)`
- `heading=(-pi, pi)`

Sampling/update behavior (`UniformVelocityCommand`):

- each resample draws uniform `vx, vy, wz`
- heading target is sampled when heading mode is enabled
- heading-control envs: `wz` overwritten by clipped proportional heading error
- standing envs: full command set to zero
- optional init velocity injection controlled by `init_velocity_prob` (default `0.0`)

Command curriculum (`commands_vel`):

- stage 0: `lin_vel_x=(-1.0, 1.0)`, `ang_vel_z=(-0.5, 0.5)`
- after `5000*24=120000` steps: `lin_vel_x=(-1.5, 2.0)`, `ang_vel_z=(-0.7, 0.7)`
- after `10000*24=240000` steps: `lin_vel_x=(-2.0, 3.0)`
- `lin_vel_y` stays unchanged unless explicitly overridden by a stage

Flat play-mode override:

- `lin_vel_x=(-1.5, 2.0)`
- `ang_vel_z=(-0.7, 0.7)`

## 5) Randomization events

Base events:

- `reset_base` (reset mode):
- pose randomization:
- `x,y in [-0.5, 0.5]`
- `z in [0.01, 0.05]`
- `yaw in [-3.14, 3.14]`
- velocity range: `{}` (no added reset velocity randomization)
- `reset_robot_joints` (reset mode):
- position range `(0.0, 0.0)`
- velocity range `(0.0, 0.0)`
- `push_robot` (interval mode):
- interval `[1.0, 3.0] s`
- velocity disturbance ranges:
- `x,y in [-0.5, 0.5]`
- `z in [-0.4, 0.4]`
- `roll,pitch in [-0.52, 0.52]`
- `yaw in [-0.78, 0.78]`
- `foot_friction` (startup, domain randomization):
- absolute geom friction range `(0.3, 1.2)`
- shared across foot geoms
- `encoder_bias` (startup): bias range `(-0.015, 0.015)`
- `base_com` (startup, domain randomization):
- torso COM offset ranges:
- x `(-0.025, 0.025)`
- y `(-0.025, 0.025)`
- z `(-0.03, 0.03)`

G1 rough adjustments:

- `foot_friction` asset geom names set to G1 foot collision geoms
- `base_com` body name set to `("torso_link",)`

Play-mode behavior inherited from rough:

- actor corruption disabled
- removes `push_robot`
- clears curriculum
- adds `randomize_terrain` on reset
- sets effectively infinite episode length (`1e9`)

Note for flat play:

- because flat sets `terrain_type="plane"` and `terrain_generator=None`, terrain randomization/curriculum are effectively not used for rough terrain progression.

## 6) Rewards

Base reward terms (before G1 overrides):

- `track_linear_velocity`: weight `+2.0`, std `sqrt(0.25)`
- `track_angular_velocity`: weight `+2.0`, std `sqrt(0.5)`
- `upright`: weight `+1.0`, std `sqrt(0.2)`
- `pose`: weight `+1.0`
- `body_ang_vel`: weight `0.0` (placeholder)
- `angular_momentum`: weight `0.0` (placeholder)
- `dof_pos_limits`: weight `-1.0`
- `action_rate_l2`: weight `-0.1`
- `air_time`: weight `0.0` (placeholder)
- `foot_clearance`: weight `-2.0`
- `foot_swing_height`: weight `-0.25`
- `foot_slip`: weight `-0.1`
- `soft_landing`: weight `-1e-5`

G1-specific posture std maps:

- standing: `{".*": 0.05}`
- walking/running: joint-group specific regex std maps for hips, knees, ankles, waist, shoulders, elbows, wrists

G1 rough/final reward overrides:

- `body_ang_vel.weight = -0.05`
- `angular_momentum.weight = -0.02`
- `air_time.weight = 0.0`
- adds `self_collisions`: weight `-1.0` (sensor `self_collision`)
- reward term site/body bindings:
- `upright` and `body_ang_vel` use `torso_link`
- `foot_clearance`, `foot_swing_height`, `foot_slip` use `left_foot`, `right_foot`

## 7) Terminations

Effective terms:

- `time_out`
- `fell_over` via bad orientation with `limit_angle=70 deg`

## 8) Viewer

- origin type: asset body
- entity: `robot`
- G1 rough sets viewer body to `torso_link`
- distance `3.0`, elevation `-5.0`, azimuth `90.0`

## 9) Summary of velocity-randomization knobs

If your goal is to tune velocity randomization specifically, the main knobs are:

- command ranges:
- `commands.twist.ranges.lin_vel_x`
- `commands.twist.ranges.lin_vel_y`
- `commands.twist.ranges.ang_vel_z`
- command sampling regime:
- `resampling_time_range`
- `rel_standing_envs`
- `rel_heading_envs`
- `heading_control_stiffness`
- command curriculum stages (`curriculum.command_vel.velocity_stages`)
- external perturbation:
- `events.push_robot.params.velocity_range`
- reset randomization:
- `events.reset_base.params.pose_range`
- optional initial-velocity injection:
- `commands.twist.init_velocity_prob` (default `0.0`)
