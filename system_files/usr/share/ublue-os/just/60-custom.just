# topaz-os recipes (imported via the 60-custom.just hook in 00-entry.just)

# Make Qt Flatpaks on the KDE runtime follow GNOME dark mode (Kvantum)
topaz-qt-dark:
    #!/usr/bin/bash
    set -euo pipefail
    branches=$(flatpak list --runtime --columns=application,branch 2>/dev/null \
        | awk '$1 == "org.kde.Platform" {print $2}' | sort -u)
    if [ -z "$branches" ]; then
        echo "No KDE runtimes installed; installing Kvantum for 6.9 as a default."
        branches="6.9"
    fi
    for branch in $branches; do
        # --system: with flathub configured as both a system and a user
        # remote, an unqualified install aborts on the ambiguity prompt
        flatpak install -y --system flathub "org.kde.KStyle.Kvantum//$branch" \
            || echo "No Kvantum build for runtime $branch (skipped)"
    done
    mkdir -p "$HOME/.config/Kvantum"
    printf '[General]\ntheme=KvGnomeDark\n' > "$HOME/.config/Kvantum/kvantum.kvconfig"
    flatpak override --user \
        --env=QT_STYLE_OVERRIDE=kvantum \
        --env=QT_QPA_PLATFORMTHEME=gtk3 \
        --env=GTK_THEME=Adwaita:dark \
        --filesystem=xdg-config/Kvantum:ro \
        --nofilesystem=xdg-config/kdeglobals
    echo "Done. Restart Qt Flatpak apps to pick up the dark theme."
    echo "Background: topaz why /usr/share/ublue-os/just/60-custom.just"

# Tailscale tray icon in the panel (StatusNotifier; ships with tailscale)
topaz-tailscale-tray:
    systemctl --user enable --now tailscale-systray.service
    @echo "Tailscale tray enabled (unit: tailscale-systray.service)."

# COSMIC wallpaper follows Bluefin's monthly artwork with day/night flips
topaz-wallpaper:
    systemctl --user enable --now topaz-bluefin-wallpaper.timer
    systemctl --user start topaz-bluefin-wallpaper.service
    @echo "Wallpaper synced; flips at 04:40/17:50, month rollover at 00:05."

# Dropbox via Flatpak with a working tray icon under COSMIC
topaz-dropbox:
    #!/usr/bin/bash
    set -euo pipefail
    flatpak install -y flathub com.dropbox.Client
    systemctl --user enable --now topaz-dropbox.service
    systemctl --user enable --now topaz-dropbox-restart.path
    echo "Dropbox installed and started. Link the account via the app window."
    echo "If the tray icon shows as a broken image, restart the panel once:"
    echo "  pkill cosmic-panel   # cosmic-session respawns it"
    echo "Flatpak updates restart the daemon automatically (the stale binary"
    echo "would otherwise keep running with a dead tray registration)."
    echo "Manual restarts need 'flatpak kill com.dropbox.Client' first (the"
    echo "daemon lives in a Flatpak scope, outside the unit's cgroup)."

# Run Electron Flatpaks Wayland-native (fixes empty image pastes into Discord)
topaz-electron-wayland apps="com.discordapp.Discord":
    #!/usr/bin/bash
    set -euo pipefail
    for app in {{ apps }}; do
        flatpak override --user --env=ELECTRON_OZONE_PLATFORM_HINT=auto "$app"
        echo "$app: ELECTRON_OZONE_PLATFORM_HINT=auto (restart the app to apply)"
    done

# Chrome overrides for automation: WebGPU via Vulkan, read-only Claude Code state
topaz-chrome-integration:
    #!/usr/bin/bash
    set -euo pipefail
    flatpak override --user \
        --filesystem=/tmp \
        --filesystem=~/.claude:ro \
        --filesystem=~/.local/share/claude:ro \
        --env=CHROME_FLAGS="--enable-unsafe-webgpu --use-angle=vulkan --enable-features=Vulkan,VulkanFromANGLE" \
        com.google.Chrome
    echo "Chrome overrides applied (restart Chrome to pick them up)."

# Claude Desktop (Linux beta): rootless install/update into ~/.local
topaz-claude-desktop:
    /usr/bin/topaz-claude-desktop-update

# kitty terminal via the official installer (user-scoped, ~/.local/kitty.app)
topaz-kitty:
    #!/usr/bin/bash
    set -euo pipefail
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
    ln -sf "$HOME/.local/kitty.app/bin/kitty" "$HOME/.local/kitty.app/bin/kitten" \
        "$HOME/.local/bin/"
    cp "$HOME"/.local/kitty.app/share/applications/kitty*.desktop \
        "$HOME/.local/share/applications/"
    sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g; s|Exec=kitty|Exec=$HOME/.local/kitty.app/bin/kitty|g" \
        "$HOME"/.local/share/applications/kitty*.desktop
    echo "kitty installed to ~/.local/kitty.app (re-run to update)."

# Keep the touchpad active while typing (libinput disables it by default)
topaz-touchpad-dwt enabled="false":
    #!/usr/bin/bash
    set -euo pipefail
    case "{{ enabled }}" in true | false) ;; *)
        echo "enabled must be 'true' or 'false'" >&2
        exit 1
        ;;
    esac
    cfg="$HOME/.config/cosmic/com.system76.CosmicComp/v1/input_touchpad"
    mkdir -p "$(dirname "$cfg")"
    [ -f "$cfg" ] || printf '(\n    state: Enabled,\n)\n' > "$cfg"
    if grep -q 'disable_while_typing:' "$cfg"; then
        sed -i "s/disable_while_typing: Some([a-z]*)/disable_while_typing: Some({{ enabled }})/" "$cfg"
    else
        sed -i "0,/^(/s//(\n    disable_while_typing: Some({{ enabled }}),/" "$cfg"
    fi
    echo "disable-while-typing -> {{ enabled }} (cosmic-comp applies it live)"
