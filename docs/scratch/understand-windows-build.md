# Understand Report: Windows Build Reproducibility

## 0) Top 5 facts, Top 5 risks

### Top 5 facts
- Fact 1: Official docs/tested path is Linux (`Ubuntu 16.04/18.04`) and build entrypoint is `./build.sh` (`README.md`, section `2. Prerequisites` and section `3. Building ORB-SLAM3 library and examples`).
- Fact 2: Build orchestration is split: third-party libs are built by `build.sh` (`build.sh`) while top-level CMake only includes `Thirdparty/g2o` as a subdirectory and links prebuilt third-party binaries by absolute path (`CMakeLists.txt`, symbol `target_link_libraries(${PROJECT_NAME} ...)`).
- Fact 3: Top-level link step hardcodes Linux shared object names and GCC-style system link flags (`CMakeLists.txt`, symbols `${PROJECT_SOURCE_DIR}/Thirdparty/DBoW2/lib/libDBoW2.so`, `${PROJECT_SOURCE_DIR}/Thirdparty/g2o/lib/libg2o.so`, `-lboost_serialization`, `-lcrypto`).
- Fact 4: Compiler feature gate assumes GCC/Clang `-std=` flags; MSVC fails that gate (`CMakeLists.txt`, symbols `CHECK_CXX_COMPILER_FLAG("-std=c++11" ...)`, `message(FATAL_ERROR "... has no C++11 support")`).
- Fact 5: Core headers/source include POSIX-only APIs (`<unistd.h>`, `usleep`), so native Windows (MSVC) is not directly supported without portability changes (`include/System.h`, `include/Settings.h`, `include/Config.h`, `src/*` symbols calling `usleep`).

### Top 5 risks
- Risk 1 (high): Native Windows configure fails immediately with MSVC due C++11 detection logic; blast radius is full build unblock (`CMakeLists.txt`, compiler flag check block).
- Risk 2 (high): Even with non-MSVC compiler on Windows, hardcoded `.so` paths and Linux-style `-l...` flags break link stage (`CMakeLists.txt`, `target_link_libraries`).
- Risk 3 (high): CMake 4.x compatibility issue from `cmake_minimum_required(VERSION 2.8)` can block configure on modern machines unless policy/version is pinned (`CMakeLists.txt`, first line).
- Risk 4 (medium): Build scripts are non-idempotent (`mkdir build` without existence checks), causing repeated builds to fail or require manual cleanup (`build.sh`, `build_ros.sh`).
- Risk 5 (medium): No CI or automated build validation in-repo, so reproducibility relies on manual environment parity and undocumented assumptions (repo root has no `.github/workflows` build pipeline).

## 1) Scope & assumptions

- Topic includes: reliable, repeatable build of this repo on Windows-hosted machines.
- Topic includes: build-tooling flow only (toolchain, dependencies, scripts, CMake graph, artifacts).
- Topic excludes: SLAM runtime quality, dataset calibration correctness, ROS runtime behavior.
- Topic excludes: source-porting implementation to native Windows in this pass (analysis only).
- Assumption: "reliable on any Windows machine" is best satisfied by a pinned Linux userspace on Windows (WSL2) because upstream build is Linux-first.

## 2) Relevant docs index (paths + summaries)

### Must-read docs (minimal set)
- `README.md`: authoritative prerequisites and official build entrypoint (`build.sh`), plus stated tested platforms.
- `Dependencies.md`: external and bundled dependency inventory.
- `build.sh`: real build execution order and generated artifacts.
- `CMakeLists.txt`: actual compiler checks, package discovery, link model, executable targets.
- `Thirdparty/DBoW2/CMakeLists.txt`: third-party local build flags and OpenCV dependency behavior.
- `Thirdparty/g2o/CMakeLists.txt`: OS-specific output directories and compiler flags that affect top-level linking.

### Nice-to-have docs
- `Changelog.md`: release context; indicates no explicit Windows support milestone.
- `build_ros.sh`: optional ROS build path (Linux-only, out of core scope).
- `Examples/REAMDME.md`: confirms examples are dataset usage docs, not build portability docs.

