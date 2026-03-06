# Penalty Expert Pipeline (Start → Finish)

Questa guida è una checklist **copy‑paste** per:
1) creare / registrare le motion,
2) allenare **Tracking**,
3) collezionare rollouts,
4) allenare **Stage‑1 Motor Controller**,
5) allenare l’**Expert Penalty**,
6) **vedere il risultato** (play) + (opzionale) eval e rollouts expert.

> Convenzioni:
> - `$WANDB_ENTITY` = la tua entity W&B (es. `fratelligpt-sapienza-universit-di-roma-org`)
> - `<GROUP_NAME>` = nome group delle run Tracking
> - `<RUN_ID>` = id run W&B
> - Sei in Italia (timezone Rome) ma qui non serve.

---

## 0) Avvio Docker + W&B env

### 0.1 Verifica file env (host)
- `utils_nostre/wandb_credentials.env`
- `utils_nostre/stage1_expert_paths.env`  
  Deve contenere (almeno):
  - `MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY=...` (lo aggiornerai dopo)

### 0.2 Avvia il container (host, da root `video_to_policy/`)
```bash
./utils_nostre/mujocolab_start.sh
```

---

## 1) Metti i CSV delle motion (host)

Metti i tuoi CSV (29 clip, ≤5s) in:
```text
video_to_policy/human_to_robot/output/mujoco_csv/penalty/
  clip_01.csv
  clip_02.csv
  ...
```

Dentro container li vedi in:
```text
/app/human_to_robot_output/penalty/
```

---

## 2) CSV → NPZ (e mirror) (container)

Da `/app` nel container:

### 2.1 Converti CSV in NPZ
```bash
uv run src/mjlab/scripts/csv_to_npz_booster_t1_23dof.py \
  --root-dir human_to_robot_output \
  --input-fps 30 \
  --output-fps 50
```

### 2.2 (Consigliato) Genera mirror
```bash
uv run src/mjlab/scripts/mirror_csv_booster_t1_23dof.py \
  --root-dir human_to_robot_output
```

> Dopo questo step, le motion saranno pronte/registrate come artifact (dipende dallo script).  
> Se usi una lista “registry name”, metti i nomi in un `.txt` come per GK.

---

## 3) Train Tracking per ogni motion (container)

### 3.1 Esempio batch (lista artifacts)
Crea un file tipo:
```bash
utils_nostre/txt_penalty/new_csv_registry_names.txt
```

Con dentro una lista simile a:
```text
$WANDB_ENTITY/wandb-registry-motions/clip_01_t1_23_motion
$WANDB_ENTITY/wandb-registry-motions/clip_01_t1_23_motion_mirror
...
```

Poi fai batch:

```bash
artifacts=(
  "$WANDB_ENTITY/wandb-registry-motions/clip_01_t1_23_motion"
  "$WANDB_ENTITY/wandb-registry-motions/clip_01_t1_23_motion_mirror"
  # ...
)

for a in "${artifacts[@]}"; do
  uv run train Mjlab-Tracking-Flat-Booster-T1_23 \
    --registry-name "$a" \
    --env.scene.num-envs 4096 \
    --agent.num_steps_per_env 25 \
    --agent.max_iterations 15000 \
    --agent.run_name "tracking_${a##*/}"
done
```

> Se per Tracking usate un comando/entrypoint diverso nel repo, cambia solo quello, non la logica.

---

## 4) Collect rollouts (DAL Tracking) per il Motor Controller (container)

### 4.1 Consiglio per 29 clip da ≤5s
- `--num-envs 64`
- `--num-episodes 50` **per run** nel group

```bash
uv run collect-rollouts Mjlab-Tracking-Flat-Booster-T1_23 \
  --wandb-workspace "$WANDB_ENTITY/mjlab" \
  --wandb-group <GROUP_NAME_TRACKING_PENALTY> \
  --num-episodes 50 \
  --num-envs 64 \
  --output-dir ./data/motor_controller_rollouts/penalty_dataset1
```

> Nota: se `<GROUP_NAME>` contiene ~29 run, allora il totale episodi ≈ 50×29 = 1450.

---

## 5) Train Stage‑1 Motor Controller (container)

