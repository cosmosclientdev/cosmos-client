#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${COSMOS_BASE_URL:-https://github.com/cosmosclientdev/cosmos-client/releases/latest/download}"
# The static files next to this script in the root of the public repo
STATIC_URL="${COSMOS_STATIC_URL:-https://raw.githubusercontent.com/cosmosclientdev/cosmos-client/main}"
APP_DIR="$HOME/.local/bin"
APP_PATH="$APP_DIR/cosmos-client"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

# The sing-box pin this copy of the script was published with; only the
# fallback for when latest.json cannot be fetched
SING_BOX_VERSION="1.14.0"

# The sing-box pin published in latest.json; it moves between releases
# (publish-static.yml), so a bump reaches macOS without a new script. Empty
# when the file cannot be fetched
published_sing_box_version() {
    curl -fsL --proto '=https' --max-time 15 "$STATIC_URL/latest.json" 2>/dev/null \
        | sed -n 's/.*"sing_box": *"\([^"]*\)".*/\1/p' || true
}

install_linux() {
    if [ "$(uname -m)" != "x86_64" ]; then
        echo "Only x86_64 builds are published for now" >&2
        exit 1
    fi

    # What the AppImage expects from the host, reported all at once with a
    # single install command so the user does not chase one missing package
    # after another.
    #
    # The AppImage carries the static type2 runtime, which needs no libfuse2:
    # it mounts itself through fusermount3 (or fusermount) found on $PATH,
    # shipped by the fuse3 package that mainstream distributions install by
    # default. Checking ldconfig for libfuse.so.2 here used to refuse to
    # install on distributions that have dropped libfuse2 (Ubuntu 24.04+).
    #
    # The libraries are the ones linuxdeploy leaves out on purpose (its
    # excludelist): the graphics driver stack (libglvnd, which Qt6 links
    # against), fontconfig/freetype, X11/xcb and wayland-client have to match
    # the host and are not bundled. Minimal Ubuntu/Debian installs and WSL
    # lack libopengl0, which makes the app fail to load at all. The list was
    # taken from the NEEDED entries of the AppImage contents minus what is
    # bundled, leaving out libc/libstdc++/zlib that every system has
    local missing=()
    if ! command -v fusermount3 >/dev/null && ! command -v fusermount >/dev/null; then
        missing+=(fusermount3)
    fi
    # ldconfig lives in /sbin, which is not on every user's $PATH. A missing
    # ldconfig is not treated as missing libraries
    local ldconfig
    ldconfig="$(command -v ldconfig || echo /sbin/ldconfig)"
    if [ -x "$ldconfig" ]; then
        local cache lib
        cache="$("$ldconfig" -p 2>/dev/null || true)"
        for lib in libOpenGL.so.0 libEGL.so.1 libGL.so.1 libGLX.so.0 \
                   libfontconfig.so.1 libfreetype.so.6 libwayland-client.so.0 \
                   libX11.so.6 libX11-xcb.so.1 libxcb.so.1; do
            # The arch tag skips 32-bit-only entries on multiarch systems
            case "$cache" in
                *"$lib (libc6,x86-64)"*) ;;
                *) missing+=("$lib") ;;
            esac
        done
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Cosmos Client needs system components that are missing here: ${missing[*]}" >&2
        echo "Install them first, then re-run this script:" >&2
        if command -v apt-get >/dev/null; then
            echo "    sudo apt install fuse3 libopengl0 libegl1 libgl1 libglx0 libfontconfig1 libfreetype6 libwayland-client0 libx11-6 libx11-xcb1 libxcb1" >&2
        elif command -v dnf >/dev/null; then
            echo "    sudo dnf install fuse3 libglvnd-opengl libglvnd-egl libglvnd-glx mesa-libGL mesa-libEGL fontconfig freetype libwayland-client libX11 libX11-xcb libxcb" >&2
        elif command -v pacman >/dev/null; then
            echo "    sudo pacman -S --needed fuse3 libglvnd mesa fontconfig freetype2 wayland libx11 libxcb" >&2
        else
            echo "    (use your distribution's package manager)" >&2
        fi
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
    local version
    version="$(published_sing_box_version)"
    version="${version:-$SING_BOX_VERSION}"
    local pkg="SFM-$version-Universal.pkg"
    local url="https://github.com/SagerNet/sing-box/releases/download/v$version/$pkg"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    echo "Cosmos Client has no macOS build yet — installing sing-box $version instead."
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