### Not included but considered
- `Calibration_Tutorial.pdf`: runtime calibration content, not needed for compile reproducibility.
- `Examples_old/REAMDME.md`: legacy examples, no build-system authority.

## 3) Dependency map (modules and package boundaries)

- Root build owner: `CMakeLists.txt` target `ORB_SLAM3`.
- External packages resolved by CMake: `OpenCV`, `Eigen3`, `Pangolin`, optional `realsense2` (`CMakeLists.txt`, `find_package(...)`).
- System libs (link by name): Boost serialization and OpenSSL crypto (`CMakeLists.txt`, `-lboost_serialization`, `-lcrypto`).
- Bundled third-party source trees: `Thirdparty/DBoW2`, `Thirdparty/g2o`, `Thirdparty/Sophus`.
- Third-party integration boundary:
- `g2o` is added as subdirectory from root (`CMakeLists.txt`, `add_subdirectory(Thirdparty/g2o)`).
- `DBoW2` is not added as subdirectory from root; root expects built binary at fixed path (`CMakeLists.txt`, hardcoded `.so`).
- Runtime artifact boundary: vocabulary tarball extraction (`Vocabulary/ORBvoc.txt.tar.gz` -> `Vocabulary/ORBvoc.txt`) performed by `build.sh`.

## 4) System overview (components, responsibilities, authority)

- Component: `build.sh`.
- Responsibility: orchestration and ordering across third-party builds and root build.
- State owner: shell working directories and generated `build` directories.
- Update authority: repository shell script logic.

- Component: top-level CMake project.
- Responsibility: dependency discovery, target definitions, final linking, example target graph.
- State owner: CMake cache + generated project files.
- Update authority: `CMakeLists.txt` and package configs installed on system.

- Component: third-party CMake projects (`DBoW2`, `g2o`, `Sophus`).
- Responsibility: producing third-party libs/headers expected by root link.
- State owner: `Thirdparty/*/build` trees and output `lib`/`bin` folders.
- Update authority: per-third-party `CMakeLists.txt`.

- Component: host package manager/toolchain.
- Responsibility: compiler, CMake, and dependency binaries/headers.
- State owner: machine environment.
- Update authority: OS package manager + manual installs.

## 5) Config/artifacts involved + where referenced

- `build.sh`: build order + vocabulary extraction.
- `build_ros.sh`: optional ROS build path.
- `CMakeLists.txt`: top-level compiler flags, dependency gates, library/output graph.
- `Thirdparty/DBoW2/CMakeLists.txt`: DBoW2 shared lib build and OpenCV resolution.
- `Thirdparty/g2o/CMakeLists.txt`: g2o output directory policy (`WIN32` -> `bin`, else `lib`).
- `Thirdparty/Sophus/CMakeLists.txt`: header-only target and optional tests/examples.
- `Vocabulary/ORBvoc.txt.tar.gz`: compressed runtime vocabulary.
- `Vocabulary/ORBvoc.txt`: expected extracted runtime file used by example invocations in `README.md`.

## 6) Load-bearing flows (build topic)

### Flow 1: Configure toolchain and compiler capability
- Text flow diagram: `cmake configure -> CMake C++11 flag probes -> pass/fail gate -> continue/abort`.
- Entry point(s): root `CMakeLists.txt` (`CHECK_CXX_COMPILER_FLAG`, C++11 gate block).
- Key files and symbols: `CMakeLists.txt` (`cmake_minimum_required`, `CHECK_CXX_COMPILER_FLAG`, `message(FATAL_ERROR ...)`).
- Deep dive notes:
- Control flow: CMake probes `-std=c++11` and `-std=c++0x`; if both fail, configure aborts.
- Data flow: probe results stored in `COMPILER_SUPPORTS_CXX11` / `COMPILER_SUPPORTS_CXX0X` cache booleans.
- Lifecycle timing: happens before any dependency `find_package`, so this is early hard gate.
- State owner(s) + update authority: CMake cache + root `CMakeLists.txt`.
- Invariants and ordering constraints: one `-std=` probe must succeed; this assumes GCC/Clang-like compilers.
- Edge cases and failure modes + blast radius: MSVC fails probe despite C++11 capability, blocking all downstream build stages.
- Tests and coverage notes: no automated coverage for this configure path in repo.

