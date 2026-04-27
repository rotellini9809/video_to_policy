# Goalkeeper Experts – Drill Environment Plan (No Dives)

This canvas is a working plan for the active goalkeeper expert drill environments in this repo: **E1** and **E2**. Earlier legacy task generations and `E3` have been removed.

---

## 0) Shared conventions (used by every expert env)

### Coordinate frame
- Goal plane at **x = GOALLINE_X**.
- A goal is conceded if the **ball crosses x ≥ GOALLINE_X** inside the goal mouth.

### Goal mouth (2.5D)
The scoring aperture on the goal plane:
- **x ≥ GOALLINE_X**
- **|y| ≤ GOAL_HALF_WIDTH**
- **0 ≤ z ≤ GOAL_HEIGHT**

Equivalent set:
- **M_goal = {(x,y,z) : x ≥ GOALLINE_X, |y| ≤ GOAL_HALF_WIDTH, 0 ≤ z ≤ GOAL_HEIGHT}**

### Goalkeeper Area (GK must stay here)
A rectangular box in front of the goal:
- **x ∈ [GOALLINE_X − GK_DEPTH, GOALLINE_X]**
- **|y| ≤ GK_HALF_WIDTH**

E1-aligned defaults:
- **GK_DEPTH = 1.0 m**
- **GK_HALF_WIDTH = 2.0 m**
- (equivalently: **KEEPER_AREA_BOUNDS = (GOALLINE_X − 1, GOALLINE_X, −2, 2)**)

Penalties:
- Soft penalty near boundary
- Strong penalty outside

### Danger Zone (immediate scoring threat)
A smaller region close to the goal mouth:
- **x ≥ GOALLINE_X − DZ_DEPTH**
- **|y| ≤ DZ_WIDTH**
- Optional: only active if **v_x > 0** (ball moving toward goal)

### Shared termination (global)
- **Goal conceded** (ball crosses goal plane in mouth)
- **Timeout** (short horizons per drill)
- **Catastrophic fall** 

---

## 1) Shared ball tools

### Shot sampler (aim-point method)
1. Sample an aim point on the goal plane: (y_aim, z_aim)
2. Spawn ball at (x0, y0, z0) with x0 < GOALLINE_X
3. Sample speed v
4. Set direction toward aim point

### Delayed launch protocol (recommended for E1)
Used to give the keeper a brief “set” moment before the shot begins.
- Phase A (pre-shot): ball is visible and still (or tiny drift) for **0.2–0.5 s**
- Phase B (shot start): ball is launched

How to use it:
- **E1 Repositioning:** use delayed launch often; optionally **terminate the drill at shot start** (or within a very short window) to isolate readiness rather than saving.

Suggested mix:
- **E1:** 70–80% delayed launch, 20–30% immediate (optional)

### On-target classifier (privileged)
Compute intersection at goal plane:
- t_goal = (GOALLINE_X − x0) / v_x
- y_hit = y0 + v_y · t_goal
- z_hit = z0 + v_z · t_goal

On-target if:
- t_goal > 0
- |y_hit| ≤ GOAL_HALF_WIDTH
- 0 ≤ z_hit ≤ GOAL_HEIGHT

Use this to:
- Bias E2 toward on-target shots
- Avoid rewarding “doing nothing” on off-target shots



---

## 2) Expert drill environments

### Semantic definition of the experts (what each one *means*)
These definitions are the *behavioral intent* of each expert. The drill environment below is then designed to isolate that intent.

- **E1 Repositioning (Ready + Track, no translation):** Stay in a goalkeeper-ready stance, keep trunk upright and **yaw aligned to the ball**, make only micro-adjustments. Translation is treated as an error.

- **E2 Block Deflect (No-dive save mechanics):** **Stop it now** (commit / save mechanics). The ball is close enough / fast enough that repositioning is mostly over; the key is body barrier + contact mechanics. Success is measured by preventing a goal and producing a good deflection away from goal. You’re training bracing + limb placement + torso orientation (still no dives), not “nice shuffles”.

Each drill must define:
- Reset distribution (keeper, ball)
- Horizon: **max horizon (T_max)** + **event-based early termination**
- Observations (privileged allowed)
- Termination conditions (drill-specific)
- Rewards (small set, outcome-focused)

---

## E1 Repositioning (Ready + Track, no translation)

### Purpose
Hold a goalkeeper-ready stance, keep trunk upright and **yaw aligned to the ball**, and make only micro-adjustments. **Base translation is treated as an error.**

### Reset distribution
- **Keeper:** standing in the GK area (typically centered), ready stance, yaw noise ±10°, small joint/velocity noise.
- **Ball:** **physical and colliding**, but **NOT a committed shot**.
  - Ball placed in front of the keeper with mild variation (e.g., x in [GOALLINE_X−6, GOALLINE_X−3], y in [−2, +2]).
  - Ball motion is produced by the **E1-only ball launcher** (kick/impulse), described below.

### E1-only ball launcher (kick-only + no-bounce sideline curbs)
Goal: mimic “in-play” slow ball motion (passes / gentle rolls / settle) while keeping the drill about *readiness*, not saving.

