

#!/usr/bin/env bash

set -e  # Stop on error

IMAGE_NAME="mjlab_v2"
CONTAINER_NAME="majin_bu_v2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Path to source folder + Dockerfile
WANDB_ENV_FILE="$SOURCE_DIR/wandb_credentials.env"
SOURCE_DIR="$PARENT_DIR/mjlab"
DOCKERFILE_PATH="$SOURCE_DIR/Dockerfile"
H2R_OUTPUT_DIR="$PARENT_DIR/human_to_robot/output"


# Detect interactive terminal
if [ -t 1 ]; then
    INTERACTIVE="-it"
else
    INTERACTIVE=""
fi

echo "=== Using SOURCE_DIR: $SOURCE_DIR"
echo "=== Using DOCKERFILE: $DOCKERFILE_PATH"

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

if [ ! -d "$H2R_OUTPUT_DIR" ]; then
    echo "❌ ERROR: human_to_robot output dir not found:"
    echo "   $H2R_OUTPUT_DIR"
    exit 1
fi

if [ ! -f "$WANDB_ENV_FILE" ]; then
    echo "⚠ WARNING: W&B env file not found: $WANDB_ENV_FILE"
    echo "   W&B will run without WANDB_API_KEY unless you set it another way."
    WANDB_ENV_ARGS=()
else
    WANDB_ENV_ARGS=(--env-file "$WANDB_ENV_FILE")
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
        "${WANDB_ENV_ARGS[@]}" \
        --runtime nvidia \
        --volume "$SOURCE_DIR:/app" \
        --volume "$H2R_OUTPUT_DIR:/app/human_to_robot_output:ro" \
        --publish 8080:8080 \
        $INTERACTIVE \
        "$IMAGE_NAME" \
        "$@"
fi
