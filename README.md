# eSim Installer — Ubuntu 25.04 Compatibility Investigation

> **FOSSEE Summer Fellowship 2026 — Task 4 Submission**  
> Investigator: Parth Bhanti, VIT Bhopal University  
> Date: April 2026

---

## Overview

This fork of [FOSSEE/eSim](https://github.com/FOSSEE/eSim) (branch: `installers`) contains a
systematic compatibility investigation of the eSim EDA Suite installer against **Ubuntu 25.04
(Plucky Puffin)**. The eSim installer was originally developed and tested for Ubuntu 22.04 and 24.04
LTS releases. As the Ubuntu ecosystem evolves — with changes in LLVM packaging, Python environment
policy (PEP 668), Qt5/Qt6 transitions, and package renames — the installer encounters multiple
breakages on Ubuntu 25.04.

This investigation identified **8 distinct issues**, of which **5 have been fixed** with patches
and **3 are documented** with upstream recommendations.

## Repository Structure

```
.
├── README.md                              # This file
├── docs/
│   ├── ENVIRONMENT_SETUP.md               # Reproduction environment instructions
│   ├── ISSUE_CATALOGUE.md                 # Structured issue catalogue (all 8 issues)
│   └── INVESTIGATION_REPORT.md            # Full investigation report
└── Ubuntu/
    ├── install-eSim.sh                    # Patched top-level dispatcher (25.04 support)
    ├── install-eSim-scripts/
    │   └── install-eSim-25.04.sh          # New 25.04-specific installer (patched)
    └── patches/
        ├── fix-001-version-dispatch.patch # Adds 25.04 case to dispatcher
        ├── fix-002-pip-pep668.patch       # PEP 668 compliance (venv-based pip)
        ├── fix-003-qt5-availability.patch # Qt5/PyQt5 package resolution
        ├── fix-004-ngspice-deps.patch     # Ngspice build dependency updates
        └── fix-005-apt-robustness.patch   # Defensive apt error handling

```

## Issues Found

| Issue # | Component | Short Description | Severity | Status |
|---------|-----------|-------------------|----------|--------|
| ISS-001 | Dispatcher | No Ubuntu 25.04 case in version switch | Critical | **Fixed** |
| ISS-002 | Python env | PEP 668 bare `pip install` failures | Critical | **Fixed** |
| ISS-003 | Qt5/PyQt5 | `python3-pyqt5` / PyQt5 availability on 25.04 | High | **Fixed** |
| ISS-004 | Ngspice | Build dependency package name changes | High | **Fixed** |
| ISS-005 | GHDL/LLVM | GHDL build requires specific LLVM+GNAT chain | High | Documented |
| ISS-006 | apt packages | Hardcoded package names changed in 25.04 | Medium | **Fixed** |
| ISS-007 | apt handling | No `--fix-broken` recovery or graceful retry | Medium | **Fixed** |
| ISS-008 | WSL2 | WSL2-specific display/systemd limitations | Low | Documented |

## How to Apply Patches

### Option A: Use the patched installer directly

```bash
# Clone this fork
git clone https://github.com/parthbhanti22/eSim.git -b installers
cd eSim

# The patched install-eSim.sh already includes Ubuntu 25.04 support
sudo bash Ubuntu/install-eSim.sh --install
```

### Option B: Apply patches to upstream

```bash
# Clone upstream
git clone https://github.com/FOSSEE/eSim.git -b installers
cd eSim

# Apply individual patches
git apply Ubuntu/patches/fix-001-version-dispatch.patch
git apply Ubuntu/patches/fix-002-pip-pep668.patch
git apply Ubuntu/patches/fix-003-qt5-availability.patch
git apply Ubuntu/patches/fix-004-ngspice-deps.patch
git apply Ubuntu/patches/fix-005-apt-robustness.patch
```

## Reproducing the Test Environment

See [docs/ENVIRONMENT_SETUP.md](docs/ENVIRONMENT_SETUP.md) for complete Docker-on-WSL2
reproduction instructions.

## Full Report

See [docs/INVESTIGATION_REPORT.md](docs/INVESTIGATION_REPORT.md) for the detailed engineering
investigation report with full technical analysis, comparison tables, and recommendations.

## License

This fork inherits the [GPL-3.0 license](https://github.com/FOSSEE/eSim/blob/master/LICENSE)
from the upstream FOSSEE/eSim project.

---

*Submitted as part of FOSSEE Summer Fellowship 2026, Task 4.*  
*Contact: Parth Bhanti — VIT Bhopal University*
