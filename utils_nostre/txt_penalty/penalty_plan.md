# Penalty Expert – P1 SetShot Plan

This doc is the working plan for the **Penalty (SetShot)** expert.
Goal: train a striker policy (latent actions → Stage-1 decoder) that performs **one clean penalty kick** aimed **high + lateral** (near the crossbar corner) with strong stability.

---

## 1) Coordinate conventions

- Field is centered at origin.
- Goal plane: **x = GOAL_X_LINE** (typically `+7.0`).
- A goal is scored if the ball crosses the goal plane inside the goal mouth.

### Goal mouth check (3D)
Ball is a goal if:
- `x >= GOAL_X_LINE`
- `|y| <= GOAL_HALF_WIDTH` (≈ 1.55)
- `goal_z_min <= z <= goal_z_max` (≈ 0.0 … 1.85)

---

## 2) Episode constraints

- **Horizon:** 6.0 s max.
- **No goal termination:** scoring does **not** end the episode.
  - Reason: allow realistic follow-through and avoid learning “freeze on score”.
  - Requirement: all goal rewards must be **event-based** (pulse once) to prevent reward blow-up.
- **One touch:** terminate on the **second** foot–ball touch.
- **Out of play:** terminate when the ball exits the 14×9 playable rectangle, or crosses the end line **outside** the goal opening, or crosses inside the goal opening but **over/under** the scoring aperture.
- **Falls:** terminate if the robot is down for consecutive steps.

---

## 3) Aim-point method (high + lateral)

We define a fixed aim point on the goal plane:
- `aim_x = GOALPOST_X` (≈ 7.3)
- `aim_y = 1.15` (absolute value; sign indicates left/right)
- `aim_z = 1.55`

### Generalize left/right
Do **not** write `±1.15` in Python.
Instead, store `aim_y = 1.15` in config and choose the sign at reset time:
- either deterministic by env id (half envs left, half right)
- or random each reset (recommended)

---

## 4) Reward philosophy

Use a **two-layer** reward:

### Dense shaping (helps learning start)
- yaw alignment to the aim direction
- approach/behind-ball positioning
- strike event (first touch)
- ball velocity toward aim (3D)
- in-flight high+side shaping (moderate weight)

### Sparse event rewards (define success)
- `goal_event`: 1 only on the step the ball first crosses the goal plane in the mouth
- `goal_high_corner_event`: goal_event AND (high + lateral thresholds)
- `goal_bad_event`: goal_event AND (low or central)

Important: **do not** use dense goal rewards if you don’t terminate on goal.

---

## 5) Debug visibility

Add **P1 test walls** around the 14×9 rectangle and a shaded overlay for allowed striker area.
This makes it obvious when the ball is out-of-play and prevents silent coordinate mistakes.
