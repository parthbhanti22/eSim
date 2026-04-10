# Environment Setup — Reproducing the Ubuntu 25.04 Test Environment

> This document provides complete, copy-pasteable instructions to reproduce the exact test
> environment used for this investigation.

---

## Prerequisites

- **Host OS:** Windows 10/11 with WSL2 enabled
- **WSL Distribution:** Debian (or Ubuntu) — used as the Docker host
- **Docker Engine:** Installed inside WSL2 (not Docker Desktop)
- **Internet access:** Required for pulling images and cloning repositories

## Step 1: Install and Configure WSL2

If WSL2 is not yet installed:

```powershell
# Run in PowerShell (Administrator)
wsl --install -d Debian
```

After installation, launch the Debian terminal and set up a user account.

## Step 2: Install Docker Inside WSL2

```bash
# Update package lists
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker prerequisites
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# Add current user to docker group (avoids needing sudo for docker commands)
sudo usermod -aG docker $USER

# Start Docker daemon (WSL2 may not have systemd)
sudo dockerd &
# Or, if using a systemd-enabled WSL2 distro:
# sudo systemctl start docker
```

> **Note:** If `systemctl` is not available (common in WSL2), start Docker with `sudo dockerd &`
> or configure `/etc/wsl.conf` to enable systemd:
> ```ini
> [boot]
> systemd=true
> ```
> Then restart WSL with `wsl --shutdown` from PowerShell.

## Step 3: Pull the Ubuntu 25.04 Image

```bash
docker pull ubuntu:25.04
```

Verify the image:

```bash
docker run --rm ubuntu:25.04 cat /etc/os-release
```

Expected output (excerpt):

```
VERSION_ID="25.04"
VERSION_CODENAME=plucky
PRETTY_NAME="Ubuntu Plucky Puffin (development branch)"
```

## Step 4: Create and Enter the Test Container

```bash
docker run -it \
  --name esim-test \
  --hostname esim-test \
  -e DEBIAN_FRONTEND=noninteractive \
  ubuntu:25.04 \
  /bin/bash
```

## Step 5: Install Base Dependencies Inside the Container

```bash
# Inside the container:
apt-get update && apt-get upgrade -y

# Install essential tools needed before running the eSim installer
apt-get install -y \
  git \
  wget \
  curl \
  sudo \
  lsb-release \
  software-properties-common \
  build-essential \
  unzip \
  xz-utils \
  ca-certificates \
  gnupg
```

## Step 6: Clone the eSim Repository (Installers Branch)

```bash
cd /opt
git clone https://github.com/FOSSEE/eSim.git -b installers
cd eSim
```

## Step 7: Run the Installer with Full Logging

```bash
# Run the installer and capture full output to a log file
bash Ubuntu/install-eSim.sh --install 2>&1 | tee /tmp/esim-install.log

# After completion (or failure), inspect the log:
cat /tmp/esim-install.log
```

## Step 8: Applying Patches (This Fork)

If you are testing with this fork's patched installer:

```bash
cd /opt
git clone https://github.com/<your-username>/eSim.git -b installers
cd eSim

# The patched install-eSim.sh includes a "25.04" case
# and install-eSim-scripts/install-eSim-25.04.sh is provided
bash Ubuntu/install-eSim.sh --install 2>&1 | tee /tmp/esim-install-patched.log
```

## Step 9: Saving Container State (Optional)

To save your container state for later investigation:

```bash
# From the WSL2 host (outside the container):
docker commit esim-test esim-test-snapshot:latest
```

To resume:

```bash
docker start -ai esim-test
```

## Step 10: WSL2 GUI Display (For eSim GUI Testing)

eSim requires a graphical display (PyQt5). In WSL2:

**Option A: WSLg (Windows 11 with WSL2 GUI support)**

Windows 11 includes WSLg, which automatically provides a Wayland/X11 display server.
No additional configuration is needed — just ensure your WSL2 is up to date:

```powershell
wsl --update
```

Inside the container, set the display variable:

```bash
export DISPLAY=:0
```

**Option B: X Server (Windows 10 or older WSL2)**

Install an X server on Windows (e.g., VcXsrv, X410) and configure:

```bash
export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):0.0
```

**Note:** GUI testing inside a Docker container requires additional X11 forwarding setup.
Pass `-e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix` to `docker run`.

---

## Quick Reference: One-Shot Test Command

For a quick, disposable test (pulls image, clones repo, runs installer):

```bash
docker run --rm -it ubuntu:25.04 bash -c '
  apt-get update && \
  apt-get install -y git sudo lsb-release software-properties-common \
    build-essential unzip wget curl ca-certificates gnupg xz-utils && \
  cd /opt && \
  git clone https://github.com/FOSSEE/eSim.git -b installers && \
  cd eSim && \
  bash Ubuntu/install-eSim.sh --install 2>&1 | tee /tmp/install.log; \
  echo "=== LOG END ==="; \
  tail -50 /tmp/install.log
'
```

---

*This environment was used for all testing and analysis in the investigation report.*
