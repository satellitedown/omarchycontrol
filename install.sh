#!/usr/bin/env bash
# Install Omarchy Control: clone, bind Ctrl+Up, autostart, start now.
set -euo pipefail

REPO="${OMARCHYCONTROL_REPO:-https://github.com/satellitedown/omarchycontrol.git}"
DEST="${OMARCHYCONTROL_DIR:-$HOME/.local/share/omarchycontrol}"
AUTOSTART="$HOME/.config/hypr/autostart.lua"
BINDINGS="$HOME/.config/hypr/bindings.lua"

need() { command -v "$1" >/dev/null || { echo "missing $1" >&2; exit 1; }; }
need git
need quickshell

here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
if [[ -n "$here" && -f "$here/shell.qml" ]]; then
  DEST=$here
else
  if [[ -d "$DEST/.git" ]]; then
    git -C "$DEST" pull --ff-only
  else
    git clone --depth 1 "$REPO" "$DEST"
  fi
fi
[[ -f "$DEST/shell.qml" ]] || { echo "no shell.qml in $DEST" >&2; exit 1; }

lua_string() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

append_once() {
  local file=$1 needle=$2 line=$3
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -Fq "$needle" "$file"; then
    return
  fi
  printf '\n%s\n' "$line" >>"$file"
}

launch="quickshell -n -p $DEST"
ipc="quickshell ipc -p $DEST call -- missioncontrol toggle"
append_once "$AUTOSTART" "quickshell -n -p $DEST" \
  "o.launch_on_start($(lua_string "$launch"))"
append_once "$BINDINGS" "missioncontrol toggle" \
  "o.bind(\"CTRL + UP\", \"Mission control\", $(lua_string "$ipc"))"
append_once "$BINDINGS" 'workspace = "e-1"' \
  'o.bind("CTRL + LEFT", "Previous desktop", hl.dsp.focus({ workspace = "e-1" }))'
append_once "$BINDINGS" 'workspace = "e+1"' \
  'o.bind("CTRL + RIGHT", "Next desktop", hl.dsp.focus({ workspace = "e+1" }))'

if command -v hyprctl >/dev/null; then
  hyprctl reload >/dev/null || true
  if ! quickshell ipc -p "$DEST" call -- missioncontrol ping >/dev/null 2>&1; then
    # -n is one instance; a reload does not run launch_on_start.
    nohup quickshell -n -p "$DEST" >/dev/null 2>&1 &
  fi
fi

echo "Installed $DEST"
echo "Toggle with Ctrl+Up. Ctrl+Left / Ctrl+Right switch desktops."
