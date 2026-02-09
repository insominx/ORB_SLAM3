# ORB_SLAM3 Windows/WSL Build Postmortem and Rebuild Playbook

## Document purpose
This report captures every build blocker encountered during a full rebuild on Windows and provides a deterministic rebuild procedure for future agents.

- Repository: `ORB_SLAM3`
- Host OS: Windows
- Build environment used: WSL2 Ubuntu 24.04.3 LTS
- Date of successful rebuild: 2026-02-09

Related docs:
- `docs/setup/windows-wsl-python-bindings-postmortem-and-playbook.md` for Python bindings install workflow and triage.

## Outcome summary
A full build completed successfully with these generated artifacts:

- `lib/libORB_SLAM3.so`
- `Thirdparty/DBoW2/lib/libDBoW2.so`
- `Thirdparty/g2o/lib/libg2o.so`
- `Vocabulary/ORBvoc.txt`
- Example binaries under `Examples/*` and `Examples_old/*` (69 executables detected)

## Problems encountered and resolutions

### 1) Native Windows toolchain path is not supported by current repo
Symptom:
- Configure with Visual Studio generator failed early with: compiler has no C++11 support.

Root cause:
- `CMakeLists.txt` checks `-std=c++11` / `-std=c++0x` flags only, which are GCC/Clang style checks, not MSVC-style.

Resolution used:
- Switched to WSL2 Linux build path (recommended for this repo as-is).

---

### 2) `build.sh` failed in WSL with `$'\r'` errors
Symptom:
- Errors like:
  - `./build.sh: line X: $'\r': command not found`
  - paths such as `Thirdparty/DBoW2\r` not found
  - malformed build directory names containing carriage returns.

Root cause:
- CRLF line endings in `build.sh` (Windows checkout behavior).

Resolution used:
- Did not rely on `build.sh`.
- Ran the equivalent build steps manually in WSL.
- Cleaned malformed build directories before retry.

Prevention:
- Prefer cloning/building inside WSL filesystem (`~/...`) with Linux git.
- If repo is on `/mnt/<drive>`, normalize scripts first (`sed -i 's/\r$//' build.sh build_ros.sh`).

---

### 3) Pangolin package not available via apt on Ubuntu 24.04
Symptom:
- `apt-get install libpangolin-dev` failed (`Unable to locate package`).

Root cause:
- No `libpangolin-dev` package in the default Ubuntu 24.04 repos.

Resolution used:
- Built Pangolin from source.

---

### 4) Latest Pangolin (master) required newer C++ than ORB_SLAM3 build flags
Symptom:
- Compile errors in `sigslot` headers such as `std::decay_t`, `std::enable_if_t` not found (C++14 features), while ORB_SLAM3 compiles with C++11.

Root cause:
- Pangolin `master` currently expects newer C++ standard than this ORB_SLAM3 config.

Resolution used:
- Pinned Pangolin to tag `v0.6` (compatible target for this codebase).

---

### 5) Pangolin `v0.6` failed on Ubuntu 24.04 / GCC 13 due missing fixed-width integer includes
Symptom:
- Errors around `uint8_t` / `uint32_t` not found in Pangolin files.

Root cause:
- Older Pangolin sources rely on transitive includes that are stricter with newer compilers.

Resolution used:
- Built Pangolin `v0.6` with:
- `-DCMAKE_CXX_FLAGS='-include cstdint'`

This injects `<cstdint>` globally during Pangolin compile and avoided patching installed repo files.

---

### 6) Partial failed runs left polluted build state
Symptom:
- Nested or malformed build directories and CMake cache/path mismatch issues.

Root cause:
- Interrupted/failed mixed runs (CRLF script + manual commands).

Resolution used:
- Hard cleanup of generated build folders before final successful rebuild.

## Clean rebuild from scratch (recommended workflow)

This section is the procedure future agents should follow for the smoothest rebuild.

### A) Windows host setup (one-time)
Run in elevated PowerShell:

```powershell
wsl --install -d Ubuntu
```

After install/reboot, confirm:

```powershell
wsl -l -v
```

### B) WSL package bootstrap
Run in WSL as root:

