#!/bin/bash
# Build and run the Fusion test SSH container.
# Usage: ./run.sh [start|stop|status|key]

set -e

CONTAINER_NAME="fusion_test_ssh"
IMAGE_NAME="fusion_test_ssh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY_DIR="$SCRIPT_DIR/.keys"

build() {
  echo "Building Docker image..."
  docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
}

start() {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container already running"
    return 0
  fi

  # Remove stopped container if exists
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

  build

  echo "Starting container..."
  docker run -d --name "$CONTAINER_NAME" -p 2222:22 "$IMAGE_NAME"

  # Wait for SSH to be ready
  echo -n "Waiting for SSH..."
  for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" sh -c "ss -tlnp | grep -q ':22'" 2>/dev/null; then
      echo " ready!"
      break
    fi
    echo -n "."
    sleep 0.5
  done

  # Extract the test private key
  mkdir -p "$KEY_DIR"
  docker cp "$CONTAINER_NAME:/home/fusion_test/.ssh/id_ed25519" "$KEY_DIR/test_key"
  chmod 600 "$KEY_DIR/test_key"

  echo "Container running on port 2222"
  echo "SSH key at: $KEY_DIR/test_key"
  echo ""
  echo "Test connection:"
  echo "  ssh -i $KEY_DIR/test_key -p 2222 -o StrictHostKeyChecking=no fusion_test@localhost echo ok"
}

stop() {
  echo "Stopping container..."
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  rm -rf "$KEY_DIR"
  echo "Done"
}

status() {
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Running"
    docker port "$CONTAINER_NAME"
  else
    echo "Not running"
    return 1
  fi
}

key() {
  if [ -f "$KEY_DIR/test_key" ]; then
    echo "$KEY_DIR/test_key"
  else
    echo "No key found. Run '$0 start' first." >&2
    return 1
  fi
}

case "${1:-start}" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  key)    key ;;
  build)  build ;;
  *)      echo "Usage: $0 [start|stop|status|key|build]" ;;
esac
