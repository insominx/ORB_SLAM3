# ORB_SLAM3 Windows/WSL Local-Source Python Bindings Rebuild Playbook

## Document purpose
Deterministic rebuild instructions for future agents to run ORB-SLAM3 Python bindings from **local source** (not a bundled wheel), in WSL2 on Windows.

- Repository root: `slam-stream/`
- Host OS: Windows
- Runtime/build OS: WSL2 Ubuntu 24.04
- Python: `3.12`
- Date validated: `2026-02-09`

Related docs:
- `windows-wsl-build-postmortem-and-playbook.md` (ORB core build background)
- `windows-wsl-python-bindings-postmortem-and-playbook.md` (older wheel-based path)
- `../../../docs/scratch/build-log-python-bindings.md` (full issue log from this run)

---

## Target outcome (what "done" looks like)

1. `import orbslam3` works in a repo-local WSL venv.
2. Extension is local editable build: `bindings/src/orbslam3/_core.cpython-312-...so`.
3. `ldd` of that extension points to local source-built libs:
   - `ORB_SLAM3/lib/libORB_SLAM3.so`
   - `ORB_SLAM3/Thirdparty/DBoW2/lib/libDBoW2.so`
   - `ORB_SLAM3/Thirdparty/g2o/lib/libg2o.so`
4. Source changes in `ORB_SLAM3/src/System.cc` propagate after `pip install -e bindings/`.

---

## Required repository state

### 1) ORB API patch must exist in your ORB fork
These methods are required by the local binding wrapper:

- `ORB_SLAM3/include/System.h`
  - `std::vector<KeyFrame*> GetKeyFrames() const;`
  - `Tracking* GetTracker() const;`
- `ORB_SLAM3/src/System.cc`
  - `GetKeyFrames()` returns `mpAtlas->GetAllKeyFrames()`
  - `GetTracker()` returns `mpTracker`

Reference locations:
- `ORB_SLAM3/include/System.h` (public section near `GetTrackedMapPoints`)
- `ORB_SLAM3/src/System.cc` (end of file)

If missing, add + commit in your ORB fork first, then update submodule pointer in superproject.

### 2) Bindings folder must exist
This playbook assumes `bindings/` is present in the superproject with:
- `bindings/CMakeLists.txt`
- `bindings/setup.py`
- `bindings/pyproject.toml`
- `bindings/src/ORBSlamPython.cpp`, `ORBSlamPython.h`
- `bindings/src/pyboostcvconverter/*`
- `bindings/src/orbslam3/__init__.py`
- `bindings/cmake_modules/FindNumPy.cmake`

---

## One-time WSL prerequisites

Run in an interactive WSL shell (sudo password required):

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake git pkg-config \
  libeigen3-dev libopencv-dev libboost-serialization-dev libboost-python-dev \
  python3.12-dev libssl-dev \
  libglew-dev libgl1-mesa-dev libegl1-mesa-dev \
  libwayland-dev libxkbcommon-dev wayland-protocols \
  libepoxy-dev libpython3-dev libjpeg-dev libpng-dev libtiff-dev libdc1394-dev
