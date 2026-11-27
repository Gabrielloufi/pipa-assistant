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
  GPU, with a model that handles tool calls (tested with Gemma 4 12B and Qwen3.5 9B);
- optionally, Home Assistant 2026.8 or newer, and a Telegram bot.

```
phone / satellite ─> Home Assistant's assistant: speech to text ─> conversation ─> text to speech
                       conversation: a known home command ─> Home Assistant itself, no LLM
                                     anything else ─> pipa-bridge (:8901)
                                                        ─> nanobot API (:8900) ─> pipa-llm-log (:8902) ─> the LLM server
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
| `pipa-llm-log` | `~/.local/bin/pipa-llm-log` | Passes nanobot's calls to the LLM server and records them, for a page that shows what PiPA asked and what the model answered. |
| `pipa_clock/` | nanobot's environment | A nanobot plugin: gives the model the current time and the channel on every turn. |
| `pipa_calendar/` | nanobot's environment | A nanobot plugin: reads your Google Calendar and adds events to it, once authorized. |
| `pipa_links/` | nanobot's environment | A nanobot plugin: reads a link you send, summarizes and tags it, and finds it again later. |
| `pipa_tv/` | nanobot's environment | A nanobot plugin: works a [couchPie](https://github.com/Gabrielloufi/couchpie) TV box on the same machine (puts a Netflix title on, opens an app, turns the TV on or off). Loads only where couchPie's `kiosk` is installed. |
| `pipa-stt` | `~/.local/bin/pipa-stt` | Speech to text for voice notes: an OpenAI-style endpoint that asks your own Wyoming server (Whisper). |
| `pipa-google-auth` | `~/.local/bin/pipa-google-auth` | Authorizes PiPA to use your Google Calendar, once, from a computer with a browser. |
| `systemd/pipa-*.service` | `~/.config/systemd/user/` | nanobot's API, nanobot's gateway, the bridge and the call log, as user services. |
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
and starts the four services. Without tokens, PiPA already answers questions and remembers
conversations.

### Your own settings and persona

`install.sh` reads its settings from the file in `PIPA_CONF` and the persona from the file in
`PIPA_SOUL` when they're set. To keep your own in a private repository, put a `pipa.conf` and
a `SOUL.md` there, with a small script that runs this repository's installer:

```bash
PIPA_CONF="$HERE/pipa.conf" PIPA_SOUL="$HERE/SOUL.md" PIPA_USER="$HERE/USER.md" exec ../pipa-assistant/install.sh
```

`PIPA_USER` is optional: a first `USER.md` (your name, timezone, language), copied only over
nanobot's blank template, since PiPA keeps adding to that file.

The installed persona is replaced on every run while its first line (the comment) is there.
Delete that line in `~/.nanobot/workspace/SOUL.md` to keep edits made there.

### Home control and Telegram

Put the tokens in `~/.config/pipa/secrets.env` (`nano ~/.config/pipa/secrets.env`), then run
`./install.sh` again:

- `HA_TOKEN`: in Home Assistant, your profile → Security → **Long-lived access tokens** →
  Create. Also add the **Model Context Protocol Server** integration (Settings → Devices &
  services → Add integration), with Assist (device control). PiPA then sees and controls the
  devices you expose to voice assistants.
- **After exposing a new script, restart PiPA:** `systemctl --user restart pipa-gateway
  pipa-api`.
  - Each exposed script is a tool of its own, and nanobot reads Home Assistant's list of tools
    only when it starts.
  - Until the restart it doesn't see the new script, and a small model may pick a similar one
    instead (another room's).
  - Newly exposed devices need no restart, because the general tools find them by name.
- `TELEGRAM_TOKEN` and `TELEGRAM_ALLOW_FROM`: create a bot with @BotFather; your numeric
  Telegram user ID comes from @userinfobot. Only that ID can talk to the bot.

### Google Calendar

PiPA can read your Google Calendar and add events to it, through two tools:
`calendar_events` (the events in a period) and `calendar_add_event` (one event, no guests).

- **What PiPA can't do:** edit or delete events, or invite anyone. Google would e-mail the
  guests in your name.
- **Other people's invites:** events organized by someone else reach the model without their
  description, since anyone can send you an invite with text meant for the model.

The authorization is your own Google Cloud app. It's free and takes a few minutes, once.

1. At [console.cloud.google.com](https://console.cloud.google.com), create a project.
2. In **APIs & Services > Library**, enable the **Google Calendar API**.
3. In **Google Auth Platform**, set it up:
   - app name, your e-mail, audience **External**;
   - in **Data access**, add the scope `https://www.googleapis.com/auth/calendar.events.owned`
     (events on calendars you own, nothing else);
   - in **Audience**, **Publish app**. While it is "Testing", Google expires the
     authorization every 7 days. It doesn't need Google's verification for your own use.
4. In **Clients**, create one of type **Desktop app** and download its JSON.
5. On a computer with a browser, with that JSON and a clone of this repository:
   ```bash
   ./pipa-google-auth client_secret_XXXX.json google.env
   ```
   Open the link it prints, choose your account, and allow access. Google warns that the app
   isn't verified: it's yours, so choose Advanced > continue.
6. Add the three lines of `google.env` to `~/.config/pipa/secrets.env` on the Pi, delete
   `google.env`, and run `./install.sh` again.

To revoke the access, go to your Google account > Security > third-party apps and services.

### Voice notes

