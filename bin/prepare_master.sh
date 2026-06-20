#!/bin/bash
#
# prepare_master.sh — "sysprep" a Herlofsen IT Service signage master Pi
# before cloning its SD card into a reusable master .img.
#
# WHY THIS EXISTS
# ---------------
# A raw clone of a working card copies *every* unique secret on it, so
# every device made from the clone would share the same SSH host keys,
# the same systemd machine-id and the same Django secret key. That is a
# security hole (one stolen key unlocks the whole fleet) and causes
# network/systemd collisions. This script clears those per-device
# secrets so each clone regenerates its own on first boot, and (option-
# ally) wipes test content so customers get a blank slate.
#
# RUN THIS:
#   * ON THE MASTER PI ITSELF (over SSH/console), as the normal install
#     user (the one that owns ~/anthias). NOT on your Windows PC.
#   * As the LAST step, right before you shut down and pull the card.
#   * After you have already verified the logo + the update-bug fix work.
#
# It does NOT touch: Wi-Fi credentials (so a headless device still joins
# the network) or the Anthias admin login (so all your devices keep the
# same operator password). Adjust below if you want those cleared too.
#
# Re-running it is harmless. Read it before you run it — it deletes
# system identity files on purpose.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal install user (it uses sudo where needed), not as root." >&2
    exit 1
fi

ANTHIAS_DIR="${HOME}/anthias"
ANTHIAS_CONF="${HOME}/.anthias/anthias.conf"
ANTHIAS_DB="${HOME}/.anthias/anthias.db"
ASSETS_DIR="${HOME}/anthias_assets"
COMPOSE_FILE="${ANTHIAS_DIR}/docker-compose.yml"

WIPE_CONTENT=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --wipe-content) WIPE_CONTENT=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help)
            cat <<'USAGE'
Usage: bash bin/prepare_master.sh [--wipe-content] [--yes]

  --wipe-content   Also delete all uploaded assets and reset the Anthias
                   database so the clone ships with an empty playlist.
                   Omit it to keep the playlist you built on the master.
  --yes, -y        Skip the confirmation prompt.
USAGE
            exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
    esac
done

echo "This will clear this device's unique identity (SSH host keys,"
echo "machine-id, Django secret key) so clones regenerate their own."
if [ "$WIPE_CONTENT" -eq 1 ]; then
    echo "It will ALSO delete all assets and reset the Anthias database."
fi
echo "Run this only on the MASTER Pi, right before cloning its card."
if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Continue? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

# 1. Stop the stack so files (DB, conf) are at rest while we edit them.
if [ -f "$COMPOSE_FILE" ]; then
    echo "==> Stopping Anthias containers..."
    sudo docker compose -f "$COMPOSE_FILE" down || \
        echo "    (compose down failed — continuing anyway)"
fi

# 2. systemd machine-id. Emptying /etc/machine-id is the documented way
#    to ask systemd to generate a fresh one on the next boot; the dbus
#    copy is removed so it is recreated from it.
echo "==> Resetting machine-id (regenerates on next boot)..."
sudo truncate -s 0 /etc/machine-id || true
sudo rm -f /var/lib/dbus/machine-id || true

# 3. SSH host keys. Delete them and install a one-shot service that
#    regenerates a fresh set on first boot, then disables itself, so no
#    two clones share a host key.
echo "==> Removing SSH host keys and arming first-boot regeneration..."
sudo rm -f /etc/ssh/ssh_host_* || true
sudo tee /etc/systemd/system/regenerate-ssh-host-keys.service >/dev/null <<'UNIT'
[Unit]
Description=Regenerate SSH host keys on first boot (Herlofsen master)
Before=ssh.service
ConditionFileIsExecutable=/usr/bin/ssh-keygen
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
ExecStartPost=/bin/systemctl disable regenerate-ssh-host-keys.service
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl enable regenerate-ssh-host-keys.service || true

# 4. Django secret key. Blanking it in anthias.conf makes Anthias mint a
#    new one on first start (see settings.py: empty key -> token_urlsafe).
if [ -f "$ANTHIAS_CONF" ]; then
    echo "==> Clearing django_secret_key in anthias.conf (regenerates on boot)..."
    sed -i 's/^django_secret_key[[:space:]]*=.*/django_secret_key = /' \
        "$ANTHIAS_CONF" || true
fi

# 5. Optional clean slate: drop uploaded assets and the playlist DB. The
#    DB is recreated by `manage migrate` in bin/start_server.sh on boot.
if [ "$WIPE_CONTENT" -eq 1 ]; then
    echo "==> Wiping assets and resetting the Anthias database..."
    rm -rf "${ASSETS_DIR:?}/"* 2>/dev/null || true
    rm -f "$ANTHIAS_DB" "${ANTHIAS_DB}-wal" "${ANTHIAS_DB}-shm" 2>/dev/null || true
fi

# 6. Trim logs / shell history so the clone is tidy and smaller.
echo "==> Clearing logs and history..."
sudo journalctl --rotate >/dev/null 2>&1 || true
sudo journalctl --vacuum-time=1s >/dev/null 2>&1 || true
rm -f "${HOME}/.bash_history" 2>/dev/null || true
sudo sync

cat <<'DONE'

Done. This Pi is now a clonable master.

Next:
  1. Shut it down cleanly:   sudo shutdown -h now
  2. Move the SD card to your PC and read it with Win32 Disk Imager into
     e.g. Herlofsen-Smartskilt-v1.img
  3. Do NOT boot this same master again before imaging — booting would
     regenerate the very secrets you just cleared. (You can boot it after
     imaging; just re-run this script before your next capture.)
DONE