**A) sideline curbs (containment, no bouncy rebounds)**
- Current E1 implementation uses a **14 x 9 m playable boundary** (half extents: x=±7.0, y=±4.5), with walls **centered on the boundary line**.
- Implemented wall layout is **6 box geoms**:
  - 2 continuous long-side walls at **y = ±4.5**
  - 4 short-side segmented walls at **x = ±7.0**
  - central opening on each short side (goal side) with half-width **1.55 m**
- Current test geometry:
  - Height: **0.07 m**
  - Thickness: **0.16 m**
  - Visible for debugging (semi-transparent red)
- Contact tuning (dead, non-bouncy):
  - high sliding friction + some rolling resistance (currently **2 0.02 0.002**)
  - stable **solref/solimp** to avoid jitter (currently **0.02 1.5** and **0.9 0.95 0.001 0.5 2.0**)
- Collision filtering:
  - Desired final behavior is curb collision **only with the ball**
  - Current implementation still needs explicit ball-only `contype/conaffinity` filtering

**B) Kick sampler (single kick, no trajectories)**
Sample one of these per episode:
- **55% Dead ball:** v = 0 (or tiny drift).
- **35% Slow lateral roll:** apply one kick mostly along ±y.
- **10% Dribble-settle:** one kick + optional single soft “tap” later.

Kick details:
- Direction: biased lateral (choose left/right 50/50), angle around **±90°** with noise (e.g., ±(90° ± 20°)).
- Speed band (non-threatening): **0.4–1.6 m/s** (tune to your friction).
- **Anti-shot constraint (keep E1 pure):**
  - Clamp the forward-to-goal component so it’s never a committed shot.
  - If goal is at +x: enforce **v_x ≤ 0.2–0.3 m/s** (or even v_x ≤ 0).
- Optional “touch” (dribble feel):
  - With low probability, at t ∈ [0.6, 1.8] s apply a small Δv (0.2–0.6 m/s), again lateral-biased.

**C) Delayed kick variant (readiness timing)**
- Ball stays still for **0.2–0.5 s**, then the kick is applied.
- Optional termination: end at kick-start (or shortly after) to train “set → react” timing without turning into E2.

### Environment mechanics (what the drill isolates)
- No fast on-target shots in this drill.
- Translation is strongly penalized to keep E1 strictly stationary/readiness-focused.
- Randomization is mild: small pose noise, small ball drift / kick variation, small sensor noise.
- Sideline curbs keep the ball in-play **without** hard resets while staying **non-bouncy**.

### Horizon
- **Max horizon (T_max): 3.0 s**

### Observations
- Proprioception
- Ball relative position and velocity
- Privileged (optional): desired yaw direction and/or a shot-imminent timer

### Reward
- + yaw alignment to ball (e.g., cos(yaw_error))
- + upright / height window / stability
- − strong penalty for base translation (|v_xy| and |Δx,Δy|)
- − leave GK area
- − fall

### Termination
- Timeout
- Leave GK area (optional hard)
- Fall (optional hard)

Notes:
- Make stepping unambiguously bad here so E1 stays “set & square”.

---

## E2 Block Deflect (No-dive save mechanics)

### Purpose
**Stop it now** (commit / save mechanics). The ball is close enough / fast enough that repositioning is mostly over; the key is **body barrier + contact mechanics**.

### Reset distribution
- **Keeper:** standing and *roughly positioned* (small lateral error). This drill assumes the keeper is already roughly positioned.
  - Bias resets toward ready/post-adjustment poses (small pose noise) rather than arbitrary contortions.
- **Ball:** mostly on-target **ground shots**, closer and faster than what you’d use for any positioning drill.
  - Choose spawns so time-to-goal is in a commit band (e.g., a few tenths of a second to ~1 s).

### Environment mechanics (commit window)
- Ball is physical and colliding.
- Keep the drill focused on contact mechanics:
  - Early termination is encouraged on **first contact** or **goal-plane crossing**.
  - Avoid rewarding positioning strongly here.
- Randomize shot angles and speeds within a no-dive-reachable band for this iteration.

### Horizon
- **Max horizon (T_max): 2 s**
- Typically ends earlier on first contact or goal-plane crossing

### Observations
- Proprioception
- Ball relative position and velocity
- Privileged (optional): t_goal only

### Reward
- − big if goal
- + success if ball does not cross goal plane by end
- + bonus if post-contact ball velocity points away from goal
- − leave GK area
- − fall

### Termination
- Goal / timeout
- Optional: stop after first contact to isolate “block” and keep the task focused on the save event.

---

## 3) Drill hyperparameters to lock early

- Max horizons (T_max) + event-based early termination:
  - E1: 3.0 s
  - E2: 2 s

- Launch / reset distributions:
  - E1: visual-only / slow ball, **optionally with delayed launch (0.2–0.5 s pre-shot) terminating at shot start**
  - E2: committed, mostly on-target ground shots (no-dive reachable band)

- Collisions:
  - E1/E2: physical and colliding

- Constraints:
  - Strong GK-area penalties across all drills
  - E1 has extra translation penalty