nanobot transcribes Telegram voice notes by sending them to an OpenAI-style
`/audio/transcriptions` endpoint, a cloud service by default. With `STT_URL` in `pipa.conf`
pointing at a Wyoming speech-to-text server (for example wyoming-faster-whisper on a PC with
a GPU, the one Home Assistant's voice uses), the installer starts `pipa-stt` on
127.0.0.1:8904 and points nanobot at it.

- It converts the audio with ffmpeg and asks your server for the text. Nothing runs on the Pi
  itself.
- Measured with Whisper large-v3-turbo on an RTX 4070 SUPER: 0.6–0.7 s for a 7 s voice note,
  about 5 s while the model loads.
- If the server is off, the message arrives without a transcription, and PiPA says it couldn't
  hear it.
- Leave `STT_URL` empty to keep voice notes off.

### Links

Send PiPA a link, alone or with a comment, and it goes into a catalog: a title, a summary of 2
or 3 sentences in Portuguese, a kind (article, news, video, repository, documentation, tool,
PDF, post) and 1 to 4 tags. Ask later for "os links sobre python" or "os vídeos que eu salvei"
and it finds them, by tag, by words (accents don't matter) or by kind.

- `link_add` reads the page on the Pi itself, not through nanobot's default cloud reader
  (Jina): web pages through readability, PDFs through pypdf, the first 12,000 characters.
- A separate call to the model writes the summary and picks the tags, reusing the ones in
  use. The page's text never enters the conversation, whose context is small, and links are
  stripped from the summary.
- Addresses inside the house or the tailnet are refused, at every redirect.
- Sending the same link again updates it. Tracking parameters (`utm_*`, `fbclid`...) are
  dropped first.

The catalog is `~/.local/state/pipa/links.sqlite3`, shown as a table on the model-call page's
**Links salvos** (`/links`), with tags and search.

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

## What PiPA asked the model

nanobot doesn't show what it sends to the model or which tools the model called, and a reply
can say "agendei" without any reminder behind it. `pipa-llm-log` sits between nanobot and the
LLM server, passes everything through unchanged (streaming too), and keeps a log with the
channel (Telegram, voz), your message, the tools offered, what the model called with which
arguments, its reply, tokens and time. A reply that claims an action without a tool call is
flagged in red.

The page gathers the calls of one conversation into a block, until a pause of 15 minutes, and
each of your messages shows the tool calls it led to and the final reply. Blocks are coloured
by who started them:
- **you:** Telegram, or Home Assistant's voice;
- **a test:** conversations named `teste-…` or `bench-…`, or nanobot run from a terminal;
- **PiPA on its own:** Dream, conversation summaries, reminders firing.

Checkboxes hide any of the three. `pipa_clock` puts the channel and the conversation in each
message's runtime context, which is how the log tells them apart.

The page is at `http://127.0.0.1:8903/` on the Pi, and the installer also serves it on your
tailnet at `https://<pi>.<tailnet>.ts.net:8444/`; `/api/calls?limit=N` gives the same as JSON.
The log, `~/.local/state/pipa/llm-calls.jsonl`, holds your conversations: it stays on the Pi
and is kept under 20 MB. `PIPA_LLM_LOG=0` in `pipa.conf` turns it off.

## Stopping PiPA: "pare"

Send just **pare** on Telegram, or say it by voice, and PiPA pauses. Every call it
makes to the model gets a fixed reply from `pipa-llm-log` instead, so no tool runs: nothing
in the house, no reminder, no link. A task that was running stops at its next step.

- **despausar** ends the pause. These are plain words on purpose: nanobot's Telegram channel
  silently drops any `/command` it doesn't know.
- The pause is a file, `~/.local/state/pipa/pausada`, so it survives restarts, and the
  model-call page shows it.
- nanobot's own **`/stop`** cancels the running task at once, without pausing.

## Tool schemas from Home Assistant

Home Assistant describes some numbers as an `allOf` of two types (a fan's percentage is
"integer" and "number from 0 to 100"). llama.cpp turns that into a grammar that only allows
`{}`, so the model could never set a fan's speed. `pipa-llm-log` merges such `allOf`s into one
type before the request reaches the server.

## The time, and the first message after a restart

nanobot 0.4.1 knows your timezone but never tells the model the time, so the model guessed it
("me lembra daqui a 1 minuto" became a job every minute, or none). The `pipa_clock` plugin adds
the current time and the channel to every message, in the runtime context nanobot appends at
the end, so the prompt the server has cached doesn't change. It also loads nanobot's tokenizer
at start-up: nanobot otherwise loads it on the first request and meanwhile overestimates that
request about fourfold, refusing it with a 16k context.

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
systemctl --user status pipa-api pipa-gateway pipa-bridge pipa-llm-log
journalctl --user -u pipa-bridge -f            # one line per voice turn, with its time
journalctl --user -u pipa-api -u pipa-gateway  # nanobot
journalctl _SYSTEMD_USER_UNIT=pipa-gateway.service   # the same, where the user journal isn't kept
~/.local/share/pipa/venv/bin/nanobot agent -m "Oi!"   # talk to it in the terminal
```

PiPA's memory, sessions and persona are in `~/.nanobot/workspace`.

## Security

PiPA is reachable from Telegram, so nanobot's shell tool is off and its file tools stay
inside its workspace. Its API and the bridge listen on 127.0.0.1 only, with a key between
them. Home Assistant's token only reaches the entities exposed to voice assistants. The
model-call page shows your conversations: it listens on 127.0.0.1, and the installer
publishes it only to your tailnet.

Chats with a Telegram bot are not end-to-end encrypted: Telegram stores them on its servers.
Keep sensitive matters out of them, and give your Telegram account a two-step verification
password, since whoever logs into it can give PiPA orders. nanobot also has a Signal channel
(through signal-cli), which is end-to-end encrypted.

## License

Apache License 2.0, see [LICENSE](LICENSE).
