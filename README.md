# Omarchy Control

Mission Control for Omarchy. See your windows, find the one you want, and bring it to the front.

- **See more.** Large live previews fit around each other instead of sitting in a rigid grid.
- **Stay sharp.** Your wallpaper, windows that fly from their real positions into the overview and settle back on close, and quick eased transitions—without a blur pass or heavy frames.
- **Keep your bearings.** Windows keep their proportions, and desktop previews show what lives where.
- **Tidy up by dragging.** Drop a window onto another desktop without switching away from your current one.
- **Stay in your flow.** Click to focus and raise a window, use the keyboard to navigate, or hit Escape to leave everything as it was.
- **Feel at home.** Uses your Omarchy theme and runs as a native Quickshell overlay—not a replacement shell.

One shortcut. All your windows. Less hunting.

Built for Hyprland with Quickshell.

## Install

Needs Omarchy (Hyprland + Quickshell).

```sh
curl -fsSL https://raw.githubusercontent.com/satellitedown/omarchycontrol/main/install.sh | bash
```

Or clone the repo and run `./install.sh`. Same thing if you point an agent at this README: run that script.

It clones to `~/.local/share/omarchycontrol` (or uses the checkout you ran it from), adds autostart + **Ctrl+↑**, and starts it. **Ctrl+← / Ctrl+→** switch desktops if those lines are not already there.
