# E1 Ball Launcher Report (Aligned to Current Implementation)

This report reflects the code currently implemented in:
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/config/t1_23dof/env_cfgs.py`
- `mjlab/src/mjlab/tasks/goalkeeper_experts/e1_set_square/mdp.py`
- `mjlab/src/mjlab/asset_zoo/robocup_assets/ball/ball.xml`

## 1) Per-Episode Execution Flow

At reset (`set_square` command):
1. Keeper pose is reset.
2. Ball pose is reset.
3. Launcher mode and its schedule are sampled once.

During simulation:
- If ball touches an E1 curb wall, ball velocity is set to zero and all future dribble taps are canceled.
- Pending main kick is applied when `time_s >= kick_time`.
- Pending dribble taps are applied when `time_s >= next_tap_time`.

## 2) Ball Asset and Contact Setup

E1 uses a physical colliding free ball (`soccer_ball`), not a marker.

Ball collision geom:
- radius `0.11 m` (diameter `0.22 m`)
- `friction="0.8 0.005 0.0001"`
- `solref="0.02 1"`
- `solimp="0.9 0.95 0.001"`

## 3) E1 Curbs / Walls (Current Geometry and Behavior)

Boundary:
- 14 x 9 m playable bounds (half extents `x=+-7.0`, `y=+-4.5`)
- 6 box walls:
  - 2 long-side walls at `y = +-4.5`
  - 4 short-side segments at `x = +-7.0`
  - short sides leave central goal opening with half-width `1.55 m`

Current wall tuning:
- height `0.07 m`
- thickness `0.16 m`
- `friction=(1.2, 0.02, 0.002)`
- `solref=(0.02, 1.5)`
- `solimp=(0.9, 0.95, 0.001, 0.5, 2.0)`

Ball-curb contact handling:
- Contact sensor explicitly matches `soccer_field:e1_wall_*` vs `soccer_ball:ball_collision`.
- On detected contact, code stops the ball and disables future taps.

Important:
- Wall geoms are still default colliders (no global ball-only `contype/conaffinity` filtering on the walls themselves). The ball-only behavior is enforced for launcher logic via the dedicated contact sensor.

## 4) Keeper Spawn

Keeper spawn ranges:
- `x in [6.8, 7.2]`
- `y in [-0.6, 0.6]`

## 5) Ball Spawn Randomization

## 5.1 XY Spawn
Ball spawns relative to keeper spawn:
- `forward ~ U(3.0, 11.0)`
- `lateral ~ U(-3.8, 3.8)`
- `ball_x = keeper_x - forward`
- `ball_y = keeper_y + lateral`

Approx world-frame range:
- `ball_x in [-4.2, 4.2]`
- `ball_y in [-4.4, 4.4]`

## 5.2 Z Spawn
Base sampling:
- `z_min = 0.11`
- `z = z_min + Exp(scale=0.08)`
- clipped to `z <= 0.35`
- optional debug fixed-z override (`False` by default)

Mode-dependent override after base spawn:
- dead mode: forced to ground (`z = 0.11`)
- dribble mode: forced to ground (`z = 0.11`)
- lateral mode: keeps base exponential/capped z

## 5.3 Initial Ball State
- Quaternion reset to identity.
- Linear/angular velocity reset to zero before launcher impulses.

## 6) Launcher Mode Probabilities

Top-level split:
- dead: `40%`
- lateral: `40%`
- dribble: `20%` (remainder)

Mode IDs:
- `0 = dead`
- `1 = lateral`
- `2 = dribble`

## 7) Mode Details

## 7.1 Dead Mode (40%)
Inside dead mode:
- with probability `0.20`, sample a tiny drift kick
- otherwise remain fully still

Drift speed:
- `0.02 .. 0.10 m/s`

Effective percentages:
- dead fully still: `40% * 80% = 32%`
- dead tiny drift: `40% * 20% = 8%`

## 7.2 Lateral Mode (40%)
- One main kick is always sampled.
- Main kick is immediate (`kick_time = 0.0`).

## 7.3 Dribble Mode (20%)
- One main kick immediate at `t=0`.
- Additional taps are always scheduled.

Tap schedule:
- `N_taps ~ randint[2, 5]` inclusive
- first tap time `U(0.6, 1.8)`
- subsequent tap intervals `U(0.20, 0.80)`
- each tap speed `0.2 .. 0.6 m/s`
- tap direction is sampled around previous push direction

Note:
- If episode terminates early, not all scheduled taps may execute.
- If curb contact happens, remaining taps are canceled.

## 8) Direction Randomization

Main kick (`_sample_lateral_velocity`):
- speed sampled from configured range
- random side sign (`+-1`, 50/50)
- angle `= side * 90deg + noise`
- `noise ~ U(-75deg, +75deg)`
- `v_z = 0`

Dribble taps (`_sample_velocity_around_mean_direction`):
- mean direction = previous push direction
- add `U(-75deg, +75deg)` noise around that mean
- `v_z = 0`

## 9) Anti-Shot Constraint

Defended goal side is configured as `+x`.

Clamp:
- `v_x <= 0.2` toward goal

Clamp is applied to:
- sampled kick velocities
- sampled tap delta-v
- ball velocity after additive tap updates
- explicit kick-set velocity path

## 10) Timing Resolution

Launcher timing uses RL step clock:
- `time_s = episode_length_buf * step_dt`
- event triggers use `time_s >= scheduled_time`

Current base sim settings:
- `sim timestep = 0.005`
- `decimation = 4`
- `step_dt = 0.02 s` (about 20 ms timing quantization)

## 11) Episode/Hold Behavior

- Launcher is sampled once per episode (`resampling_time_range=(1e9, 1e9)`).
- Episode length is `5.0 s`.

## 12) Ball Observations Used by Policy

Actor and critic include:
- `target_dir_xy`
- `ball_pos_rel_xyz`
- `ball_vel_rel_xyz`

## 13) Current Gaps vs Original E1 Plan

1. Episode length is `5.0 s` (plan target was `3.0 s`).
2. Dead mode still includes optional tiny drift (`20%` inside dead mode).
3. Delayed-kick variant is not implemented; launcher kicks are immediate.
4. Anti-shot is soft cap (`v_x <= 0.2`), not strict `v_x <= 0`.
5. Physical wall collisions are not globally ball-only filtered; wall-stop logic is ball-specific through the contact sensor.
