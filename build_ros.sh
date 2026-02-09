#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [ -z "${JOBS:-}" ]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
  else
    JOBS=4
  fi
fi

echo "Building ROS nodes"
ROS_DIR="Examples/ROS/ORB_SLAM3"
if [ ! -d "$ROS_DIR" ]; then
  echo "Error: $ROS_DIR is missing in this checkout." >&2
  echo "Hint: use a repository version that includes ROS examples." >&2
  exit 1
fi

cmake -S "$ROS_DIR" -B "$ROS_DIR/build" -DROS_BUILD_TYPE=Release
cmake --build "$ROS_DIR/build" -j"$JOBS"