```bash
uv run train-motor-stage1 \
  --data-root ./data/motor_controller_rollouts/penalty_dataset1 \
  --latent-type npmp \
  --sample-mode chunk \
  --chunk-len 32 \
  --k-future 10 \
  --max-iters 15000 \
  --val-frac 0.1 \
  --seed 0 \
  --run-name PenaltyStage1_v2_kl002 \
  --beta-kl-end 0.02 \
  --beta-kl-warmup-iters 6000 \
  --log-every 50
```

Quando finisce, prendi il run path su W&B:
```text
$WANDB_ENTITY/motor_controller_stage1/<RUN_ID_STAGE1>
```

---

## 6) Punta l’Expert Penalty al nuovo Stage‑1 (container)

### 6.1 Export (solo per la sessione corrente)
```bash
export MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY="$WANDB_ENTITY/motor_controller_stage1/<RUN_ID_STAGE1>"
```

### 6.2 (Consigliato) Scrivi anche nel file env (host)
Nel file:
```text
utils_nostre/stage1_expert_paths.env
```
metti:
```text
MJLAB_STAGE1_WANDB_RUN_PATH_PENALTY=$WANDB_ENTITY/motor_controller_stage1/<RUN_ID_STAGE1>
```
Poi riavvia il container se vuoi essere sicuro che venga caricato sempre.

---

## 7) Train Expert Penalty (container)

Esempio:
```bash
uv run train Mjlab-Penalty-Booster-T1_23 \
  --run-name P1_penalty_expert_v0
```

Risultato: su W&B avrai una run tipo:
```text
$WANDB_ENTITY/penalty_experts/<RUN_ID_EXPERT>
```

---

## 8) Play (vedere il risultato) (container)

### 8.1 Sanity check: agent random (deve terminare su fall/out/6s)
```bash
uv run play Mjlab-Penalty-Booster-T1_23 \
  --agent random \
  --num-envs 1 \
  --viewer native
```

### 8.2 Play della policy allenata (W&B)
```bash
uv run play Mjlab-Penalty-Booster-T1_23 \
  --wandb-run-path "$WANDB_ENTITY/penalty_experts/<RUN_ID_EXPERT>" \
  --num-envs 1 \
  --viewer native
```

**IMPORTANTE**
- NON usare `--no-fall-termination True` (altrimenti non termina quando cade).
- Assicurati che nel tuo `env_cfgs.py` in `if play:` **non** metta `episode_length_s = 1e9`, ma lasci `EPISODE_LENGTH_S = 6.0`.

---

## 9) (Opzionale) Eval quantitativo (container)

Esempio:
```bash
uv run eval Mjlab-Penalty-Booster-T1_23 \
  --wandb-run-path "$WANDB_ENTITY/penalty_experts/<RUN_ID_EXPERT>" \
  --num-episodes 200 \
  --env.scene.num-envs 64
```

Metriche utili:
- `goal_event` rate
- `goal_high_corner` rate
- `ball_out` rate
- `fallen` rate
- `second_touch` rate

---

## 10) (Opzionale) Rollouts dell’Expert (per skill priors / final policy)

Se la pipeline lo supporta direttamente:
```bash
uv run collect-rollouts Mjlab-Penalty-Booster-T1_23 \
  --wandb-run-path "$WANDB_ENTITY/penalty_experts/<RUN_ID_EXPERT>" \
  --num-episodes 400 \
  --num-envs 64 \
  --output-dir ./data/expert_rollouts/penalty_p1
```

Se `collect-rollouts` nel repo è solo per Tracking, allora serve lo script “dump expert trajectories” (dimmi l’errore e lo puntiamo al file giusto).

---

## Parametri consigliati rapidi

### Rollouts tracking → Stage‑1
- `num_envs`: **64** (se OOM → 32)
- `num_episodes`: **50 per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert training
- Episode length: **6s**
- Terminations: `fallen`, `ball_out`, `second_touch`, `timeout`
- Goal: **non termina** (solo reward event-based)

---

## Troubleshooting ultra rapido

- **Episodi infiniti in play**: nel `env_cfgs.py` hai `if play: cfg.episode_length_s = 1e9` → rimettilo a 6.0.
- **Reward esplode dopo goal**: `goal_*` deve essere **event-based** (solo 1 step).
- **Second touch termina subito**: soglie troppo strette o “distanza” noisy → passare a ContactSensor.
- **Ball_out non termina mai**: controlla `field_half_length_x/width_y` e verso `goal_line_x`.

