#!/bin/bash
# Installs PiPA: nanobot in its own Python environment, its settings and persona, the bridge
# for Home Assistant's voice, the model-call log, and four user services. Run it as your user, from a clone of
# this repository, on the machine next to Home Assistant (a Raspberry Pi running couchPie, for
# example). Safe to run again.
#
#   cp pipa.conf.example pipa.conf      # then fill it in
#   ./install.sh
#
# Settings come from pipa.conf here, or from the file in PIPA_CONF; the persona from SOUL.md
# here, or from the file in PIPA_SOUL; a first USER.md (who you are) from the file in
# PIPA_USER, if any. That's how a private repository can keep its own settings and persona
# on top of this one.
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
export PIPA_CONTEXT="${PIPA_CONTEXT:-16384}"
# Voice notes: a Wyoming speech-to-text server (Whisper on a PC, for example); empty = off
STT_URL="${STT_URL:-}"
export PIPA_STT="${STT_URL:+1}"
# nanobot reaches the LLM through pipa-llm-log, which records each call for its page;
# PIPA_LLM_LOG=0 in the settings connects it straight to the server instead
if [ "${PIPA_LLM_LOG:-1}" != 0 ]; then NANOBOT_LLM=http://127.0.0.1:8902/v1; else NANOBOT_LLM=$LLM_URL; fi
[ -f "$SOUL" ] || { echo "No persona at $SOUL" >&2; exit 1; }
NOTES=()

echo "== nanobot $NANOBOT_VERSION"
if [ "$("$VENV/bin/nanobot" --version 2>/dev/null | grep -o '[0-9.]*$')" != "$NANOBOT_VERSION" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q "nanobot-ai==$NANOBOT_VERSION"
fi
"$VENV/bin/nanobot" --version
# PiPA's nanobot plugins: the time on every turn (nanobot doesn't give it), Google
# Calendar (its tools load only once its authorization is in the secrets), the link
# catalog, and the TV remote (its tools load only where couchPie's kiosk is installed)
for plugin in pipa_clock pipa_calendar pipa_links pipa_tv; do
    "$VENV/bin/pip" install -q --no-deps --force-reinstall "$HERE/$plugin"
done
# pipa-stt talks Wyoming to the speech-to-text server
"$VENV/bin/pip" install -q wyoming

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
# Google Calendar: the three lines pipa-google-auth writes (see README.md)
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REFRESH_TOKEN=
EOF
fi
set -a
# shellcheck source=/dev/null
source "$SECRETS"
set +a
[ -n "${HA_TOKEN:-}" ] || NOTES+=("No HA_TOKEN in $SECRETS yet: PiPA can't see or control the house.")
[ -n "${TELEGRAM_TOKEN:-}" ] || NOTES+=("No TELEGRAM_TOKEN in $SECRETS yet: no Telegram.")
[ -n "${GOOGLE_REFRESH_TOKEN:-}" ] || NOTES+=("No Google Calendar yet (optional): see README.md, Google Calendar.")

echo "== Settings ($CONFIG)"
[ -f "$CONFIG" ] || "$VENV/bin/nanobot" onboard < /dev/null > /dev/null
"$VENV/bin/python" -I "$HERE/configure.py" "$CONFIG" "$NANOBOT_LLM" "$MODEL" "$HA_URL"
# The persona: replaces nanobot's default, and earlier versions of ours while their first
# line is still there; once you delete that line, your edits are left alone
if [ ! -f "$WORKSPACE/SOUL.md" ] || grep -q -e "I am nanobot" -e "install.sh keeps this file" "$WORKSPACE/SOUL.md"; then
    install -m 644 "$SOUL" "$WORKSPACE/SOUL.md"
fi
# Who the person is: PIPA_USER is a starting USER.md, copied only over nanobot's blank
# template, since PiPA keeps adding to this file as it learns
if [ -n "${PIPA_USER:-}" ] && { [ ! -f "$WORKSPACE/USER.md" ] || grep -q "(your name)" "$WORKSPACE/USER.md"; }; then
    install -m 644 "$PIPA_USER" "$WORKSPACE/USER.md"
fi

echo "== Services"
install -D -m 755 "$HERE/pipa-bridge" "$HOME/.local/bin/pipa-bridge"
install -D -m 755 "$HERE/pipa-llm-log" "$HOME/.local/bin/pipa-llm-log"
install -D -m 755 "$HERE/pipa-google-auth" "$HOME/.local/bin/pipa-google-auth"
install -D -m 755 "$HERE/pipa-stt" "$HOME/.local/bin/pipa-stt"
printf "PIPA_LLM_UPSTREAM=%s\n" "$LLM_URL" > "$HOME/.config/pipa/llm-log.env"
printf "PIPA_STT_WYOMING=%s\n" "$STT_URL" > "$HOME/.config/pipa/stt.env"
UNIT_LIST="pipa-llm-log pipa-api pipa-gateway pipa-bridge"
if [ -n "$STT_URL" ]; then
    UNIT_LIST="pipa-stt $UNIT_LIST"
else
    systemctl --user disable --now pipa-stt > /dev/null 2>&1 || true
    NOTES+=("No STT_URL in $CONF: voice notes aren't transcribed.")
fi
mkdir -p "$UNITS"
for unit in pipa-llm-log pipa-api pipa-gateway pipa-bridge pipa-stt; do
    install -m 644 "$HERE/systemd/$unit.service" "$UNITS/$unit.service"
done
# User services; lingering starts them at boot, whether or not the desktop logs in
sudo loginctl enable-linger "$USER"
systemctl --user daemon-reload
for unit in $UNIT_LIST; do
    systemctl --user enable "$unit" > /dev/null 2>&1
    systemctl --user restart "$unit"
done
sleep 5
systemctl --user --no-pager --plain list-units 'pipa-*' | head -7
# The page of model calls, for your tailnet only (not Funnel), with the Pi's HTTPS certificate
if command -v tailscale > /dev/null && sudo tailscale serve --bg --https=8444 http://127.0.0.1:8903 > /dev/null; then
    host=$(tailscale status --json | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
    NOTES+=("Model calls, for checking what PiPA did: https://$host:8444/")
else
    NOTES+=("Model calls: http://127.0.0.1:8903/ on this Pi (not on the tailnet: set up Tailscale with HTTPS).")
fi

echo "== Done"
NOTES+=("In Home Assistant, add the llama.cpp integration at http://127.0.0.1:8901/v1 and make it the voice assistant's conversation agent (see README.md).")
printf '* %s\n' "${NOTES[@]}"
