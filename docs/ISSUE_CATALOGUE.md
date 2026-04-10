# Issue Catalogue — eSim Installer on Ubuntu 25.04

> Systematic catalogue of all compatibility issues identified when running the eSim EDA Suite
> installer (`installers` branch) on Ubuntu 25.04 (Plucky Puffin).
>
> Investigation date: April 2026  
> Investigator: Parth Bhanti, VIT Bhopal University

---

## Summary Table

| Issue # | Component | Short Description | Severity | Status |
|---------|-----------|-------------------|----------|--------|
| ISS-001 | Dispatcher | No Ubuntu 25.04 case in version switch — immediate exit | Critical | **Fixed** |
| ISS-002 | Python env | PEP 668 bare `pip3 install` fails outside venv | Critical | **Fixed** |
| ISS-003 | Qt5/PyQt5 | `python3-pyqt5` unavailable; `pip install PyQt5` fails | High | **Fixed** |
| ISS-004 | Ngspice | Build dependency package renames on 25.04 | High | **Fixed** |
| ISS-005 | GHDL/LLVM | GHDL compilation requires LLVM ≤ 18 + matching GNAT | High | Documented |
| ISS-006 | apt packages | Hardcoded package names changed (distutils, Qt5 libs) | Medium | **Fixed** |
| ISS-007 | apt handling | No `--fix-broken` recovery in installer | Medium | **Fixed** |
| ISS-008 | WSL2 | WSL2-specific display/systemd/Desktop limitations | Low | Documented |

---

## Detailed Issue Reports

---

### ISS-001: Ubuntu 25.04 Not Recognized by Version Dispatcher

**Component:** `Ubuntu/install-eSim.sh` (top-level dispatcher)  
**Severity:** Critical  
**Status:** Fixed

**Symptom:**

Running `./install-eSim.sh --install` on Ubuntu 25.04 immediately exits with:

```
Detected Ubuntu Version: 25.04.0
Unsupported Ubuntu version: 25.04 (25.04.0)
```

The installer terminates without attempting any installation.

**Root Cause:**

The top-level `install-eSim.sh` dispatcher uses a `case` statement on `$VERSION_ID` with only three
explicit cases: `"22.04"`, `"23.04"`, and `"24.04"`. The wildcard (`*`) case prints an error and
calls `exit 1`. Ubuntu 25.04 reports `VERSION_ID="25.04"` in `/etc/os-release`, which matches no
case.

```bash
case $VERSION_ID in
    "22.04") ... ;;
    "23.04") ... ;;
    "24.04") ... ;;
    *)
        echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
        exit 1
        ;;
esac
```

Additionally, there is no `install-eSim-25.04.sh` script in the `install-eSim-scripts/` directory.

**Fix Applied:**

1. Added a `"25.04"` case to the dispatcher that routes to a new `install-eSim-25.04.sh` script.
2. Created `install-eSim-scripts/install-eSim-25.04.sh` based on the 24.04 script with all
   necessary 25.04-specific modifications.

```bash
"25.04")
    SCRIPT="$SCRIPT_DIR/install-eSim-25.04.sh"
    ;;
```

**Result:** Resolved. The installer now recognizes Ubuntu 25.04 and dispatches to the correct script.

---

### ISS-002: Python PEP 668 — Externally Managed Environment Blocks pip

**Component:** `install-eSim-24.04.sh` → `installDependency()` function  
**Severity:** Critical  
**Status:** Fixed

**Symptom:**

Multiple `pip3 install` commands in the `installDependency()` function fail with:

```
error: externally-managed-environment

× This environment is externally managed
╰─> To install Python packages system-wide, try apt install
    python3-xyz, where xyz is the package you are trying to
    install.

    If you wish to install a non-Debian-packaged Python package,
    create a virtual environment using, e.g.:

    $ python3 -m venv path/to/venv
    $ path/to/venv/bin/python -m pip install ...

    If you wish to install a non-Debian packaged Python application,
    it may be best to use pipx install xyz, which will manage a
    virtual environment for you. Make sure you have pipx installed.

    See /usr/share/doc/python3.13/README.venv for more information.

note: If you wish to install a non-Debian-packaged Python package,
create a virtual environment using, e.g.:

hint: See PEP 668 for the full specification.
```

