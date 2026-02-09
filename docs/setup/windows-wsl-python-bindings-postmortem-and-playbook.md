# ORB_SLAM3 Windows/WSL Python Bindings Postmortem and Install Playbook

## Document purpose
This report captures every blocker encountered while installing Python bindings on Windows-hosted WSL and provides a deterministic install procedure for future agents.

- Repository: `ORB_SLAM3`
- Host OS: Windows
- Python environment used: WSL2 Ubuntu 24.04.3 LTS (`python3.12`)
- Date of successful install: 2026-02-09

## Outcome summary
A Python bindings install completed successfully in a repo-local WSL virtual environment with these results:

- Virtual environment: `.venv-wsl`
- Installed package: `orbslam3-python==2.0.0`
- Import check: `import orbslam3` succeeded in WSL venv
- Windows host Python (`C:\Python313\python.exe`) still does not have `orbslam3` installed

## Problems encountered and resolutions

### 1) Python bindings were not preinstalled
Symptom:
- `importlib.util.find_spec('orbslam3')` returned `None` in both Windows Python and WSL Python.

Root cause:
- No prior binding package installation in either active Python environment.

Resolution used:
- Installed bindings into a dedicated WSL virtual environment.

---

### 2) Repo does not include in-tree Python binding build/install scripts
Symptom:
- No `setup.py`, `pyproject.toml`, `pybind11` targets, or binding install docs in this checkout.

Root cause:
- This repository is centered on the C++ library/examples and does not provide a first-party Python package pipeline here.

Resolution used:
- Used pip package installation path in WSL (`orbslam3-python`) instead of in-repo build steps.

---

### 3) `pip` was missing in WSL base environment
Symptom:
- `python3 -m pip` failed with `No module named pip`.

Root cause:
- `python3-pip` was not installed in WSL Ubuntu image.

Resolution used:
- Installed `python3-pip` via apt.

---

### 4) Direct pip install was blocked by PEP 668 ("externally-managed-environment")
Symptom:
- `python3 -m pip install --user orbslam3-python` failed with externally managed environment error.

Root cause:
- Ubuntu system Python prevents direct pip writes to managed environments.

Resolution used:
- Switched to a project-local virtual environment and installed package there.

---

### 5) Virtual environment creation initially failed (`ensurepip` unavailable)
Symptom:
- `python3 -m venv .venv-wsl` failed and requested `python3.12-venv`.

Root cause:
- `python3.12-venv` was missing.

Resolution used:
- Installed `python3.12-venv` via apt and recreated the venv.

---

### 6) Environment mismatch risk (Windows Python vs WSL Python)
Symptom:
- Package import succeeded in WSL venv but still failed from Windows Python.

Root cause:
- Windows and WSL use separate Python runtimes and site-packages.

Resolution used:
- Standardized execution instructions to always activate WSL venv before running Python binding code.

## Clean install from scratch (recommended workflow)

This section is the procedure future agents should follow for the smoothest setup.

### A) Install WSL Python packaging prerequisites
Run in WSL as root:

```bash
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3-pip \
  python3.12-venv
```

### B) Create and activate a repo-local virtual environment
Run from repo root in WSL:

```bash
set -euo pipefail
cd /mnt/d/Projects/tools/ORB_SLAM3
python3 -m venv .venv-wsl
. .venv-wsl/bin/activate
```

### C) Install bindings package in the venv
Run in the activated venv:

```bash
set -euo pipefail
python -m pip install -U pip
python -m pip install orbslam3-python==2.0.0
```

### D) Verify install
Run in the activated venv:

```bash
python - <<'PY'
import importlib.metadata
import orbslam3
print("ORB_PY_OK")
print("version:", importlib.metadata.version("orbslam3-python"))
print("module:", orbslam3.__file__)
print("symbols:", [x for x in ["Sensor", "System", "create_system"] if hasattr(orbslam3, x)])
PY
```

Expected:
- `ORB_PY_OK` printed.
- Version printed as `2.0.0` (or chosen pinned version).
- Module path printed under `.venv-wsl/lib/python3.12/site-packages/orbslam3/...`.

## Verification checklist
Run from repo root:

```bash
# WSL venv path should succeed
wsl -e bash -lc 'cd /mnt/d/Projects/tools/ORB_SLAM3; . .venv-wsl/bin/activate; python -c "import orbslam3; print(\"WSL_ORB_PY_OK\")"'

# Windows Python intentionally separate; should be None unless separately installed
python -c "import importlib.util; print(importlib.util.find_spec('orbslam3'))"
```

Expected:
- First command prints `WSL_ORB_PY_OK`.
- Second command may print `None` if host Windows Python was not explicitly configured.

## Known warnings that did not block successful install

- PEP 668 warning when attempting direct pip install into system-managed Python (resolved by using venv).
- `pip` upgrade notices in venv are informational and non-fatal.

## Fast triage map for future agents

- If `No module named pip`:
- Install `python3-pip` in WSL.

- If pip reports `externally-managed-environment`:
- Do not force-install into system Python; create and use a venv.

- If `python3 -m venv` reports `ensurepip is not available`:
- Install `python3.12-venv` and recreate the venv.

- If import works in WSL but not Windows terminal:
- You are using a different Python runtime; activate `.venv-wsl` in WSL.

## Optional maintainability improvements (not required for install)

- Add a script such as `scripts/setup_wsl_python_bindings.sh` to automate steps A-D.
- Add a short "Python bindings (WSL)" section in `README.md` that points to this playbook.

## Instruction block for future agents

When asked to install Python bindings for this repo on Windows with minimal risk, use this exact strategy:

1. Install Python packaging prerequisites in WSL (`python3-pip`, `python3.12-venv`).
2. Create a repo-local WSL virtual environment (`.venv-wsl`).
3. Install bindings in that venv (pin version, then verify import).
4. Validate from WSL venv, not Windows host Python, unless host install is explicitly requested.
5. If any previous install attempts failed, remove `.venv-wsl` and recreate from zero.
