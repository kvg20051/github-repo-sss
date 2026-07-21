#!/usr/bin/env bash
#
# setup-system.sh
# Ubuntu 26 host setup:
#   1) Mask sleep/suspend/hibernate targets
#   2) Add WireGuard hub hosts to /etc/hosts
#   3) Set wifi.powersave = 2 in NetworkManager conf.d
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
# 2) Add hosts entries to /etc/hosts (idempotent)
# -----------------------------------------------------------------------------
echo "==> Updating /etc/hosts..."

HOSTS_FILE="/etc/hosts"
MARKER_BEGIN="# BEGIN wg4-hosts (managed by setup-system.sh)"
MARKER_END="# END wg4-hosts (managed by setup-system.sh)"

HOSTS_BLOCK=$(cat <<'EOF'
10.124.124.2    gen10               # wg4   ProLiant MicroServer Gen10 - wg4 wireguard vpn hub. Net - 10.123.123.0/24
10.124.124.1    gen20               # wg4   ProLiant MicroServer Gen20
10.124.124.16   gen30               # wg4   ProLiant MicroServer Gen30
10.124.124.11   ficus               # wg4   FICUS
10.124.124.19   gen40               # wg4   gen40
EOF
)

if grep -qF "$MARKER_BEGIN" "$HOSTS_FILE" 2>/dev/null; then
    # Remove the old managed block entirely (markers inclusive), then re-append fresh below
    sed -i "/^${MARKER_BEGIN//\//\\/}$/,/^${MARKER_END//\//\\/}$/d" "$HOSTS_FILE"
    echo "    Removed previous managed block (will re-add below)."
fi

# Strip any trailing blank lines left over from previous edits, then append cleanly
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HOSTS_FILE"

{
    echo ""
    echo "$MARKER_BEGIN"
    echo "$HOSTS_BLOCK"
    echo "$MARKER_END"
} >> "$HOSTS_FILE"
echo "    Managed block written."

# -----------------------------------------------------------------------------
# 3) Set wifi.powersave = 2 in NetworkManager conf.d
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
# 4) Install monitrc into /etc/monit/
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