```bash
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential cmake git pkg-config \
  libeigen3-dev libopencv-dev libboost-serialization-dev libssl-dev \
  libglew-dev libgl1-mesa-dev libegl1-mesa-dev \
  libwayland-dev libxkbcommon-dev wayland-protocols \
  libepoxy-dev libpython3-dev libjpeg-dev libpng-dev libtiff-dev libdc1394-dev
```

### C) Use a clean LF checkout (highly recommended)
Recommended:
- Clone inside WSL filesystem (example: `~/src/ORB_SLAM3`) with Linux git.

If using a Windows-mounted repo (`/mnt/d/...`), normalize shell scripts:

```bash
sed -i 's/\r$//' build.sh build_ros.sh || true
```

### D) Install Pangolin (pinned)
Run in WSL:

```bash
set -euo pipefail
rm -rf /tmp/Pangolin
git clone --depth 1 --branch v0.6 https://github.com/stevenlovegrove/Pangolin.git /tmp/Pangolin
cd /tmp/Pangolin
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS='-include cstdint' \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TOOLS=OFF
cmake --build build -j4
sudo cmake --install build
```

### E) Build ORB_SLAM3 (manual deterministic sequence)
From repo root:

```bash
set -euo pipefail

# Optional: clean previous generated outputs
rm -rf build lib \
  Thirdparty/DBoW2/build Thirdparty/DBoW2/lib \
  Thirdparty/g2o/build Thirdparty/g2o/lib Thirdparty/g2o/bin \
  Thirdparty/Sophus/build

# Third-party
cd Thirdparty/DBoW2
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

cd ../../g2o
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4

cd ../../Sophus
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF
make -j4

# Vocabulary
cd ../../../Vocabulary
tar -xf ORBvoc.txt.tar.gz

# Root
cd ..
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
```

## Verification checklist
Run from repo root:

```bash
test -f lib/libORB_SLAM3.so && echo ORB_LIB_OK
test -f Thirdparty/DBoW2/lib/libDBoW2.so && echo DBOW2_OK
test -f Thirdparty/g2o/lib/libg2o.so && echo G2O_OK
test -f Vocabulary/ORBvoc.txt && echo VOCAB_OK
find Examples -maxdepth 2 -type f -executable | wc -l
```

Expected:
- All `*_OK` lines printed.
- Non-zero executable count in `Examples` (during successful run, count was `69`).

## Known warnings that did not block successful build

- CMake deprecation warnings due old `cmake_minimum_required` in upstream files.
- Missing `realsense2` package warning (only affects RealSense optional examples).
- Various Eigen/OpenSSL deprecation and signedness warnings.

These are non-fatal for the baseline build.

## Fast triage map for future agents

- If you see `$'\r'` in bash errors:
- Normalize line endings or avoid shell scripts and run manual sequence.

- If Pangolin compile errors mention `decay_t`/`enable_if_t`:
- You installed too-new Pangolin. Reinstall pinned `v0.6`.

- If Pangolin `v0.6` errors mention `uint32_t`/`uint8_t`:
- Rebuild Pangolin with `-DCMAKE_CXX_FLAGS='-include cstdint'`.

- If CMake says `realsense2` not found:
- Ignore unless RealSense example binaries are required.

- If build folders look corrupted after a failed run:
- Remove all generated build/output directories and rebuild from zero.

## Optional maintainability improvements (not required for rebuild)

- Convert repository shell scripts to LF and make them idempotent.
- Add a WSL-oriented bootstrap script in repo.
- Pin Pangolin version in project docs.
- Consider modernizing CMake standard handling (`CMAKE_CXX_STANDARD`) and minimum CMake version.

## Instruction block for future agents

When asked to rebuild this repo on Windows with minimal risk, use this exact strategy:

1. Build in WSL2, not native Windows toolchains.
2. Pin Pangolin to `v0.6` and compile with `-include cstdint` on Ubuntu 24.04+.
3. Do manual build steps (third-party then root) unless `build.sh` is confirmed LF.
4. Always run post-build artifact checks before declaring success.
5. If prior attempts failed, clean generated outputs before retrying.
