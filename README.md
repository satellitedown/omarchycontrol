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

Needs Omarchy (Hyprland + Quickshell). Clone this repo, then point two user config lines at it. Replace the path if you cloned somewhere else.

```lua
-- ~/.config/hypr/autostart.lua
o.launch_on_start("quickshell -n -p /home/YOU/Projects/omarchycontrol")

-- ~/.config/hypr/bindings.lua
o.bind("CTRL + UP", "Mission control", "quickshell ipc -p /home/YOU/Projects/omarchycontrol call -- missioncontrol toggle")
```

Start it for this session:

```sh
quickshell -n -p /home/YOU/Projects/omarchycontrol
```

Press **Ctrl+↑** to toggle. Optional, same as macOS Spaces:

```lua
o.bind("CTRL + LEFT", "Previous desktop", hl.dsp.focus({ workspace = "e-1" }))
o.bind("CTRL + RIGHT", "Next desktop", hl.dsp.focus({ workspace = "e+1" }))
```
