#!/usr/bin/env bash
echo "START_DOCKER ARGS: $*"

set -e  # Stop on error

IMAGE_NAME="mjlab"
CONTAINER_NAME="majin_bu"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Paths (same style/behavior as your mjlab_v2 script)
WANDB_ENV_FILE="$SCRIPT_DIR/wandb_credentials.env"
SOURCE_DIR="$PARENT_DIR/mjlab"
DOCKERFILE_PATH="$SOURCE_DIR/Dockerfile"
OUTPUTVIDEO_DIR="$PARENT_DIR/human_to_robot/output/mujoco_csv"
WANDB_CACHE_HOST_DIR="$SOURCE_DIR/logs/wandb_cache"
WANDB_CACHE_CONTAINER_DIR="/app/logs/wandb_cache"

# ---------------- Parse custom flags (same as v2) ----------------
REBUILD=0
NO_CACHE=0
PASSTHRU_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --rebuild)  REBUILD=1 ;;
    --no-cache) NO_CACHE=1 ;;
    *)          PASSTHRU_ARGS+=("$arg") ;;
  esac
done

# Detect interactive terminal
if [ -t 1 ]; then
  INTERACTIVE="-it"
else
  INTERACTIVE=""
fi

echo "=== Using SOURCE_DIR:      $SOURCE_DIR"
echo "=== Using DOCKERFILE:      $DOCKERFILE_PATH"
echo "=== WANDB_ENV_FILE:        $WANDB_ENV_FILE"
echo "=== OUTPUTVIDEO_DIR(host): $OUTPUTVIDEO_DIR"
echo "=== WANDB_CACHE_DIR(host): $WANDB_CACHE_HOST_DIR"

# ---------------- Safety checks ----------------
if [ ! -d "$SOURCE_DIR" ]; then
  echo "❌ ERROR: Source directory does not exist:"
  echo "   $SOURCE_DIR"
  exit 1
fi

if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ ERROR: Dockerfile not found:"
  echo "   $DOCKERFILE_PATH"
  exit 1
fi

# Ensure outputvideo dir exists (create if missing) — same “create if missing” behavior
if [ ! -d "$OUTPUTVIDEO_DIR" ]; then
  echo "⚠ outputvideo dir not found, creating it:"
  echo "   $OUTPUTVIDEO_DIR"
  mkdir -p "$OUTPUTVIDEO_DIR"
fi

if [ ! -d "$OUTPUTVIDEO_DIR" ]; then
  echo "❌ ERROR: could not create outputvideo dir:"
  echo "   $OUTPUTVIDEO_DIR"
  exit 1
fi

# W&B env file handling (same behavior as v2)
if [ ! -f "$WANDB_ENV_FILE" ]; then
  echo "⚠ WARNING: W&B env file not found: $WANDB_ENV_FILE"
  echo "   W&B will run without WANDB_API_KEY unless you set it another way."
  WANDB_ENV_ARGS=()
else
  WANDB_ENV_ARGS=(--env-file "$WANDB_ENV_FILE")
fi

# ---------------- Build image if needed ----------------
echo "=== Checking for Docker image '$IMAGE_NAME' ==="

BUILD_ARGS=()
if [ "$NO_CACHE" -eq 1 ]; then
  BUILD_ARGS+=(--no-cache)
fi

if [ "$REBUILD" -eq 1 ]; then
  echo "⚠ Rebuild requested. Building..."
  docker build \
    "${BUILD_ARGS[@]}" \
    -t "$IMAGE_NAME" \
    -f "$DOCKERFILE_PATH" \
    "$SOURCE_DIR"
  echo "✅ Build completed."
elif ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "⚠ Image not found. Building..."
  docker build \
    -t "$IMAGE_NAME" \
    -f "$DOCKERFILE_PATH" \
    "$SOURCE_DIR"
  echo "✅ Build completed."
else
  echo "✅ Image already exists."
fi

# ---------------- Run or start container ----------------
echo "=== Checking for container '$CONTAINER_NAME' ==="

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  if [ "$REBUILD" -eq 1 ]; then
    echo "Rebuild requested — recreating container."
    docker rm -f "$CONTAINER_NAME"
  else
    echo "Container exists. Starting..."
    docker start "$CONTAINER_NAME"
    if [ -t 1 ]; then
      docker attach "$CONTAINER_NAME"
    fi
    exit 0
  fi
fi

echo "Container not found — creating new one."

"$SCRIPT_DIR"/start_docker.sh \
  --name "$CONTAINER_NAME" \
  "${WANDB_ENV_ARGS[@]}" \
  --env "WANDB_CACHE_DIR=$WANDB_CACHE_CONTAINER_DIR" \
  --volume "$SOURCE_DIR:/app" \
  --volume "$OUTPUTVIDEO_DIR:/app/human_to_robot_output" \
  --publish 8080:8080 \
  $INTERACTIVE \
  -- \
  "$IMAGE_NAME" \
  "${PASSTHRU_ARGS[@]}"
