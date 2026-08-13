#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${COSMOS_BASE_URL:-https://github.com/cosmosclientdev/cosmos-client/releases/latest/download}"
APP_DIR="$HOME/.local/bin"
APP_PATH="$APP_DIR/cosmos-client"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

SING_BOX_VERSION="1.13.18"

install_linux() {
    if [ "$(uname -m)" != "x86_64" ]; then
        echo "Only x86_64 builds are published for now" >&2
        exit 1
    fi

    # AppImage needs libfuse2, and modern distributions do not ship it by default
    if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
        echo "libfuse2 is required to run AppImages. Install it first:" >&2
        echo "    sudo apt install libfuse2      # Debian/Ubuntu" >&2
        echo "    sudo dnf install fuse-libs     # Fedora" >&2
        exit 1
    fi

    mkdir -p "$APP_DIR" "$DESKTOP_DIR" "$ICON_DIR"

    # Remember whether this is a fresh install: this script also runs on every
    # auto-update, which must not recreate a desktop icon the user has deleted
    local fresh_install=true
    [ -e "$APP_PATH" ] && fresh_install=false

    echo "Downloading Cosmos Client..."
    local tmp
    tmp="$(mktemp "$APP_DIR/.cosmos-client.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    curl -fL --proto '=https' -o "$tmp" "$BASE_URL/cosmos-client-x86_64.AppImage"
    chmod +x "$tmp"
    # mv keeps a running instance alive on its old inode; cp would fail with
    # "Text file busy" while the application is running
    mv -f "$tmp" "$APP_PATH"
    trap - EXIT

    curl -fsL -o "$ICON_DIR/cosmos-client.png" "$BASE_URL/cosmos-client.png" || true

    cat > "$DESKTOP_DIR/cosmos-client.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Cosmos Client
Comment=Cosmos Client
Exec=$APP_PATH %u
Icon=cosmos-client
Terminal=false
Categories=Network;
StartupWMClass=cosmos_client
MimeType=x-scheme-handler/cosmos-client;
EOF
    command -v update-desktop-database >/dev/null && update-desktop-database "$DESKTOP_DIR" || true
    command -v xdg-mime >/dev/null && xdg-mime default cosmos-client.desktop x-scheme-handler/cosmos-client || true

    # On a fresh install also drop a launcher onto the desktop. GNOME shows a
    # warning icon for .desktop files there unless they are executable and
    # explicitly marked trusted; KDE/XFCE are fine with just the file
    if $fresh_install; then
        local desktop_dir
        desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
        if [ -d "$desktop_dir" ] && [ "$desktop_dir" != "$HOME" ]; then
            cp "$DESKTOP_DIR/cosmos-client.desktop" "$desktop_dir/"
            chmod +x "$desktop_dir/cosmos-client.desktop"
            gio set "$desktop_dir/cosmos-client.desktop" metadata::trusted true 2>/dev/null || true
        fi
    fi

    echo "✅ Installed: $APP_PATH"
    echo "If Cosmos Client is running, restart it to pick up the new version."
}

install_macos() {
    local pkg="SFM-$SING_BOX_VERSION-Universal.pkg"
    local url="https://github.com/SagerNet/sing-box/releases/download/v$SING_BOX_VERSION/$pkg"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    echo "Cosmos Client has no macOS build yet — installing sing-box $SING_BOX_VERSION instead."
    echo "Downloading $pkg..."
    curl -fL --proto '=https' -o "$tmp_dir/$pkg" "$url"

    echo "Opening the installer — follow its steps and enter the admin password when it asks."
    # The package installs system-wide and asks for the password itself, which
    # is why this script must not be run under sudo. -W blocks until the
    # installer window is closed, so the downloaded file outlives it
    open -W "$tmp_dir/$pkg"

    echo "✅ Done. Launch sing-box from Applications and add your subscription URL there."
}

# Everything lands in the user's home (Linux) or goes through the graphical
# installer, which elevates on its own (macOS). Running the whole script as
# root would only leave root-owned files in $HOME and a launcher for the
# wrong user
if [ "$(id -u)" = 0 ]; then
    echo "Do not run this installer as root: it installs for the current user." >&2
    echo "Re-run it without sudo." >&2
    exit 1
fi

case "$(uname -s)" in
    Linux) install_linux ;;
    Darwin) install_macos ;;
    *)
        echo "Unsupported operating system: $(uname -s)" >&2
        exit 1
        ;;
esac
