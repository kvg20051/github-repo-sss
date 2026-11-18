#!/usr/bin/env bash
#
# setup-system.sh
# Ubuntu 26 host setup:
#   1) Mask sleep/suspend/hibernate targets
#   2) Set wifi.powersave = 2 in NetworkManager conf.d
#
# Idempotent: safe to re-run without duplicating entries.
# Must be run as root (or with sudo).

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# 1) Mask sleep/suspend/hibernate targets
# -----------------------------------------------------------------------------
echo "==> Masking sleep/suspend/hibernate targets..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# -----------------------------------------------------------------------------
# 2) Set wifi.powersave = 2 in NetworkManager conf.d
# -----------------------------------------------------------------------------
echo "==> Configuring NetworkManager wifi powersave..."

NM_CONF_DIR="/etc/NetworkManager/conf.d"
NM_CONF_FILE="${NM_CONF_DIR}/default-wifi-powersave-on.conf"

mkdir -p "$NM_CONF_DIR"

if [[ -f "$NM_CONF_FILE" ]] && grep -qE '^\s*wifi\.powersave\s*=' "$NM_CONF_FILE"; then
    # Update existing setting in place
    sed -i -E 's/^\s*wifi\.powersave\s*=.*/wifi.powersave = 2/' "$NM_CONF_FILE"
    echo "    Updated existing wifi.powersave setting in $NM_CONF_FILE."
elif [[ -f "$NM_CONF_FILE" ]]; then
    # File exists but has no wifi.powersave key under [connection]; ensure section + key present
    if grep -qE '^\[connection\]' "$NM_CONF_FILE"; then
        sed -i '/^\[connection\]/a wifi.powersave = 2' "$NM_CONF_FILE"
    else
        {
            echo ""
            echo "[connection]"
            echo "wifi.powersave = 2"
        } >> "$NM_CONF_FILE"
    fi
    echo "    Added wifi.powersave setting to existing $NM_CONF_FILE."
else
    cat > "$NM_CONF_FILE" <<'EOF'
[connection]
wifi.powersave = 2
EOF
    echo "    Created $NM_CONF_FILE."
fi

echo "==> Done. Note: NetworkManager was not restarted; the powersave setting"
echo "    will take effect on next NetworkManager restart or reboot."

# -----------------------------------------------------------------------------
# 3) Install monitrc into /etc/monit/
# -----------------------------------------------------------------------------
echo "==> Installing monitrc..."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SRC_MONITRC="${SCRIPT_DIR}/monitrc"
DEST_MONITRC="/etc/monit/monitrc"

if [[ -f "$SRC_MONITRC" ]]; then
    mkdir -p /etc/monit
    install -m 600 -o root -g root "$SRC_MONITRC" "$DEST_MONITRC"
    echo "    Installed ${SRC_MONITRC} -> ${DEST_MONITRC}"

    echo "==> Restarting monit service..."
    systemctl restart monit
    echo "    monit restarted."
else
    echo "    WARNING: ${SRC_MONITRC} not found next to this script — skipping monitrc install." >&2
fi
