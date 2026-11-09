#!/bin/bash
# Installs PiPA: nanobot in its own Python environment, its settings and persona, the bridge
# for Home Assistant's voice, and three user services. Run it as your user, from a clone of
# this repository, on the machine next to Home Assistant (a Raspberry Pi running couchPie, for
# example). Safe to run again.
#
#   cp pipa.conf.example pipa.conf      # then fill it in
#   ./install.sh
#
# Settings come from pipa.conf here, or from the file in PIPA_CONF; the persona from SOUL.md
# here, or from the file in PIPA_SOUL. That's how a private repository can keep its own
# settings and persona on top of this one.
#
# Tokens go in ~/.config/pipa/secrets.env, created on the first run: HA_TOKEN for Home
# Assistant, TELEGRAM_TOKEN and TELEGRAM_ALLOW_FROM for Telegram. Run this again after
# adding them.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CONF="${PIPA_CONF:-$HERE/pipa.conf}"
SOUL="${PIPA_SOUL:-$HERE/SOUL.md}"
NANOBOT_VERSION=0.4.1
VENV="$HOME/.local/share/pipa/venv"
SECRETS="$HOME/.config/pipa/secrets.env"
CONFIG="$HOME/.nanobot/config.json"
WORKSPACE="$HOME/.nanobot/workspace"
UNITS="$HOME/.config/systemd/user"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as the desktop user, not root." >&2
    exit 1
fi
if [ ! -f "$CONF" ]; then
    echo "No settings at $CONF: copy pipa.conf.example to pipa.conf and fill it in." >&2
    exit 1
fi
# shellcheck source=pipa.conf.example
source "$CONF"
LLM_URL="${LLM_URL:?set LLM_URL in $CONF}"
MODEL="${PIPA_MODEL:?set PIPA_MODEL in $CONF}"
HA_URL="${HA_URL:-http://127.0.0.1:8123}"
[ -f "$SOUL" ] || { echo "No persona at $SOUL" >&2; exit 1; }
NOTES=()

echo "== nanobot $NANOBOT_VERSION"
if [ "$("$VENV/bin/nanobot" --version 2>/dev/null | grep -o '[0-9.]*$')" != "$NANOBOT_VERSION" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q "nanobot-ai==$NANOBOT_VERSION"
fi
"$VENV/bin/nanobot" --version

echo "== Secrets ($SECRETS)"
if [ ! -f "$SECRETS" ]; then
    mkdir -p "$(dirname "$SECRETS")"
    install -m 600 /dev/null "$SECRETS"
    cat > "$SECRETS" << EOF
# PiPA's secrets, read by its services. Only you can read this file.
# The key between Home Assistant's bridge and nanobot's API (both on this Pi)
PIPA_API_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
# Home Assistant: your profile > Security > Long-lived access tokens
HA_TOKEN=
# Telegram: the bot's token from @BotFather, and your numeric user ID (from @userinfobot)
TELEGRAM_TOKEN=
TELEGRAM_ALLOW_FROM=
EOF
fi
set -a
# shellcheck source=/dev/null
source "$SECRETS"
set +a
[ -n "${HA_TOKEN:-}" ] || NOTES+=("No HA_TOKEN in $SECRETS yet: PiPA can't see or control the house.")
[ -n "${TELEGRAM_TOKEN:-}" ] || NOTES+=("No TELEGRAM_TOKEN in $SECRETS yet: no Telegram.")

echo "== Settings ($CONFIG)"
[ -f "$CONFIG" ] || "$VENV/bin/nanobot" onboard < /dev/null > /dev/null
"$VENV/bin/python" -I "$HERE/configure.py" "$CONFIG" "$LLM_URL" "$MODEL" "$HA_URL"
# The persona: replaces nanobot's default, and earlier versions of ours while their first
# line is still there; once you delete that line, your edits are left alone
if [ ! -f "$WORKSPACE/SOUL.md" ] || grep -q -e "I am nanobot" -e "install.sh keeps this file" "$WORKSPACE/SOUL.md"; then
    install -m 644 "$SOUL" "$WORKSPACE/SOUL.md"
fi

echo "== Services"
install -D -m 755 "$HERE/pipa-bridge" "$HOME/.local/bin/pipa-bridge"
mkdir -p "$UNITS"
for unit in pipa-api pipa-gateway pipa-bridge; do
    install -m 644 "$HERE/systemd/$unit.service" "$UNITS/$unit.service"
done
# User services; lingering starts them at boot, whether or not the desktop logs in
sudo loginctl enable-linger "$USER"
systemctl --user daemon-reload
for unit in pipa-api pipa-gateway pipa-bridge; do
    systemctl --user enable "$unit" > /dev/null 2>&1
    systemctl --user restart "$unit"
done
sleep 5
systemctl --user --no-pager --plain list-units 'pipa-*' | head -5

echo "== Done"
NOTES+=("In Home Assistant, add the llama.cpp integration at http://127.0.0.1:8901/v1 and make it the voice assistant's conversation agent (see README.md).")
printf '* %s\n' "${NOTES[@]}"