### Flow 2: Resolve external dependencies
- Text flow diagram: `configure -> find_package(OpenCV/Eigen/Pangolin/realsense2) -> imported vars/targets -> link inputs`.
- Entry point(s): root `CMakeLists.txt` (`find_package(...)`).
- Key files and symbols: `CMakeLists.txt` (`find_package(OpenCV 4.4)`, `find_package(Eigen3 3.1.0 REQUIRED)`, `find_package(Pangolin REQUIRED)`, `find_package(realsense2)`).
- Deep dive notes:
- Control flow: required deps abort configure when missing.
- Data flow: include and library variables consumed by include/link commands.
- Lifecycle timing: after compiler checks, before target graph completion.
- State owner(s) + update authority: host package installations + CMake cache.
- Invariants and ordering constraints: required packages must be discoverable by CMake.
- Edge cases and failure modes + blast radius: package naming/layout differences across Windows toolchains can block configure or later link.
- Tests and coverage notes: no lockfile/manifest in repo to pin versions or source locations.

### Flow 3: Build bundled third-party libraries
- Text flow diagram: `build.sh -> DBoW2 configure/build -> g2o configure/build -> Sophus configure/build`.
- Entry point(s): `build.sh`.
- Key files and symbols: `build.sh` (`cd Thirdparty/DBoW2`, `cmake ..`, `make -j`; same for g2o/Sophus).
- Deep dive notes:
- Control flow: strict sequential order; failure in any stage aborts remaining stages.
- Data flow: outputs expected in each third-party project output directory.
- Lifecycle timing: must complete before root link because root expects prebuilt DBoW2 artifact.
- State owner(s) + update authority: script-created `build` dirs + per-third-party CMake configs.
- Invariants and ordering constraints: `make` must exist; build directories absent or manually cleaned.
- Edge cases and failure modes + blast radius: reruns can fail on `mkdir build`; non-GNU environments break `make`-based assumptions.
- Tests and coverage notes: no scripted verification of produced library filenames/locations.

### Flow 4: Link ORB_SLAM3 shared library
- Text flow diagram: `root target build -> compile src/* -> link ORB_SLAM3 against external + third-party libs`.
- Entry point(s): root target declaration and link stanza.
- Key files and symbols: `CMakeLists.txt` (`add_library(ORB_SLAM3 SHARED ...)`, `target_link_libraries(${PROJECT_NAME} ...)`).
- Deep dive notes:
- Control flow: linker consumes OpenCV/Eigen/Pangolin vars plus fixed file paths and `-l...` flags.
- Data flow: hardcoded paths to `libDBoW2.so` and `libg2o.so`.
- Lifecycle timing: after third-party artifacts should exist.
- State owner(s) + update authority: top-level CMake link instructions.
- Invariants and ordering constraints: Linux-style artifact names and locations must match.
- Edge cases and failure modes + blast radius: Windows shared library naming/output conventions violate assumptions; main library fails to link.
- Tests and coverage notes: no cross-platform link checks.

### Flow 5: Build example executables (and optional RealSense)
- Text flow diagram: `configure -> add_executable blocks -> compile examples -> optional realsense examples if package found`.
- Entry point(s): root `CMakeLists.txt` executable blocks.
- Key files and symbols: `CMakeLists.txt` (`set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ...)`, `add_executable(...)`, `if(realsense2_FOUND) ...`).
- Deep dive notes:
- Control flow: many targets compile unconditionally once root library exists.
- Data flow: examples link to `ORB_SLAM3` library.
- Lifecycle timing: post-library build.
- State owner(s) + update authority: top-level CMake target graph.
- Invariants and ordering constraints: example sources must compile under selected platform headers/APIs.
- Edge cases and failure modes + blast radius: POSIX includes/usleep usage in headers/source create portability breakpoints for native Windows toolchains.
- Tests and coverage notes: no automated target matrix validating all example targets.

