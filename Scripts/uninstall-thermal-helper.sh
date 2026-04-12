#!/bin/zsh
set -euo pipefail

PLIST_PATH="/Library/LaunchDaemons/com.alfred.fluxbar.thermal.plist"
INSTALL_SCRIPT="/usr/local/libexec/fluxbar-thermal-sampler.sh"

/bin/launchctl bootout system "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST_PATH"
/bin/rm -f "$INSTALL_SCRIPT"
/bin/rm -f /Users/Shared/FluxBar/thermal-cache.json

/bin/echo "FluxBar thermal helper removed."
