#!/usr/bin/env bash
# Cosmos Client installer for Linux. Safe to re-run: it simply replaces the
# AppImage with the latest release, so it doubles as the updater.
set -euo pipefail

BASE_URL="${COSMOS_BASE_URL:-https://github.com/cosmosclientdev/cosmos-client/releases/latest/download}"
APP_DIR="$HOME/.local/bin"
APP_PATH="$APP_DIR/cosmos-client"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

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

echo "Downloading Cosmos Client..."
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
Comment=VPN client
Exec=$APP_PATH
Icon=cosmos-client
Terminal=false
Categories=Network;
StartupWMClass=cosmos_client
EOF
command -v update-desktop-database >/dev/null && update-desktop-database "$DESKTOP_DIR" || true

echo "Installed: $APP_PATH"
echo "If Cosmos Client is running, restart it to pick up the new version."
