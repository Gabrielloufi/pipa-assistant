#!/usr/bin/python3 -I
"""Merges PiPA's settings into nanobot's config.json (~/.nanobot/config.json), keeping
everything else nanobot or its WebUI wrote there. Run by install.sh, with the secrets file's
variables in the environment.

Secrets stay out of config.json: it holds ${VAR} references, and systemd loads the values
from ~/.config/pipa/secrets.env. nanobot refuses to start when a referenced variable is
unset, so Home Assistant and Telegram are only added once their tokens are in that file.

  configure.py CONFIG_JSON LLM_URL MODEL [HA_URL]
"""

import json
import os
import socket
import sys
from pathlib import Path
from urllib.parse import urlparse

config_path, llm_url, model = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
ha_url = (sys.argv[4] if len(sys.argv) > 4 else "http://127.0.0.1:8123").rstrip("/")
# nanobot blocks private addresses for MCP unless whitelisted: Home Assistant's own
ha_ip = socket.gethostbyname(urlparse(ha_url).hostname)

SETTINGS = {
    "agents": {"defaults": {
        "modelPreset": "casa",
        "botName": "PiPA",
        "botIcon": "🥧",
        # Most replies are spoken: short ones, and few tool rounds before answering
        "maxTokens": 1024,
        "maxToolIterations": 12,
    }},
    # An OpenAI-compatible server (llama.cpp's llama-server, for example), no key
    "providers": {"custom": {"apiBase": llm_url, "apiKey": "local"}},
    "modelPresets": {"casa": {
        "provider": "custom",
        "model": model,
        "contextWindowTokens": 32768,
        "maxTokens": 1024,
        "temperature": 0.3,
        # No thinking out loud before answering: it only adds seconds to every reply
        "extraBody": {"chat_template_kwargs": {"enable_thinking": False}},
    }},
    # The API that pipa-bridge (Home Assistant's voice) talks to: this Pi only
    "api": {"host": "127.0.0.1", "port": 8900, "timeout": 300.0, "apiKey": "${PIPA_API_KEY}"},
    "tools": {
        # Reachable from Telegram: no shell, and files only inside its workspace
        "exec": {"enable": False},
        "restrictToWorkspace": True,
        # nanobot blocks private addresses for MCP; Home Assistant's is allowed
        "ssrfWhitelist": [f"{ha_ip}/32"],
    },
}

HOME_ASSISTANT = {"tools": {"mcpServers": {"homeassistant": {
    "type": "streamableHttp",
    "url": f"{ha_url}/api/mcp",
    "headers": {"Authorization": "Bearer ${HA_TOKEN}"},
    "toolTimeout": 60,
}}}}


def telegram(allow_from):
    return {"channels": {"telegram": {
        "enabled": True,
        "token": "${TELEGRAM_TOKEN}",
        # Only these Telegram user IDs; empty means new users must be approved by pairing
        "allowFrom": [u.strip() for u in allow_from.split(",") if u.strip()],
    }}}


def merge(base, extra):
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
    return base


config = json.loads(config_path.read_text())
merge(config, SETTINGS)
if os.environ.get("HA_TOKEN"):
    merge(config, HOME_ASSISTANT)
else:
    config.get("tools", {}).get("mcpServers", {}).pop("homeassistant", None)
if os.environ.get("TELEGRAM_TOKEN"):
    merge(config, telegram(os.environ.get("TELEGRAM_ALLOW_FROM", "")))
else:
    config.get("channels", {}).get("telegram", {})["enabled"] = False

backup = config_path.with_suffix(".json.before-pipa")
if not backup.exists():
    backup.write_text(config_path.read_text())
config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
print("nanobot config:", "Home Assistant" if os.environ.get("HA_TOKEN") else "no Home Assistant yet",
      "|", "Telegram" if os.environ.get("TELEGRAM_TOKEN") else "no Telegram yet")
