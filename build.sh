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

echo "Configuring and building Thirdparty/DBoW2 ..."
cmake -S Thirdparty/DBoW2 -B Thirdparty/DBoW2/build -DCMAKE_BUILD_TYPE=Release
cmake --build Thirdparty/DBoW2/build -j"$JOBS"

echo "Configuring and building Thirdparty/g2o ..."
cmake -S Thirdparty/g2o -B Thirdparty/g2o/build -DCMAKE_BUILD_TYPE=Release
cmake --build Thirdparty/g2o/build -j"$JOBS"

echo "Configuring and building Thirdparty/Sophus ..."
cmake -S Thirdparty/Sophus -B Thirdparty/Sophus/build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF
cmake --build Thirdparty/Sophus/build -j"$JOBS"

echo "Uncompress vocabulary ..."
if [ ! -f Vocabulary/ORBvoc.txt ]; then
  tar -xf Vocabulary/ORBvoc.txt.tar.gz -C Vocabulary
fi

echo "Configuring and building ORB_SLAM3 ..."
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$JOBS"