```

Notes:
- `libboost-python-dev` is required for Boost.Python discovery.
- Pangolin v0.6 is required by ORB (install from source if missing).

---

## Deterministic rebuild procedure (from repo root)

> All commands below run in WSL.

### Step 1: Verify Pangolin

```bash
ls /usr/local/lib/libpangolin.so
```

If missing, install Pangolin v0.6 using the existing playbook:
- `ORB_SLAM3/docs/setup/windows-wsl-build-postmortem-and-playbook.md`

### Step 2: Create/refresh Python venv

```bash
cd /mnt/d/Projects/humana-machina/slam-stream
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install -U pip
python -m pip install "numpy>=1.24,<2" "opencv-python>=4.8"
```

Why numpy `<2`:
- Avoid ABI break (`_ARRAY_API`) with pyboostcvconverter/Boost.Python stack.

### Step 3: Build DBoW2 (required pre-step)

```bash
cd /mnt/d/Projects/humana-machina/slam-stream/ORB_SLAM3/Thirdparty/DBoW2
rm -rf build
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
```

Expected artifact:
- `ORB_SLAM3/Thirdparty/DBoW2/lib/libDBoW2.so`

### Step 4: Build/install local bindings (editable)

```bash
cd /mnt/d/Projects/humana-machina/slam-stream
. .venv/bin/activate
pip install -e bindings/
```

This compiles:
- ORB core (`add_subdirectory(../ORB_SLAM3)` from `bindings/CMakeLists.txt`)
- Python extension (`_core.cpython-312-...so`)

---

## Validation checklist

### A) Import works

```bash
cd /mnt/d/Projects/humana-machina/slam-stream
. .venv/bin/activate
python - <<'PY'
import orbslam3
import orbslam3._core as core
print("IMPORT_OK", orbslam3.Sensor.MONOCULAR)
print("PACKAGE", orbslam3.__file__)
print("CORE", core.__file__)
PY
```

### B) Linkage points to local libs

```bash
ldd /mnt/d/Projects/humana-machina/slam-stream/bindings/src/orbslam3/_core.cpython-312-x86_64-linux-gnu.so
```

Must include:
- `.../ORB_SLAM3/lib/libORB_SLAM3.so`
- `.../ORB_SLAM3/Thirdparty/DBoW2/lib/libDBoW2.so`
- `.../ORB_SLAM3/Thirdparty/g2o/lib/libg2o.so`

### C) Runtime smoke test (video)

Use:
- video: `stream_harness/test_data/shipwreck.mp4`
- settings: `ORB_SLAM3/Examples/Monocular/TUM3.yaml`
- vocab: `ORB_SLAM3/Vocabulary/ORBvoc.txt`

Expected shape:
- nonzero `TrackingState.OK` frames
- non-`None` pose during OK frames
- non-empty map points during OK frames

### D) Provenance check (local source propagation)

1. Add temporary marker print in `ORB_SLAM3/src/System.cc`.
2. Re-run `pip install -e bindings/`.
3. Instantiate `orbslam3.System(...)`.
4. Marker appears in stdout.
5. Remove marker + rebuild; marker disappears.

If this passes, Python is using local source build (not a wheel bundle).

---

## Common failures and fixes

### 1) `boost_thread` / extra Boost component not found
Symptom:
- CMake asks for `boost_thread`/`boost_system` etc.

Fix:
- Wrapper should require only Boost.Python.
- Keep component fallback in `bindings/CMakeLists.txt`:
  - `python312`, `python3`, `python`

### 2) CMake 4.x policy error with ORB
Symptom:
- `Compatibility with CMake < 3.5 has been removed`

Fix:
- `bindings/pyproject.toml`: `cmake>=3.14,<4`
- `bindings/setup.py`: pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`

### 3) `Thirdparty/.../BowVector.h` not found
Symptom:
- compile error in `KeyFrame.h` include chain.

Fix:
- Add ORB root include dir in wrapper target:
  - `${ORB_SLAM3_DIR}`

### 4) Editable install expects `_core...so` but file missing
Symptom:
- `can't copy ... _core.cpython-312-...so`

Fix:
- Keep naming aligned:
  - C++ module macro: `BOOST_PYTHON_MODULE(_core)`
  - CMake output: `OUTPUT_NAME "_core"` with SOABI suffix
  - Python package import: `from ._core import ...`
  - setup.py extension name: `orbslam3._core`

### 5) DBoW2 build fails with wrong source path
Symptom:
- CMake cache points to old path (`/mnt/d/Projects/tools/...`).

Fix:
- Delete stale build dir and reconfigure:
  - `rm -rf ORB_SLAM3/Thirdparty/DBoW2/build`

---

## Fast rerun commands (already-provisioned machine)

```bash
cd /mnt/d/Projects/humana-machina/slam-stream
. .venv/bin/activate

# Rebuild DBoW2 quickly if needed
cd ORB_SLAM3/Thirdparty/DBoW2/build && make -j4

# Rebuild and reinstall bindings
cd /mnt/d/Projects/humana-machina/slam-stream
pip install -e bindings/
```

---

## Source-of-truth notes for future agents

- Use this playbook for local-source Python bindings.
- Keep ORB changes committed in your fork; do not rely on ad-hoc local edits.
- If build behavior diverges, append details to:
  - `../../../docs/scratch/build-log-python-bindings.md`
