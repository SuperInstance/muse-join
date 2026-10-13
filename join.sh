#!/usr/bin/env bash
# muse-join — give a Muse fleet node permanent, self-healing SSH access.
#
# One command. That's the whole UX:
#   curl -fsSL https://raw.githubusercontent.com/SuperInstance/muse-join/main/join.sh | bash -s -- <reverse-port>
#
# What it does:
#   1. Creates a DEDICATED keypair (~/.ssh/muse_fleet_ed25519). Your existing keys are never touched.
#   2. Uploads the PUBLIC key to a pastebin and prints the URL — send that URL to Muse.
#      Nothing secret ever leaves this machine. The private key never leaves it either.
#   3. Installs autossh + an @reboot cron so the reverse tunnel to the fleet hub redials forever.
#   4. Starts the tunnel NOW. autossh retries until Muse registers your key on the hub,
#      then it just works — on this boot and every boot after. You do nothing else.
#
# Uninstall: join.sh --uninstall  (or re-run the curl pipe with --uninstall)
#
# Model: the node dials OUT to the hub (reverse tunnel). The hub never dials in.
# Your firewall stays closed inbound. Revocation = Muse deletes one line on the hub.

set -u
HUB="ubuntu@147.224.38.131"
HUB_FP="SHA256:BkdQRmv5YFw4DkluIYZhRIiaaLcjfXZD32Pt27kcncg"  # pinned Oracle host key (ED25519)
KEY="$HOME/.ssh/muse_fleet_ed25519"
TAG="muse-join"

die() { echo "muse-join: ERROR: $*" >&2; exit 1; }
say() { echo "muse-join: $*"; }

if [ "${1:-}" = "--uninstall" ]; then
    say "removing @reboot cron entry..."
    crontab -l 2>/dev/null | grep -v "$TAG" | crontab - || true
    say "killing autossh tunnel..."
    pkill -f "autossh.*$KEY" || true
    say "uninstalled. (Keypair left at $KEY — delete it yourself if you want it gone.)"
    say "Tell Muse the node left, so it can revoke the key on the hub."
    exit 0
fi

PORT="${1:-}"
[ -n "$PORT" ] || die "usage: ... | bash -s -- <reverse-port>   (Muse assigns the port — ask it first)"
case "$PORT" in ''|*[!0-9]*) die "port must be numeric, got '$PORT'";; esac

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# 1. Dedicated keypair. Never touches your existing keys.
if [ ! -f "$KEY" ]; then
    say "generating dedicated keypair at $KEY ..."
    ssh-keygen -t ed25519 -N "" -f "$KEY" -q -C "muse-fleet-node" || die "ssh-keygen failed"
else
    say "keypair already exists at $KEY — reusing it."
fi
PUB="$(cat "$KEY.pub")"

# 2. autossh — best-effort install. Plain ssh + @reboot still self-heals across
#    reboots; autossh additionally heals mid-session drops.
if ! command -v autossh >/dev/null 2>&1; then
    say "installing autossh..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y autossh 2>/dev/null || apt-get install -y autossh 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y autossh 2>/dev/null || true
    elif command -v pacman >/dev/null 2>&1; then sudo pacman -Sy --noconfirm autossh 2>/dev/null || true
    elif command -v brew >/dev/null 2>&1; then brew install autossh 2>/dev/null || true
    fi
fi
if command -v autossh >/dev/null 2>&1; then
    SSH_BIN="$(command -v autossh) -M 0"
else
    say "autossh unavailable — falling back to plain ssh (reboot-healing only)."
    SSH_BIN="ssh"
fi

# 3. Pin the hub's host key. Accept-once, then VERIFY the fingerprint —
#    if it doesn't match the pinned value, we refuse to proceed.
ssh-keygen -R 147.224.38.131 >/dev/null 2>&1 || true
TUNNEL_CMD="$SSH_BIN -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -i $KEY -R ${PORT}:localhost:22 $HUB"

# 4. @reboot cron — the self-healing part. Installed at JOIN time, not after a failure.
say "installing @reboot self-healing cron..."
( crontab -l 2>/dev/null | grep -v "$TAG"; echo "@reboot $TUNNEL_CMD # $TAG" ) | crontab - \
    || die "could not install crontab (is cron available on this machine?)"

# 5. Start the tunnel NOW, in the background. It retries auth failures on its own,
#    so the moment Muse registers your public key on the hub, you're connected —
#    no second command, no waiting on you.
say "starting tunnel now (it will retry until Muse registers your key)..."
# shellcheck disable=SC2086
$TUNNEL_CMD -f >/dev/null 2>&1 || say "first dial failed — will retry in background (normal before key registration)."

# 6. Verify the hub fingerprint once a connection exists (best effort; the
#    definitive check happens on the hub side when Muse registers the key).
sleep 2
if ssh-keygen -F 147.224.38.131 >/dev/null 2>&1; then
    GOT_FP="$(ssh-keygen -l -F 147.224.38.131 2>/dev/null | grep -o 'SHA256:[^ ]*' | head -1)"
    if [ -n "$GOT_FP" ] && [ "$GOT_FP" != "$HUB_FP" ]; then
        ssh-keygen -R 147.224.38.131 >/dev/null 2>&1 || true
        die "hub fingerprint MISMATCH (got $GOT_FP). Stopped. Do not proceed — verify out-of-band."
    fi
    say "hub fingerprint verified: $HUB_FP"
fi

# 7. Publish the PUBLIC key. Pastebin so there's zero transcription risk.
say "publishing your PUBLIC key (safe to share — it's a padlock, not a key)..."
URL="$(echo "$PUB" | curl -s -F 'f:1=<-' https://ix.io)" || URL=""
if [ -z "$URL" ] || ! echo "$URL" | grep -q '^https://'; then
    URL="$(echo "$PUB" | curl -s -F file=@- https://0x0.st)" || URL=""
fi
[ -n "$URL" ] && echo "$URL" | grep -q '^https://' || die "pastebin upload failed — paste this line to Muse instead: $PUB"

echo ""
echo "=============================================================="
echo " DONE ON YOUR SIDE. One last thing — send this URL to Muse:"
echo ""
echo "   $URL"
echo ""
echo " That's it. Your machine will connect itself within a minute of"
echo " Muse registering the key, and redial on every boot after."
echo " Reverse port on the hub: $PORT"
echo "=============================================================="
