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
        flatpak install -y flathub "org.kde.KStyle.Kvantum//$branch" \
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
    echo "Dropbox installed and started. Link the account via the app window."
    echo "If the tray icon shows as a broken image, restart the panel once:"
    echo "  pkill cosmic-panel   # cosmic-session respawns it"
    echo "Note: 'systemctl restart' does not restart a running daemon (it"
    echo "lives in a Flatpak scope); use 'flatpak kill com.dropbox.Client'."

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
