#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ ERROR at line $LINENO: $BASH_COMMAND" >&2' ERR

# -------------------- Parse custom flags --------------------
NO_GPU=0
PASSTHRU_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-gpu)
      NO_GPU=1
      ;;
    *)
      PASSTHRU_ARGS+=("$arg")
      ;;
  esac
done

# Variables required for logging as a user with the same id as the user running this script
export LOCAL_USER_ID=$(id -u "$USER")
export LOCAL_GROUP_ID=$(id -g "$USER")
export LOCAL_GROUP_NAME=$(id -gn "$USER")
DOCKER_USER_ARGS="--env LOCAL_USER_ID --env LOCAL_GROUP_ID --env LOCAL_GROUP_NAME"

# Variables for forwarding ssh agent into docker container
DOCKER_SSH_AUTH_ARGS=""
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
  DOCKER_SSH_AUTH_ARGS="-v $(dirname "$SSH_AUTH_SOCK"):$(dirname "$SSH_AUTH_SOCK") -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
fi

# X11 forwarding (independent from GPU)
DOCKER_X11_ARGS=""
if [ -n "${DISPLAY:-}" ]; then
  XAUTHORITY_PATH="${XAUTHORITY:-$HOME/.Xauthority}"
  XAUTH_FILE="/tmp/.docker.xauth"
  XAUTH_FALLBACK_TMP="/tmp/.docker.xauth.$USER"
  XAUTH_FALLBACK_HOME="$HOME/.docker.xauth"
  DOCKER_X11_ARGS="--env DISPLAY --env QT_X11_NO_MITSHM=1 --volume=/tmp/.X11-unix:/tmp/.X11-unix:rw"
  if command -v xauth >/dev/null 2>&1; then
    # Ensure the path is a writable file so Docker can bind-mount it.
    if [ -d "$XAUTH_FILE" ] || { [ -e "$XAUTH_FILE" ] && [ ! -w "$XAUTH_FILE" ]; }; then
      XAUTH_FILE="$XAUTH_FALLBACK_TMP"
    fi
    if [ -d "$XAUTH_FILE" ] || { [ -e "$XAUTH_FILE" ] && [ ! -w "$XAUTH_FILE" ]; }; then
      XAUTH_FILE="$XAUTH_FALLBACK_HOME"
    fi
    if ! : > "$XAUTH_FILE" 2>/dev/null; then
      echo "WARNING: Could not create Xauthority file at $XAUTH_FILE; X11 auth may fail." >&2
      XAUTH_FILE=""
    fi
    if [ -n "$XAUTH_FILE" ]; then
      if [ -f "$XAUTHORITY_PATH" ]; then
        xauth -f "$XAUTHORITY_PATH" nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "$XAUTH_FILE" nmerge - 2>/dev/null
      else
        xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "$XAUTH_FILE" nmerge - 2>/dev/null
      fi
      DOCKER_X11_ARGS="$DOCKER_X11_ARGS --env XAUTHORITY=$XAUTH_FILE --volume=$XAUTH_FILE:$XAUTH_FILE:ro"
    fi
  elif [ -f "$XAUTHORITY_PATH" ]; then
    DOCKER_X11_ARGS="$DOCKER_X11_ARGS --env XAUTHORITY=$XAUTHORITY_PATH --volume=$XAUTHORITY_PATH:$XAUTHORITY_PATH:ro"
  fi
  if command -v xhost >/dev/null 2>&1; then
    xhost +SI:localuser:root >/dev/null 2>&1 || xhost + >/dev/null 2>&1
  fi
fi

# Settings required for having nvidia GPU acceleration inside the docker
DOCKER_GPU_ARGS=""

# If user requested NO GPU, disable GPU args and force plain docker run
if [ "$NO_GPU" -eq 1 ]; then
  DOCKER_COMMAND="docker run"
else
  dpkg -l | grep nvidia-container-toolkit &> /dev/null
  HAS_NVIDIA_TOOLKIT=$?
  if command -v nvidia-docker >/dev/null 2>&1; then
    HAS_NVIDIA_DOCKER=0
  else
    HAS_NVIDIA_DOCKER=1
  fi

  if [ $HAS_NVIDIA_TOOLKIT -eq 0 ]; then
    docker_version=$(docker version --format '{{.Client.Version}}' | cut -d. -f1)
    if [ "$docker_version" -ge 19 ]; then
      DOCKER_COMMAND="docker run --gpus all"
    else
      DOCKER_COMMAND="docker run --runtime=nvidia"
    fi
  elif [ $HAS_NVIDIA_DOCKER -eq 0 ]; then
    DOCKER_COMMAND="nvidia-docker run"
  else
    echo "Running without nvidia-docker, if you have an NVidia card you may need it to have GPU acceleration"
    DOCKER_COMMAND="docker run"
  fi

fi

DOCKER_NETWORK_ARGS="" # --net host
if [[ " ${PASSTHRU_ARGS[*]} " == *" --net "* ]]; then
  DOCKER_NETWORK_ARGS=""
else
  if [ -n "${DISPLAY:-}" ]; then
    DOCKER_ROOT_DIR="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
    if echo "$DOCKER_ROOT_DIR" | grep -q "/var/snap/docker"; then
      # Snap Docker uses a private /tmp, so rely on host network + XAUTHORITY.
      DOCKER_NETWORK_ARGS="--net host"
    fi
  fi
fi

$DOCKER_COMMAND \
  $DOCKER_USER_ARGS \
  $DOCKER_GPU_ARGS \
  $DOCKER_X11_ARGS \
  $DOCKER_SSH_AUTH_ARGS \
  $DOCKER_NETWORK_ARGS \
  --privileged \
  -v "$HOME/exchange:/home/user/exchange" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${PASSTHRU_ARGS[@]}"
