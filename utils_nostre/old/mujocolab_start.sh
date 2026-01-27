#!/usr/bin/env bash

set -e  # Stop on error

IMAGE_NAME="mjlab"
CONTAINER_NAME="majin_bu_prova"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(cd "$PARENT_DIR/.." && pwd)"

# Path to source folder + Dockerfile
SOURCE_DIR="$PARENT_DIR/mjlab"
DOCKERFILE_PATH="$SOURCE_DIR/Dockerfile"

# ---- Weights & Biases credentials (.env) -------------------------------------
# Put your W&B creds in this file (gitignored), e.g.:
# WANDB_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# WANDB_ENTITY=your_entity
# WANDB_PROJECT=your_project
WANDB_ENV_FILE="$SCRIPT_DIR/wandb_credentials.env"

# Detect interactive terminal
if [ -t 1 ]; then
    INTERACTIVE="-it"
else
    INTERACTIVE=""
fi

echo "=== Using SOURCE_DIR: $SOURCE_DIR"
echo "=== Using DOCKERFILE: $DOCKERFILE_PATH"
echo "=== WANDB_ENV_FILE:  $WANDB_ENV_FILE"

# --- Safety checks ------------------------------------------------------------

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

# W&B env file is optional; if present we pass it to docker
WANDB_ENV_ARGS=()
if [ -f "$WANDB_ENV_FILE" ]; then
    echo "✅ Found W&B credentials file."
    WANDB_ENV_ARGS+=(--env-file "$WANDB_ENV_FILE")
else
    echo "⚠ W&B credentials file not found (ok if you don't use W&B):"
    echo "   $WANDB_ENV_FILE"
fi

# --- Build image if needed ----------------------------------------------------

echo "=== Checking for Docker image '$IMAGE_NAME' ==="

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "⚠ Image not found. Building..."

    docker build \
        -t "$IMAGE_NAME" \
        -f "$DOCKERFILE_PATH" \
        "$SOURCE_DIR"

    echo "✅ Build completed."
else
    echo "✅ Image already exists."
fi

# --- Run or start container ---------------------------------------------------

echo "=== Checking for container '$CONTAINER_NAME' ==="

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "Container exists. Starting..."

    docker start "$CONTAINER_NAME"

    if [ -t 1 ]; then
        docker attach "$CONTAINER_NAME"
    fi
else
    echo "Container not found — creating new one."

    "$SCRIPT_DIR"/start_docker.sh \
        --name "$CONTAINER_NAME" \
        --runtime nvidia \
        "${WANDB_ENV_ARGS[@]}" \
        --volume "$SOURCE_DIR:/app" \
        --publish 8080:8080 \
        $INTERACTIVE \
        "$IMAGE_NAME" \
        "$@"
fi
