#!/usr/bin/env bash
set -Eeuo pipefail

# Check for Termux:X11
read -r -p "Do you have Termux:X11 installed? (y/n): " has_x11
if [[ ! "$has_x11" =~ ^[Yy]$ ]]; then
    echo "Downloading Termux:X11 to your Download folder..."
    termux-setup-storage
    mkdir -p "$HOME/storage/shared/Download"
    curl --fail --location --show-error --progress-bar \
        -o "$HOME/storage/shared/Download/termux-x11.apk" \
        "https://github.com/termux/termux-x11/releases/download/nightly/termux-x11-universal-debug.apk"

    echo
    echo "--------------------------------------------------"
    echo "APK downloaded to your Download folder!"
    echo "Install termux-x11.apk using your file manager."
    echo "--------------------------------------------------"
    read -r -p "Press Enter after installing Termux:X11..."
fi

# Install Termux packages
pkg update
pkg upgrade -y
pkg install -y proot-distro curl wget x11-repo
pkg update
pkg install -y termux-x11-nightly xorg-xdpyinfo

# Install Ubuntu if not already installed
if proot-distro list -q | grep -Fxq 'ubuntu'; then
    echo "Ubuntu is already installed. Reusing it."
else
    echo "Ubuntu is not installed. Installing..."
    proot-distro install ubuntu
fi

# Install Ubuntu dependencies and HwGDReqs
proot-distro login --shared-tmp ubuntu -- \
    bash -euc '
        apt update
        apt upgrade -y

        apt install -y python3 python3-pip python3-venv xfwm4 x11-apps libxcb-cursor0 libxkbcommon-x11-0  libglib2.0-0 libgl1 libegl1 libxkbcommon0 libdbus-1-3 libfontconfig1 libfreetype6 libx11-xcb1 libcairo2 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-sync1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libxrender1 libxi6 libsm6 libice6

        python3 -m venv /opt/hwgdreqs-venv

        /opt/hwgdreqs-venv/bin/pip install --upgrade pip
        /opt/hwgdreqs-venv/bin/pip install hwgdreqs
    '

# Create HwGDReqs launcher
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/run-hwgdreqs" <<'LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

DISPLAY=:1
export DISPLAY

WM_PID=""
APP_PID=""

cleanup() {
    trap - EXIT INT TERM

    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
    fi

    if [[ -n "$WM_PID" ]]; then
        kill "$WM_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Start Termux:X11 if not already running
if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    termux-x11 "$DISPLAY" >/dev/null 2>&1 &
    X11_PID=$!

    echo "Waiting for Termux:X11..."

    ready=false

    for _ in {1..30}; do
        if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
            ready=true
            break
        fi

        # Stop if the process exited
        if ! kill -0 "$X11_PID" 2>/dev/null; then
            break
        fi

        sleep 0.5
    done

    if [[ "$ready" != true ]]; then
        echo "ERROR: Termux:X11 did not become ready." >&2
        echo "Check the Termux:X11 installation and Android app." >&2
        exit 1
    fi
fi

# Open the Android X11 activity
am start --user 0 \
    -n com.termux.x11/com.termux.x11.MainActivity

# Start the Ubuntu window manager
proot-distro login ubuntu --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix -- \
    bash -lc 'export DISPLAY=:1; exec xfwm4' &
WM_PID=$!

sleep 1

# Start HwGDReqs
echo "Launching HwGDReqs..."

proot-distro login --shared-tmp ubuntu -- \
    bash -lc 'export DISPLAY=:1; exec /opt/hwgdreqs-venv/bin/hwgdreqs' &
APP_PID=$!

wait "$APP_PID"
LAUNCHER

chmod +x "$HOME/.local/bin/run-hwgdreqs"

# Add ~/.local/bin to PATH without duplicates
export PATH="$HOME/.local/bin:$PATH"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$rc"

    if ! grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$rc"; then
        printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi
done

echo
echo "======"
echo "Setup complete!"
echo "Run: run-hwgdreqs"
echo "======" # ai ahh ones but idc
