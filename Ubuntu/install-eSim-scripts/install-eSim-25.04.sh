#!/bin/bash
#=============================================================================
#          FILE: install-eSim-25.04.sh
#
#         USAGE: Called by install-eSim.sh dispatcher
#
#   DESCRIPTION: eSim installation script for Ubuntu 25.04 (Plucky Puffin)
#                Based on install-eSim-24.04.sh with compatibility fixes.
#
#       AUTHORS: Original: eSim Team, FOSSEE, IIT Bombay
#                Patches: Parth Bhanti (FOSSEE Summer Fellowship 2026, Task 4)
#
#       CREATED: April 2026
#
#  FIXES APPLIED:
#    FOSSEE-FIX-ISS-001: Ubuntu 25.04 version dispatch (in parent script)
#    FOSSEE-FIX-ISS-002: PEP 668 compliance — venv-based pip installs
#    FOSSEE-FIX-ISS-003: Qt5/PyQt5 availability with t64 package names
#    FOSSEE-FIX-ISS-004: Ngspice build dependency updates
#    FOSSEE-FIX-ISS-006: Hardcoded package name updates
#    FOSSEE-FIX-ISS-007: Defensive apt error handling with recovery
#=============================================================================

# =============================================================================
# FOSSEE-FIX-ISS-003: Install Qt5 runtime libraries (t64 ABI names for 25.04)
# On Ubuntu 25.04, Qt5 libraries use t64 suffix (64-bit time_t transition)
# =============================================================================
sudo apt-get install -y \
    libxcb-xinerama0 libxcb1 libx11-xcb1 libxcb-glx0 \
    libxcb-util1 libxrender1 libxi6 libxrandr2 \
    libqt5gui5t64 libqt5core5t64 libqt5widgets5t64 2>/dev/null || \
sudo apt-get install -y \
    libqt5gui5 libqt5core5a libqt5widgets5 2>/dev/null || true