### Flow 6: Runtime vocabulary artifact extraction
- Text flow diagram: `build.sh -> cd Vocabulary -> tar -xf ORBvoc.txt.tar.gz -> ORBvoc.txt available to runtime commands`.
- Entry point(s): `build.sh` vocabulary section.
- Key files and symbols: `build.sh` (`tar -xf ORBvoc.txt.tar.gz`), `README.md` run command using `Vocabulary/ORBvoc.txt`.
- Deep dive notes:
- Control flow: extraction is part of build script, not CMake target.
- Data flow: compressed archive -> plain text vocabulary file.
- Lifecycle timing: before root configure in script sequence.
- State owner(s) + update authority: repository `Vocabulary` folder + shell script.
- Invariants and ordering constraints: extraction tool must exist and file must be present.
- Edge cases and failure modes + blast radius: missing extraction leads runtime failure even if compilation succeeded.
- Tests and coverage notes: no post-build check verifying vocabulary existence.

## 7) Key data models / schemas / state machines

- Build-state model:
- Configure state (CMake cache): compiler checks, package discovery results.
- Third-party artifact state: expected binaries in `Thirdparty/DBoW2/lib` and `Thirdparty/g2o/lib|bin`.
- Root artifact state: `lib/libORB_SLAM3.*` and executables in `Examples/*` directories.
- Runtime data state: `Vocabulary/ORBvoc.txt` extracted from tarball.

## 8) Configuration and environment dependencies

- Build tools: CMake, C/C++ compiler, make-compatible backend (per script), shell environment.
- Libraries: OpenCV (>=4.4 per top-level), Eigen3 (>=3.1.0), Pangolin (required), Boost serialization, OpenSSL crypto.
- Optional library: realsense2 (adds extra examples).
- External services: none.
- Environment variables: none required by current build scripts; package discovery may rely on standard CMake search paths.

## 9) Gotchas and footguns

- `cmake_minimum_required(VERSION 2.8)` is fragile with CMake 4.x.
- MSVC is rejected by current C++11 check logic even though MSVC supports modern C++.
- Hardcoded `.so` + `-l...` link items make target graph Linux-specific.
- `Thirdparty/g2o` output path diverges on `WIN32` (`bin`) vs root expectation (`lib`).
- `build.sh` / `build_ros.sh` are not idempotent due `mkdir build` without guard.
- POSIX headers/functions in public headers propagate portability issues widely.

## 10) Open questions

- Question 1: Is native Windows (MSVC/MinGW) a required support target or is WSL2-on-Windows acceptable?
- Location: `README.md` (no explicit Windows stance), `CMakeLists.txt` (Linux-biased link model).
- Decision blocked: whether to invest in cross-platform CMake/source portability changes.

- Question 2: Should reproducibility prioritize strict version pinning (container/lock) or simpler manual setup docs?
- Location: repo has no lockfile/manifest for dependency versions.
- Decision blocked: whether to add Docker/WSL automation scripts and CI validation.

- Question 3: Should `DBoW2` be moved to target-based linking (add_subdirectory/imported target) instead of fixed file path?
- Location: `CMakeLists.txt` hardcoded file path link item.
- Decision blocked: robustness of multi-platform linking and artifact naming.

## 11) Quick glossary

- `WSL2`: Windows Subsystem for Linux v2, Linux userspace on Windows host.
- `Top-level CMake`: root `CMakeLists.txt` that defines `ORB_SLAM3` and examples.
- `Third-party build`: local compilation of bundled `DBoW2`, `g2o`, `Sophus` projects.
- `Configure phase`: CMake dependency/compiler detection before compilation.
- `Link phase`: creation of shared libraries/executables from object files and dependencies.
- `Vocabulary artifact`: `Vocabulary/ORBvoc.txt` required by runtime examples.

## Practical recommendation for reliable Windows duplication

- Recommended path: standardize on WSL2 Ubuntu (Linux userspace) per machine instead of native Windows toolchains.
- Why: upstream build/test path is Linux-first (`README.md`), and current build graph contains native-Windows blockers (`CMakeLists.txt`, POSIX headers/usleep use).
- Minimum reproducible controls:
- Pin OS image/version (for example Ubuntu LTS in WSL2).
- Pin CMake major (<4 or update minimum policy handling in local workflow).
- Install dependencies with scripted package list and build Pangolin in-script.
- Use a single non-interactive bootstrap script that clones, installs deps, runs `build.sh`, and verifies `lib/libORB_SLAM3.so` plus one example binary.