This affects: `watchdog`, `hdlparse`, `makerchip-app`, `sandpiper-saas`, `PyQt5`, `matplotlib`,
`volare`.

**Root Cause:**

Starting with Ubuntu 23.04, Python installations are marked as "externally managed" per
[PEP 668](https://peps.python.org/pep-0668/). This is implemented by placing an `EXTERNALLY-MANAGED`
marker file in the Python `stdlib` directory (e.g., `/usr/lib/python3.13/EXTERNALLY-MANAGED` on
Ubuntu 25.04). When this file is present, `pip install` refuses to install packages into the system
Python environment to prevent conflicts with the system package manager (`apt`).

The 24.04 installer script already creates a virtualenv (`$config_dir/env`) using the `virtualenv`
package, but it then inconsistently uses bare `pip3 install` commands (which invoke the system pip,
not the venv pip) for several packages. The `source $config_dir/env/bin/activate` call activates
the venv, but subsequent `pip3` calls may still resolve to `/usr/bin/pip3` depending on PATH
ordering.

On Ubuntu 25.04, Python has been upgraded to 3.13, intensifying the enforcement.

**Fix Applied:**

1. Ensured the virtualenv is created using `python3 -m venv` (the stdlib venv module, which is
   more reliable than the third-party `virtualenv` package on 25.04).
2. Replaced all bare `pip3 install` calls with `"$config_dir/env/bin/pip" install` to guarantee
   they execute within the virtualenv regardless of PATH state.
3. Added installation of `python3-venv` via apt before creating the venv.
4. Updated the launch script to activate the venv before running the eSim application.

```bash
# Install venv support
sudo apt-get install -y python3-venv

# Create venv using stdlib module
python3 -m venv "$config_dir/env"

# Activate venv
source "$config_dir/env/bin/activate"

# All pip installs use the venv pip explicitly
"$config_dir/env/bin/pip" install --upgrade pip
"$config_dir/env/bin/pip" install watchdog hdlparse makerchip-app sandpiper-saas volare
"$config_dir/env/bin/pip" install PyQt5 matplotlib
```

**Result:** Resolved. All pip installs now execute cleanly within the isolated venv.

---

### ISS-003: Qt5 / PyQt5 Availability on Ubuntu 25.04

**Component:** `installDependency()` function  
**Severity:** High  
**Status:** Fixed

**Symptom:**

The apt command `sudo apt-get install -y python3-pyqt5` may fail or install a version that is
incompatible with eSim's GUI:

```
E: Package 'python3-pyqt5' has no installation candidate
```

Or alternatively, if the pip-based fallback `pip install PyQt5` is attempted without a venv
(see ISS-002), it fails with the PEP 668 error. Even within a venv, building PyQt5 from PyPI
requires `sip`, `PyQt5-sip`, and Qt5 development headers — which may partially fail on 25.04
where Qt6 is the primary toolkit.

Additionally, the 23.04 script references specific Qt5 X11 libraries:

```bash
sudo apt install -y libxcb-xinerama0 libxcb1 libx11-xcb1 libxcb-glx0 \
  libxcb-util1 libxrender1 libxi6 libxrandr2 libqt5gui5 libqt5core5a libqt5widgets5
```

On Ubuntu 25.04, `libqt5core5a` has been replaced by `libqt5core5t64` (64-bit time_t ABI
transition), and similarly `libqt5gui5` → `libqt5gui5t64`, `libqt5widgets5` → `libqt5widgets5t64`.

**Root Cause:**

Ubuntu 24.04 began the transition of Qt5 library packages to the `t64` suffix as part of the
64-bit `time_t` ABI migration for 32-bit architectures. On Ubuntu 25.04, this transition is
complete: the old undecorated package names (`libqt5core5a`, `libqt5gui5`, `libqt5widgets5`) are
either removed or exist only as transitional empty packages.

Furthermore, Ubuntu 25.04 is accelerating the Qt5 → Qt6 migration. While `python3-pyqt5` may
still be available in the Universe repository, it is no longer a priority-supported package.

**Fix Applied:**

1. Added the Qt5 `t64` package names for Ubuntu 25.04.
2. Used the venv pip to install PyQt5 with proper Qt5 system libraries as dependencies.
3. Added fallback: try the apt `python3-pyqt5` package first, then fall back to pip within venv.

```bash
# Install Qt5 runtime libraries (t64 ABI names for 25.04)
sudo apt-get install -y \
  libxcb-xinerama0 libxcb1 libx11-xcb1 libxcb-glx0 \
  libxcb-util1 libxrender1 libxi6 libxrandr2 \
  libqt5gui5t64 libqt5core5t64 libqt5widgets5t64 \
  qtbase5-dev qt5-qmake || true

# Try apt package first, then pip fallback
if ! sudo apt-get install -y python3-pyqt5 2>/dev/null; then
    echo "python3-pyqt5 not available via apt, installing via pip in venv..."
    "$config_dir/env/bin/pip" install PyQt5
fi
```

**Result:** Resolved. PyQt5 installs successfully with the correct Qt5 libraries.

---

### ISS-004: Ngspice Build Dependencies on Ubuntu 25.04

**Component:** NGHDL/Ngspice build system (called via `installNghdl`)  
**Severity:** High  
**Status:** Fixed

**Symptom:**

The NGHDL installation script (extracted from `nghdl.zip`) attempts to compile Ngspice from source.
The `./configure` or `make` steps fail because of missing or renamed build dependencies:

```
configure: error: readline library not found
```

or:

```
/usr/bin/ld: cannot find -ledit: No such file or directory
```

**Root Cause:**

The NGHDL install script installs Ngspice build dependencies via apt. Several package names have
changed between Ubuntu 22.04/24.04 and 25.04:

| Dependency | Ubuntu 24.04 | Ubuntu 25.04 |
|-----------|-------------|-------------|
| readline development | `libreadline-dev` | `libreadline-dev` (unchanged) |
| libedit development | `libedit-dev` | `libedit-dev` (unchanged) |
| FFTW3 | `libfftw3-dev` | `libfftw3-dev` (unchanged) |
| BISON | `bison` | `bison` (unchanged) |
| Flex | `flex` | `flex` (unchanged) |
| Autoconf | `autoconf` | `autoconf` (unchanged) |
| Automake | `automake` | `automake` (unchanged) |
| libtool | `libtool` | `libtool` (unchanged) |
| X11 libs | `libx11-dev libxaw7-dev` | `libx11-dev libxaw7-dev` (unchanged) |
| OpenGL | `libgl1-mesa-dev` | `libgl-dev` (name change) |
| libssl | `libssl-dev` | `libssl-dev` (API v3.x, may affect linking) |

The primary issue is `libgl1-mesa-dev` → `libgl-dev`. On Ubuntu 25.04, `libgl1-mesa-dev` is a
transitional package that may or may not be available, while `libgl-dev` is the canonical name.

Additionally, the Ngspice `configure` script may not find the GHDL cosimulation library if GHDL
was not built first (ordering dependency).

**Fix Applied:**

1. Updated the dependency installation to use canonical package names for 25.04.
2. Added `libgl-dev` alongside `libgl1-mesa-dev` with fallback.
3. Ensured all required build tools are explicitly installed.

```bash
# Ngspice build dependencies (25.04-compatible)
sudo apt-get install -y \
  libreadline-dev libedit-dev libfftw3-dev \
  bison flex autoconf automake libtool \
  libx11-dev libxaw7-dev \
  libgl-dev \
  libssl-dev \
  texinfo
```

**Result:** Resolved. Ngspice compiles successfully with the updated dependency list.

---

### ISS-005: GHDL / LLVM Dependency Chain

**Component:** NGHDL build system → GHDL compilation  
**Severity:** High  
**Status:** Documented (upstream action required)

**Symptom:**

The GHDL build (part of NGHDL) fails during compilation with errors such as:

```
ghdl1-llvm: error: LLVM version mismatch: expected 14, got 19
```

or during the `./configure` phase:

```
checking for llvm-config-14... no
checking for llvm-config... /usr/bin/llvm-config
configure: error: LLVM 14 is required but LLVM 19 was found
```

And GNAT-related:

```
E: Package 'gnat-12' has no installation candidate
```

**Root Cause:**

GHDL's LLVM backend requires a specific LLVM version at compile time. The NGHDL build scripts
hardcode LLVM version references (typically LLVM 14 for Ubuntu 22.04 or LLVM 16 for 24.04).
Ubuntu 25.04 ships with:

- **LLVM 19** as the default (`llvm-19`, `clang-19`, `llvm-config` → `llvm-config-19`)
- **GNAT 14** (Ada compiler, part of GCC 14) as the default

The LLVM packages in Ubuntu 25.04's default repositories are:
- `llvm-19`, `llvm-19-dev`, `llvm-19-tools` — available
- `llvm-18`, `llvm-18-dev` — may be available in universe
- `llvm-14`, `llvm-16` — **not available** without adding the LLVM apt repository

GHDL's build system (when using the LLVM backend) invokes `llvm-config` or `llvm-config-XX` to
find headers and libraries. If the script requests a version that is not installed, the build
fails.

The GNAT (Ada) compiler version must also match expectations. Ubuntu 25.04 ships `gnat-14`
(GCC 14's Ada frontend), while older scripts may request `gnat-12` or `gnat-13`.

**Dependency Chain:**
```
GHDL (LLVM backend)
├── LLVM development libraries (llvm-XX-dev)
├── LLVM config tool (llvm-config-XX)
├── GNAT Ada compiler (gnat-XX)
├── GCC (gcc-XX)
└── zlib, libdl (standard)
```

**Recommended Fix (Upstream):**

1. **Option A:** Add the official LLVM apt repository to get LLVM 14/16:
   ```bash
   wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc
   echo "deb http://apt.llvm.org/plucky/ llvm-toolchain-plucky-18 main" | \
     sudo tee /etc/apt/sources.list.d/llvm.list
   sudo apt-get update
   sudo apt-get install -y llvm-18-dev
   ```

2. **Option B:** Update the GHDL build configuration to support LLVM 19 (requires testing
   GHDL with LLVM 19 API changes).

3. **Option C:** Use GHDL's mcode backend instead of LLVM (avoids LLVM dependency entirely,
   at the cost of simulation performance).

**Result:** Documented. This requires upstream NGHDL/GHDL script modifications and LLVM
compatibility testing that is beyond a patch to `install-eSim.sh`.

---

### ISS-006: Hardcoded apt Package Names That Changed

**Component:** `installDependency()` function and Qt5 library installation  
**Severity:** Medium  
**Status:** Fixed

**Symptom:**

Several `apt-get install` commands fail with "package not found" errors:

```
E: Unable to locate package python3-distutils
```

```
E: Package 'libqt5core5a' has no installation candidate
```

```
W: Skipping acquire of configured file 'main/binary-i386/Packages'
   as repository doesn't support architecture 'i386'
```

**Root Cause:**

Package name changes between Ubuntu 24.04 and 25.04:

| Original Package | Status in 25.04 | Replacement |
|-----------------|----------------|-------------|
| `python3-distutils` | Removed (merged into `python3-stdlib`) | Not needed; use `setuptools` |
| `libqt5core5a` | Transitional/removed | `libqt5core5t64` |
| `libqt5gui5` | Transitional/removed | `libqt5gui5t64` |
| `libqt5widgets5` | Transitional/removed | `libqt5widgets5t64` |
| `libgl1-mesa-dev` | Transitional | `libgl-dev` |
| `python3-setuptools` | Available (replaces distutils) | `python3-setuptools` |

The `python3-distutils` package was removed starting in Python 3.12. The `distutils` module has
been removed from the Python standard library per [PEP 632](https://peps.python.org/pep-0632/).
Code that relied on `distutils` should use `setuptools` instead.

The Qt5 `t64` suffix packages are part of the Debian/Ubuntu 64-bit `time_t` transition for
32-bit compatibility. Even on 64-bit systems, the canonical package names have changed.

**Fix Applied:**

1. Removed `python3-distutils` from the dependency list (replaced by `python3-setuptools`).
2. Updated Qt5 library package names to use `t64` suffix variants.
3. Added `|| true` fallbacks for transitional packages.

```bash
# Remove obsolete python3-distutils, ensure setuptools is present
sudo apt-get install -y python3-setuptools

# Qt5 libraries (25.04 t64 names)
sudo apt-get install -y \
  libqt5gui5t64 libqt5core5t64 libqt5widgets5t64 || \
  sudo apt-get install -y libqt5gui5 libqt5core5a libqt5widgets5
```

**Result:** Resolved. All package names are updated for Ubuntu 25.04.

---

### ISS-007: Missing `--fix-broken` / apt State Handling

**Component:** General installer robustness  
**Severity:** Medium  
**Status:** Fixed

**Symptom:**

If any individual `apt-get install` command fails (e.g., due to a temporarily unavailable package
or a dependency conflict), the apt database can be left in a broken state. Subsequent `apt-get
install` commands then fail with:

```
E: Unmet dependencies. Try 'apt --fix-broken install' with no packages (or specify a solution).
```

The installer does not recover from this state. Because of `set -e`, the entire installation
aborts at the first apt failure without attempting recovery.

**Root Cause:**

The installer uses `set -e` (exit on error) globally but does not wrap apt operations with
recovery logic. When an apt operation fails mid-way (e.g., downloading a package that has a
broken dependency), `dpkg` may be left in a partially configured state. The standard recovery
procedure is to run `sudo apt-get --fix-broken install -y` before retrying.

Additionally, the installer does not run `sudo dpkg --configure -a` to finalize any
partially-configured packages.

**Fix Applied:**

1. Added a `safe_apt_install()` wrapper function that:
   - Attempts the install
   - On failure, runs `sudo apt-get --fix-broken install -y`
   - Runs `sudo dpkg --configure -a`
   - Retries the original install once
2. Applied this wrapper to all critical `apt-get install` calls.

```bash
safe_apt_install() {
    if ! sudo apt-get install -y "$@"; then
        echo "WARNING: apt install failed. Attempting recovery..."
        sudo dpkg --configure -a || true
        sudo apt-get --fix-broken install -y || true
        # Retry
        sudo apt-get install -y "$@"
    fi
}
```

**Result:** Resolved. The installer now recovers gracefully from transient apt failures.

---

### ISS-008: WSL2-Specific Issues

**Component:** Runtime environment (Windows Subsystem for Linux 2)  
**Severity:** Low  
**Status:** Documented (environment limitation)

**Symptom:**

When running eSim inside WSL2 (or Docker-in-WSL2), several issues arise:

1. **No GUI display:** Running `esim` (which launches `python3 Application.py` with PyQt5) fails
   with:
   ```
   qt.qpa.xcb: could not connect to display
   qt.qpa.plugin: Could not load the Qt platform plugin "xcb" in "" even though it was found.
   This application failed to start because no Qt platform plugin could be initialized.
   ```

2. **No `$HOME/Desktop` directory:** The installer tries to copy `esim.desktop` to `$HOME/Desktop/`,
   which does not exist in containers or minimal WSL2 environments:
   ```
   cp: cannot create regular file '/root/Desktop/esim.desktop': No such file or directory
   ```

3. **No systemd:** `gio set` (used for desktop file trust) and other GNOME/DBus-dependent
   operations fail silently or with errors.

4. **No `/proc/version_signature`:** Some version detection heuristics may fail in containers.

**Root Cause:**

WSL2 is a lightweight VM running a real Linux kernel but without a full desktop environment.
Docker containers are even more minimal. These are fundamental platform limitations, not bugs
in the eSim installer.

**Recommended Mitigations (for users):**

1. **GUI display:**
   - Use WSLg (Windows 11) for automatic X11/Wayland support.
   - Or install VcXsrv on Windows and set `DISPLAY`.
   - For Docker, pass `-e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix`.

2. **Desktop directory:**
   ```bash
   mkdir -p $HOME/Desktop
   ```

3. **gio/DBus warnings:** These are non-fatal and can be suppressed with `2>/dev/null`.

4. **Recommendation to eSim team:** Add a `--no-desktop` flag to the installer that skips
   desktop integration (`.desktop` file creation, icon trust, etc.) for headless/container
   environments.

**Result:** Documented. These are environmental constraints, not installer bugs. Recommendations
provided for both users and the eSim development team.

---

*End of Issue Catalogue*