# =============================================================================
# FOSSEE-FIX-ISS-002: Create virtual environment using stdlib venv (PEP 668)
# Ubuntu 25.04 (Python 3.13) enforces PEP 668 externally-managed-environment.
# All pip installs MUST go through a venv to avoid the EXTERNALLY-MANAGED error.
# =============================================================================
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."

    # Try to find a usable Python 3 version
    PYTHON_BIN=$(which python3.13 || which python3.12 || which python3.11 || which python3)

    if [ -z "$PYTHON_BIN" ]; then
        echo "No suitable Python 3.x found. Please install Python 3.11+."
        exit 1
    fi

    PYTHON_VERSION=$($PYTHON_BIN -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    VENV_PACKAGE="python${PYTHON_VERSION}-venv"

    # FOSSEE-FIX-ISS-002: Ensure venv module is available
    if ! $PYTHON_BIN -m venv --help > /dev/null 2>&1; then
        echo "! venv not found for Python $PYTHON_VERSION. Attempting to install $VENV_PACKAGE..."
        sudo apt-get update
        sudo apt-get install -y "$VENV_PACKAGE"
    fi

    # Try to fix ensurepip-related issues
    if ! $PYTHON_BIN -c "import ensurepip" &>/dev/null; then
        echo "! ensurepip is missing. Installing full Python package for $PYTHON_VERSION..."
        sudo apt-get install -y "python${PYTHON_VERSION}-full"
    fi

    $PYTHON_BIN -m venv venv
else
    echo "Virtual environment already exists."
fi

# Activate the virtual environment
source ./venv/bin/activate

# Ensure virtual environment is deactivated when script exits
trap 'if [[ -d "venv" ]]; then deactivate 2>/dev/null; fi' EXIT

# Get Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)

echo "Detected Ubuntu version: $UBUNTU_VERSION ($UBUNTU_CODENAME)"

# All variables go here
config_dir="$HOME/.esim"
config_file="config.ini"
eSim_Home=$(pwd)
ngspiceFlag=0

error_exit()
{
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
}

# =============================================================================
# FOSSEE-FIX-ISS-007: Defensive apt install wrapper with --fix-broken recovery
# Wraps apt-get install with automatic recovery on failure. Runs dpkg --configure -a
# and apt --fix-broken install before retrying once.
# =============================================================================
safe_apt_install()
{
    local attempt=0
    local max_attempts=2

    while [ $attempt -lt $max_attempts ]; do
        if sudo apt-get install -y "$@"; then
            return 0
        fi

        attempt=$((attempt + 1))
        echo "WARNING: apt-get install failed (attempt $attempt/$max_attempts). Attempting recovery..."
        sudo dpkg --configure -a 2>/dev/null || true
        sudo apt-get --fix-broken install -y 2>/dev/null || true
        sudo apt-get update 2>/dev/null || true
    done

    echo "ERROR: apt-get install failed after $max_attempts attempts for packages: $*"
    return 1
}


function createConfigFile
{
    # Creating config.ini file and adding configuration information
    # Check if config file is present
    if [ -d "$config_dir" ]; then
        rm "$config_dir/$config_file" && touch "$config_dir/$config_file"
    else
        mkdir -p "$config_dir" && touch "$config_dir/$config_file"
    fi

    echo "[eSim]" >> "$config_dir/$config_file"
    echo "eSim_HOME = $eSim_Home" >> "$config_dir/$config_file"
    echo "LICENSE = %(eSim_HOME)s/LICENSE" >> "$config_dir/$config_file"
    echo "KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz" >> "$config_dir/$config_file"
    echo "IMAGES = %(eSim_HOME)s/images" >> "$config_dir/$config_file"
    echo "VERSION = %(eSim_HOME)s/VERSION" >> "$config_dir/$config_file"
    echo "MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json" >> "$config_dir/$config_file"
}


function installNghdl
{
    echo "Installing NGHDL..........................."
    unzip -o nghdl.zip
    cd nghdl/
    chmod +x install-nghdl.sh

    # Do not trap on error of any command. Let NGHDL script handle its own errors.
    trap "" ERR

    ./install-nghdl.sh --install       # Install NGHDL

    # Set trap again to error_exit function to exit on errors
    trap error_exit ERR

    ngspiceFlag=1
    cd ../
}


function installSky130Pdk
{
    echo "Installing SKY130 PDK......................"

    # Remove any previous sky130-fd-pdr instance, if any
    sudo rm -rf /usr/share/local/sky130_fd_pr

    # FOSSEE-FIX-ISS-002: Use venv pip for volare
    # Installing sky130 via volare (installed in venv)
    volare enable --pdk sky130 --pdk-root /usr/share/local/ 0fe599b2afb6708d281543108caf8310912f54af

    # Copy SKY130 library
    echo "Copying SKY130 PDK........................."

    sudo mkdir -p /usr/share/local/
    sudo mv /usr/share/local/volare/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af/sky130A/libs.ref/sky130_fd_pr /usr/share/local/
    rm -rf /usr/share/local/volare/

    # Change ownership from root to the user
    sudo chown -R "$USER:$USER" /usr/share/local/sky130_fd_pr/
}


function installIhpPdk
{
    echo -n "Do you want to install IHP Open PDK for analog IC design? (y/n): "
    read installIhp

    if [ "$installIhp" == "y" -o "$installIhp" == "Y" ]; then
        echo "Installing IHP Open PDK........................"

        if [ -f "ihp/ihp-install-script.sh" ]; then
            cd ihp/
            chmod +x ihp-install-script.sh
            trap "" ERR
            ./ihp-install-script.sh --install
            trap error_exit ERR
            cd ../
        else
            echo "IHP install script not found. Skipping..."
        fi
    else
        echo "Skipping IHP Open PDK installation"
    fi
}


function installKicad
{
    echo "Installing KiCad..........................."

    # Detect Ubuntu version
    ubuntu_version=$(lsb_release -rs)

    # FOSSEE-FIX-ISS-003: KiCad PPA for Ubuntu 25.04
    # KiCad 8.0 PPA should work for 25.04; if not available, try building from source
    if [[ "$ubuntu_version" == "25.04" || "$ubuntu_version" == "24.04" ]]; then
        echo "Ubuntu $ubuntu_version detected."
        kicadppa="kicad/kicad-8.0-releases"

        # Check if KiCad is installed using dpkg-query for the main package
        if dpkg -s kicad &>/dev/null; then
            installed_version=$(dpkg-query -W -f='${Version}' kicad | cut -d'.' -f1)
            if [[ "$installed_version" != "8" ]]; then
                echo "A different version of KiCad ($installed_version) is installed."
                read -p "Do you want to remove it and install KiCad 8.0? (yes/no): " response

                if [[ "$response" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
                    echo "Removing KiCad $installed_version..."
                    sudo apt-get remove --purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
                    sudo apt-get autoremove -y
                else
                    echo "Exiting installation. KiCad $installed_version remains installed."
                    exit 1
                fi
            else
                echo "KiCad 8.0 is already installed."
                return 0
            fi
        fi
    else
        kicadppa="kicad/kicad-6.0-releases"
    fi

    # Check if the PPA is already added
    if ! grep -q "^deb .*${kicadppa}" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "Adding KiCad PPA to local apt repository: $kicadppa"
        sudo add-apt-repository -y "ppa:$kicadppa"
        sudo apt-get update
    else
        echo "KiCad PPA is already present in sources."
    fi

    # FOSSEE-FIX-ISS-007: Use safe_apt_install for KiCad
    safe_apt_install kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates

    echo "KiCad installation completed successfully!"
}


function installDependency
{
    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Update apt repository
    echo "Updating apt index files..................."
    sudo apt-get update

    # FOSSEE-FIX-ISS-007: Run fix-broken before starting dependency installation
    sudo dpkg --configure -a 2>/dev/null || true
    sudo apt-get --fix-broken install -y 2>/dev/null || true

    set -e      # Re-enable exit on error
    trap error_exit ERR

    # FOSSEE-FIX-ISS-002: Install venv support from apt (PEP 668 compliance)
    echo "Installing Python3 venv support............"
    safe_apt_install python3-venv python3-pip

    # FOSSEE-FIX-ISS-002: Create and activate virtualenv using stdlib venv
    echo "Creating virtual environment to isolate packages (PEP 668 compliant)..."
    if [ ! -d "$config_dir/env" ]; then
        python3 -m venv "$config_dir/env"
    fi

    echo "Activating the virtual env................."
    source "$config_dir/env/bin/activate"

    echo "Upgrading Pip.............................."
    # FOSSEE-FIX-ISS-002: Explicit venv pip path to avoid system pip interference
    "$config_dir/env/bin/pip" install --upgrade pip

    echo "Installing Xterm..........................."
    safe_apt_install xterm

    echo "Installing Psutil.........................."
    safe_apt_install python3-psutil

    # FOSSEE-FIX-ISS-003: Qt5 / PyQt5 availability on Ubuntu 25.04
    echo "Installing Qt5 runtime libraries..........."
    sudo apt-get install -y \
        libxcb-xinerama0 libxcb1 libx11-xcb1 libxcb-glx0 \
        libxcb-util1 libxrender1 libxi6 libxrandr2 \
        libqt5gui5t64 libqt5core5t64 libqt5widgets5t64 \
        qtbase5-dev qt5-qmake 2>/dev/null || \
    sudo apt-get install -y \
        libqt5gui5 libqt5core5a libqt5widgets5 2>/dev/null || true

    echo "Installing PyQt5 (apt fallback to pip)....."
    if ! sudo apt-get install -y python3-pyqt5 2>/dev/null; then
        echo "python3-pyqt5 not available via apt. Installing via pip in venv..."
        "$config_dir/env/bin/pip" install PyQt5
    fi

    echo "Installing Matplotlib......................"
    if ! sudo apt-get install -y python3-matplotlib 2>/dev/null; then
        "$config_dir/env/bin/pip" install matplotlib
    fi

    # FOSSEE-FIX-ISS-006: Removed python3-distutils (removed in Python 3.12+, PEP 632)
    # Using python3-setuptools instead
    echo "Installing Setuptools...................."
    safe_apt_install python3-setuptools

    # Install NgVeri Dependencies
    echo "Installing Pip3............................"
    sudo apt-get install -y python3-pip || true

    # FOSSEE-FIX-ISS-002: All pip installs use explicit venv pip path
    echo "Installing Watchdog........................"
    "$config_dir/env/bin/pip" install watchdog

    echo "Installing Hdlparse........................"
    "$config_dir/env/bin/pip" install --upgrade https://github.com/hdl/pyhdlparser/tarball/master

    echo "Installing Makerchip......................."
    "$config_dir/env/bin/pip" install makerchip-app

    echo "Installing SandPiper Saas.................."
    "$config_dir/env/bin/pip" install sandpiper-saas

    echo "Installing Hdlparse......................"
    "$config_dir/env/bin/pip" install hdlparse

    echo "Installing matplotlib...................."
    "$config_dir/env/bin/pip" install matplotlib

    echo "Installing PyQt5 (in venv)................."
    "$config_dir/env/bin/pip" install PyQt5

    echo "Installing volare.........................."
    # FOSSEE-FIX-ISS-006: Fixed missing 'install' subcommand for xz-utils
    safe_apt_install xz-utils
    "$config_dir/env/bin/pip" install volare

    # FOSSEE-FIX-ISS-004: Install Ngspice build dependencies (25.04 package names)
    echo "Installing Ngspice build dependencies......"
    safe_apt_install \
        build-essential \
        libreadline-dev libedit-dev libfftw3-dev \
        bison flex autoconf automake libtool \
        libx11-dev libxaw7-dev \
        libssl-dev texinfo gperf
    # FOSSEE-FIX-ISS-004: libgl1-mesa-dev renamed to libgl-dev on 25.04
    sudo apt-get install -y libgl-dev 2>/dev/null || \
        sudo apt-get install -y libgl1-mesa-dev 2>/dev/null || true
}


function copyKicadLibrary
{
    #Extract custom KiCad Library
    tar -xJf library/kicadLibrary.tar.xz

    # FOSSEE-FIX-ISS-003: KiCad 8 uses different config path than KiCad 6
    if [[ "$ubuntu_version" == "25.04" || "$ubuntu_version" == "24.04" ]]; then
        KICAD_CONFIG_DIR="$HOME/.config/kicad/8.0"
    else
        KICAD_CONFIG_DIR="$HOME/.config/kicad/6.0"
    fi

    if [ -d "$KICAD_CONFIG_DIR" ]; then
        echo "KiCad config folder already exists at $KICAD_CONFIG_DIR"
    else
        echo "$KICAD_CONFIG_DIR does not exist, creating..."
        mkdir -p "$KICAD_CONFIG_DIR"
    fi

    # Copy symbol table for eSim custom symbols
    cp kicadLibrary/template/sym-lib-table "$KICAD_CONFIG_DIR/"
    echo "Symbol table copied to $KICAD_CONFIG_DIR"

    # Copy KiCad symbols made for eSim
    sudo cp -r kicadLibrary/eSim-symbols/* /usr/share/kicad/symbols/

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Remove extracted KiCad Library - not needed anymore
    rm -rf kicadLibrary

    set -e      # Re-enable exit on error
    trap error_exit ERR

    #Change ownership from Root to the User
    sudo chown -R "$USER:$USER" /usr/share/kicad/symbols/
}


function createDesktopStartScript
{
    # FOSSEE-FIX-ISS-002: Launch script activates venv before running eSim
    # Generating new esim-start.sh
    echo '#!/bin/bash' > esim-start.sh
    echo "cd $eSim_Home/src/frontEnd || exit" >> esim-start.sh
    echo "source $config_dir/env/bin/activate" >> esim-start.sh
    echo "python3 Application.py" >> esim-start.sh

    # Make it executable
    sudo chmod 755 esim-start.sh
    # Copy esim start script
    sudo cp -vp esim-start.sh /usr/bin/esim
    # Remove local copy of esim start script
    rm esim-start.sh

    # Generating esim.desktop file
    echo "[Desktop Entry]" > esim.desktop
    echo "Version=1.0" >> esim.desktop
    echo "Name=eSim" >> esim.desktop
    echo "Comment=EDA Tool" >> esim.desktop
    echo "GenericName=eSim" >> esim.desktop
    echo "Keywords=eda-tools" >> esim.desktop
    echo "Exec=esim %u" >> esim.desktop
    echo "Terminal=true" >> esim.desktop
    echo "X-MultipleArgs=false" >> esim.desktop
    echo "Type=Application" >> esim.desktop
    getIcon="$config_dir/logo.png"
    echo "Icon=$getIcon" >> esim.desktop
    echo "Categories=Development;" >> esim.desktop
    echo "MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;" >> esim.desktop
    echo "StartupNotify=true" >> esim.desktop

    # Make esim.desktop file executable
    sudo chmod 755 esim.desktop
    # Copy desktop icon file to share applications
    sudo cp -vp esim.desktop /usr/share/applications/

    # FOSSEE-FIX-ISS-008: Handle missing Desktop directory in containers/WSL2
    if [ -d "$HOME/Desktop" ]; then
        cp -vp esim.desktop "$HOME/Desktop/"
    else
        echo "WARNING: $HOME/Desktop does not exist. Skipping desktop icon copy."
        echo "  (This is expected in Docker containers and some WSL2 environments.)"
        mkdir -p "$HOME/Desktop" 2>/dev/null && cp -vp esim.desktop "$HOME/Desktop/" || true
    fi

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Make esim.desktop file as trusted application
    gio set "$HOME/Desktop/esim.desktop" "metadata::trusted" true 2>/dev/null || true
    # Set Permission and Execution bit
    chmod a+x "$HOME/Desktop/esim.desktop" 2>/dev/null || true

    # Remove local copy of esim.desktop file
    rm esim.desktop

    set -e      # Re-enable exit on error
    trap error_exit ERR

    # Copying logo.png to .esim directory to access as icon
    cp -vp images/logo.png "$config_dir"
}


####################################################################

####################################################################

if [ "$#" -eq 1 ]; then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1;
fi

if [ "$option" == "--install" ]; then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap error_exit ERR


    echo "Enter proxy details if you are connected to internet through proxy"

    echo -n "Is your internet connection behind proxy? (y/n): "
    read getProxy
    if [ "$getProxy" == "y" -o "$getProxy" == "Y" ]; then
        echo -n 'Proxy Hostname :'
        read proxyHostname

        echo -n 'Proxy Port :'
        read proxyPort

        echo -n "username@$proxyHostname:$proxyPort :"
        read username

        echo -n 'Password :'
        read -s passwd

        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        unset ftp_proxy
        unset FTP_PROXY

        export http_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export https_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export HTTP_PROXY="http://$username:$passwd@$proxyHostname:$proxyPort"
        export HTTPS_PROXY="http://$username:$passwd@$proxyHostname:$proxyPort"
        export ftp_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export FTP_PROXY="http://$username:$passwd@$proxyHostname:$proxyPort"

        echo "Install with proxy"

    elif [ "$getProxy" == "n" -o "$getProxy" == "N" ]; then
        echo "Install without proxy"

    else
        echo "Please select the right option"
        exit 0
    fi

    # Calling functions
    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    installIhpPdk
    createDesktopStartScript

    if [ $? -ne 0 ]; then
        echo -e "\n\n\nERROR: Unable to install required packages. Please check your internet connection.\n\n"
        exit 0
    fi

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on \"eSim\" icon placed on Desktop"


elif [ "$option" == "--uninstall" ]; then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK along with their models and libraries (y/n):"
    read getConfirmation
    if [ "$getConfirmation" == "y" -o "$getConfirmation" == "Y" ]; then
        echo "Removing eSim............................"
        sudo rm -rf "$HOME/.esim" "$HOME/Desktop/esim.desktop" /usr/bin/esim /usr/share/applications/esim.desktop
        echo "Removing KiCad..........................."
        sudo apt purge -y kicad kicad-footprints kicad-libraries kicad-symbols kicad-templates
        sudo rm -rf /usr/share/kicad
        sudo rm -f /etc/apt/sources.list.d/kicad*
        rm -rf "$HOME/.config/kicad/8.0"
        rm -rf "$HOME/.config/kicad/6.0"

        echo "Removing Virtual env......................."
        sudo rm -rf "$config_dir/env"

        echo "Removing Makerchip......................."
        pip3 uninstall -y hdlparse makerchip-app sandpiper-saas 2>/dev/null || true

        echo "Removing SKY130 PDK......................"
        sudo rm -rf /usr/share/local/sky130_fd_pr

        echo "Removing IHP Open PDK...................."
        if [ -f "ihp/install-ihp-openpdk.sh" ]; then
            cd ihp/
            chmod +x install-ihp-openpdk.sh
            ./install-ihp-openpdk.sh --uninstall
            cd ../
        fi

        echo "Removing NGHDL..........................."
        rm -rf library/modelParamXML/Nghdl/*
        rm -rf library/modelParamXML/Ngveri/*
        if [ -d "nghdl" ]; then
            cd nghdl/
            chmod +x install-nghdl.sh
            ./install-nghdl.sh --uninstall
            cd ../
            rm -rf nghdl
            echo -e "----------------eSim Uninstalled Successfully----------------"
        else
            echo -e "\nCannot find \"nghdl\" directory. Please remove it manually"
        fi

        deactivate 2>/dev/null || true
        rm -rf venv

    elif [ "$getConfirmation" == "n" -o "$getConfirmation" == "N" ]; then
        exit 0
    else
        echo "Please select the right option."
        exit 0
    fi

else
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi
