#!/usr/bin/env bash
set -euo pipefail

# ==================== Paths ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_DIR="$PARENT_DIR/human_to_robot"
DOCKERFILE_PATH="$SOURCE_DIR/Dockerfile"
CONFIG_PATH="$SOURCE_DIR/config.yaml"

START_DOCKER_SH="$SCRIPT_DIR/start_docker.sh"

# ==================== Interactive ====================
if [ -t 1 ]; then
  INTERACTIVE="-it"
else
  INTERACTIVE=""
fi

echo "=== Using SOURCE_DIR: $SOURCE_DIR"
echo "=== Using DOCKERFILE: $DOCKERFILE_PATH"
echo "=== Using CONFIG: $CONFIG_PATH"
echo "=== Using START_DOCKER_SH: $START_DOCKER_SH"

# ==================== Safety checks ====================
if [ ! -d "$SOURCE_DIR" ]; then
  echo "❌ ERROR: Source directory does not exist: $SOURCE_DIR"
  exit 1
fi

if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ ERROR: Dockerfile not found: $DOCKERFILE_PATH"
  exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "❌ ERROR: config.yaml not found: $CONFIG_PATH"
  exit 1
fi

if [ ! -f "$START_DOCKER_SH" ]; then
  echo "❌ ERROR: start_docker.sh not found: $START_DOCKER_SH"
  exit 1
fi

# ==================== Read device from YAML ====================
# Accepts lines like:
# device: cpu
# device: cuda
# device: "cuda"
# device: 'cpu'
DEVICE="$(grep -E '^[[:space:]]*device[[:space:]]*:' "$CONFIG_PATH" \
  | head -n1 \
  | sed -E 's/^[[:space:]]*device[[:space:]]*:[[:space:]]*//; s/[[:space:]]*$//' \
  | sed -E 's/^["'\''](.*)["'\'']$/\1/' \
  | tr '[:upper:]' '[:lower:]')"

if [ -z "${DEVICE}" ]; then
  echo "❌ ERROR: 'device:' not found or empty in $CONFIG_PATH"
  exit 1
fi

if [ "$DEVICE" != "cpu" ] && [ "$DEVICE" != "cuda" ]; then
  echo "❌ ERROR: device must be 'cpu' or 'cuda' in $CONFIG_PATH, got: '$DEVICE'"
  exit 1
fi

# ==================== Names & target ====================
IMAGE_NAME="human_to_robot_${DEVICE}_v2_prova"
CONTAINER_NAME="il_prescelto_${DEVICE}_v2_prova"
BUILD_TARGET="$DEVICE"

echo "=== Selected device: $DEVICE"
echo "=== Image: $IMAGE_NAME"
echo "=== Container: $CONTAINER_NAME"
echo "=== Build target: $BUILD_TARGET"

# ==================== Mode selection (interactive) ====================
RUN_MODE="custom"
if [ -t 1 ]; then
  echo "=== Select mode ==="
  echo "1) Open shell"
  echo "2) Run pipeline (video_to_robot.py)"
  read -r -p "Choose [1/2] (default: 1): " RUN_MODE
  case "$RUN_MODE" in
    2|run|pipeline)
      RUN_MODE="run"
      ;;
    *)
      RUN_MODE="shell"
      ;;
  esac
else
  RUN_MODE="custom"
fi

RUN_CMD=()
if [ "$RUN_MODE" = "run" ]; then
  RUN_CMD=(python /workspace/video_to_robot.py /workspace/config.yaml)
fi

DISPLAY_VALUE="${DISPLAY:-}"
X11_ENABLED="off"
if [ -n "$DISPLAY_VALUE" ]; then
  X11_ENABLED="on"
fi
NET_MODE="default"
if [ -n "$DISPLAY_VALUE" ]; then
  DOCKER_ROOT_DIR="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if echo "$DOCKER_ROOT_DIR" | grep -q "/var/snap/docker"; then
    NET_MODE="host"
  fi
fi

# Warn about viewer when DISPLAY is missing
SHOW_VIEWER="$(grep -E '^[[:space:]]*show_viewer[[:space:]]*:' "$CONFIG_PATH" \
  | head -n1 \
  | sed -E 's/^[[:space:]]*show_viewer[[:space:]]*:[[:space:]]*//; s/[[:space:]]*$//' \
  | sed -E 's/^["'\''](.*)["'\'']$/\1/' \
  | tr '[:upper:]' '[:lower:]')"
if [ "${SHOW_VIEWER}" = "true" ] && [ -z "${DISPLAY_VALUE}" ]; then
  echo "⚠ WARNING: show_viewer=true but DISPLAY is not set. Viewer will fail (GLFW)."
fi

# ==================== Build (only if missing) ====================
echo "=== Checking for Docker image '$IMAGE_NAME' ==="

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "⚠ Image not found. Building..."

  docker build \
    --target "$BUILD_TARGET" \
    -t "$IMAGE_NAME" \
    -f "$DOCKERFILE_PATH" \
    "$SOURCE_DIR"

  echo "✅ Build completed."
else
  echo "✅ Image already exists."
fi

# ==================== Run or start ====================
echo "=== Checking for container '$CONTAINER_NAME' ==="

LABEL_KEY_MODE="com.spqr.run_mode"
LABEL_KEY_X11="com.spqr.x11"
LABEL_KEY_DISPLAY="com.spqr.display"
LABEL_KEY_NET="com.spqr.net"
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  CURRENT_MODE="$(docker inspect -f "{{ index .Config.Labels \"${LABEL_KEY_MODE}\" }}" "$CONTAINER_NAME" 2>/dev/null || true)"
  CURRENT_X11="$(docker inspect -f "{{ index .Config.Labels \"${LABEL_KEY_X11}\" }}" "$CONTAINER_NAME" 2>/dev/null || true)"
  CURRENT_DISPLAY="$(docker inspect -f "{{ index .Config.Labels \"${LABEL_KEY_DISPLAY}\" }}" "$CONTAINER_NAME" 2>/dev/null || true)"
  CURRENT_NET="$(docker inspect -f "{{ index .Config.Labels \"${LABEL_KEY_NET}\" }}" "$CONTAINER_NAME" 2>/dev/null || true)"
  NEED_RECREATE="no"
  if [ "$CURRENT_MODE" != "$RUN_MODE" ]; then
    NEED_RECREATE="yes"
  fi
  if [ "$CURRENT_X11" != "$X11_ENABLED" ]; then
    NEED_RECREATE="yes"
  fi
  if [ "$X11_ENABLED" = "on" ] && [ "$CURRENT_DISPLAY" != "$DISPLAY_VALUE" ]; then
    NEED_RECREATE="yes"
  fi
  if [ "$CURRENT_NET" != "$NET_MODE" ]; then
    NEED_RECREATE="yes"
  fi

  if [ "$NEED_RECREATE" = "yes" ]; then
    echo "✅ Container exists. Recreating to apply settings (mode/display)."
    docker rm -f "$CONTAINER_NAME"
  else
    if [ -t 1 ]; then
      echo "✅ Container exists. Starting..."
      docker start "$CONTAINER_NAME"
      docker attach "$CONTAINER_NAME"
      exit 0
    else
      echo "✅ Container exists. Starting..."
      docker start "$CONTAINER_NAME"
      exit 0
    fi
  fi
else
  echo "⚠ Container not found — creating new one."
fi

EXTRA_ARGS=()

#if [ "$DEVICE" = "cpu" ]; then
  # start_docker.sh must support this flag (as we modified earlier)
#  EXTRA_ARGS+=(--no-gpu)
#fi

"$START_DOCKER_SH" \
  "${EXTRA_ARGS[@]}" \
  --label "$LABEL_KEY_MODE=$RUN_MODE" \
  --label "$LABEL_KEY_X11=$X11_ENABLED" \
  --label "$LABEL_KEY_DISPLAY=$DISPLAY_VALUE" \
  --label "$LABEL_KEY_NET=$NET_MODE" \
  --name "$CONTAINER_NAME" \
  --volume "$SOURCE_DIR:/workspace" \
  --publish 8080:8080 \
  $INTERACTIVE \
  "$IMAGE_NAME" \
  "${RUN_CMD[@]}" \
  "$@"
