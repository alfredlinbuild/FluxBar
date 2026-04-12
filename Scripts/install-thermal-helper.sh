#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SCRIPT="/usr/local/libexec/fluxbar-thermal-sampler.sh"
PLIST_PATH="/Library/LaunchDaemons/com.alfred.fluxbar.thermal.plist"

/bin/mkdir -p /usr/local/libexec /Users/Shared/FluxBar
/bin/cp "$ROOT_DIR/fluxbar-thermal-sampler.sh" "$INSTALL_SCRIPT"
/usr/sbin/chown root:wheel "$INSTALL_SCRIPT"
/bin/chmod 755 "$INSTALL_SCRIPT"

/bin/cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.alfred.fluxbar.thermal</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>15</integer>
    <key>StandardOutPath</key>
    <string>/tmp/com.alfred.fluxbar.thermal.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.alfred.fluxbar.thermal.err</string>
</dict>
</plist>
EOF

/usr/sbin/chown root:wheel "$PLIST_PATH"
/bin/chmod 644 "$PLIST_PATH"

/bin/launchctl bootout system "$PLIST_PATH" >/dev/null 2>&1 || true
/bin/launchctl bootstrap system "$PLIST_PATH"
/bin/launchctl kickstart -k system/com.alfred.fluxbar.thermal

/bin/echo "FluxBar thermal helper installed."
