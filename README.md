# PiPA

The Pi Personal Assistant: one assistant behind Home Assistant's voice and Telegram, running
entirely on your own machines. Simple home commands stay with Home Assistant; everything else
goes to PiPA, an agent ([nanobot](https://github.com/HKUDS/nanobot)) that remembers, sets
reminders, answers questions and, with a token, controls the house through Home Assistant.
Its language model is a server on your network, so nothing leaves the house.

It was built for [couchPie](https://github.com/Gabrielloufi/couchpie), a Raspberry Pi TV box
that also runs Home Assistant, but it only needs:

- a Linux machine next to Home Assistant, with Python 3.11 or newer and systemd (a Raspberry Pi
  5 is enough: the language model runs elsewhere);
- an OpenAI-compatible language model server, such as llama.cpp's `llama-server` on a PC with a
  GPU, with a model that handles tool calls (tested with Gemma 4 12B);
- optionally, Home Assistant 2026.8 or newer, and a Telegram bot.

```
phone / satellite ─> Home Assistant's assistant: speech to text ─> conversation ─> text to speech
                       conversation: a known home command ─> Home Assistant itself, no LLM
                                     anything else ─> pipa-bridge (:8901)
                                                        ─> nanobot API (:8900) ─> the LLM server
                                                                             └─> Home Assistant MCP
Telegram ─> nanobot gateway ─┘
```

| File | Installed to | Purpose |
|---|---|---|
| `install.sh` | run it | Installs or updates everything below. Safe to run again. |
| `pipa.conf.example` | copy to `pipa.conf` | The LLM server, the model, and Home Assistant's address. |
| `configure.py` | run by `install.sh` | Merges PiPA's settings into nanobot's `~/.nanobot/config.json`. |
| `SOUL.md` | `~/.nanobot/workspace/SOUL.md` | The persona: Brazilian Portuguese, short spoken answers, how to use its tools. |
| `pipa-bridge` | `~/.local/bin/pipa-bridge` | Home Assistant's OpenAI-style requests to nanobot's API, and back. |
| `systemd/pipa-*.service` | `~/.config/systemd/user/` | nanobot's API, nanobot's gateway, and the bridge, as user services. |
| | `~/.local/share/pipa/venv` | nanobot 0.4.1. |
| | `~/.config/pipa/secrets.env` | Tokens, readable only by you. Created by the first run. |

## Install

On the machine next to Home Assistant:

```bash
git clone https://github.com/Gabrielloufi/pipa-assistant.git
cd pipa-assistant
cp pipa.conf.example pipa.conf      # the LLM server's address and the model's name
./install.sh
```

It installs nanobot in its own environment, points it at your model, installs the persona,
and starts the three services. Without tokens, PiPA already answers questions and remembers
conversations.

### Your own settings and persona

`install.sh` reads its settings from the file in `PIPA_CONF` and the persona from the file in
`PIPA_SOUL` when they're set. To keep your own in a private repository, put a `pipa.conf` and
a `SOUL.md` there, with a small script that runs this repository's installer:

```bash
PIPA_CONF="$HERE/pipa.conf" PIPA_SOUL="$HERE/SOUL.md" exec ../pipa-assistant/install.sh
```

The installed persona is replaced on every run while its first line (the comment) is there.
Delete that line in `~/.nanobot/workspace/SOUL.md` to keep edits made there.

### Home control and Telegram

Put the tokens in `~/.config/pipa/secrets.env` (`nano ~/.config/pipa/secrets.env`), then run
`./install.sh` again:

- `HA_TOKEN`: in Home Assistant, your profile → Security → **Long-lived access tokens** →
  Create. Also add the **Model Context Protocol Server** integration (Settings → Devices &
  services → Add integration), with Assist (device control). PiPA then sees and controls the
  devices you expose to voice assistants.
- `TELEGRAM_TOKEN` and `TELEGRAM_ALLOW_FROM`: create a bot with @BotFather; your numeric
  Telegram user ID comes from @userinfobot. Only that ID can talk to the bot.

## In Home Assistant

1. Settings → Devices & services → Add integration → **llama.cpp**: URL
   `http://127.0.0.1:8901/v1` (the bridge, on the machine PiPA runs on), no API key. The model
   is `pipa`.
2. In its conversation agent: **Control Home Assistant** off (PiPA controls the house through
   MCP instead), no instructions needed (they're in `SOUL.md`).
3. Settings → Voice assistants → your assistant → **Conversation agent**: the new one, with
   **Prefer handling commands locally** on.

Speech to text and text to speech are Home Assistant's own choice: any Wyoming services (for
example Whisper on a PC with a GPU, and Piper on the Pi as the fallback voice).

## How the bridge works

Home Assistant sends the whole conversation on every turn; nanobot's API takes one user
message and keeps the history itself. The bridge:

- sends only the newest message;
- adds "(por voz; agora é domingo, 8 de novembro de 2026, 19:00)", so PiPA answers briefly
  and knows the date (models otherwise guess one);
- uses Home Assistant's conversation ID as nanobot's session, so follow-ups keep context;
- strips markdown and emojis, which the voice would read aloud;
- answers Home Assistant's setup check itself.

## Speed

Measured on 2026-11-08, with Gemma 4 12B on an RTX 4070 SUPER (12 GB):

| | |
|---|---|
| A follow-up, the model loaded | about 3 s |
| A new conversation | a few seconds more: nanobot's first prompt is about 5,000–6,000 tokens, but the server reuses its cached start |
| The model not loaded | +8 s to load it |

**Give the model its VRAM.** With the model plus Whisper plus F5-TTS on the same 12 GB card, a
32k-token context with the vision module didn't fit: Windows moved part of the model into
system RAM, and the same first prompt took 70 s. Leaving vision out and using a 16k context
fixed it. Image models held in VRAM (ComfyUI) have the same effect.

A model on the Raspberry Pi's own CPU isn't fast enough for voice: a 4B model would take
minutes on that 5,000-token first prompt.

## Everyday commands

```bash
systemctl --user status pipa-api pipa-gateway pipa-bridge
journalctl --user -u pipa-bridge -f            # one line per voice turn, with its time
journalctl --user -u pipa-api -u pipa-gateway  # nanobot
~/.local/share/pipa/venv/bin/nanobot agent -m "Oi!"   # talk to it in the terminal
```

PiPA's memory, sessions and persona are in `~/.nanobot/workspace`.

## Security

PiPA is reachable from Telegram, so nanobot's shell tool is off and its file tools stay
inside its workspace. Its API and the bridge listen on 127.0.0.1 only, with a key between
them. Home Assistant's token only reaches the entities exposed to voice assistants.

## License

Apache License 2.0, see [LICENSE](LICENSE).
