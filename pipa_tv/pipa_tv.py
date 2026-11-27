"""PiPA's TV remote for nanobot: works the couchPie TV box on the same machine.

  tv_assistir(titulo, perfil?)   searches Netflix for a title and plays it (kiosk-watch); a
                                 series resumes where that profile stopped
  tv_abrir(app)                  opens a streaming service or Kodi on the TV (kiosk run)
  tv_energia(acao)               turns the TV on or off (kiosk wake / standby)

The tools load only where couchPie's `kiosk` is installed (~/.local/bin/kiosk, or
PIPA_KIOSK_DIR). Netflix accounts are often shared: tv_assistir never picks a profile by
itself. Without one it returns the profiles' names, so the model asks.
"""

import asyncio
import json
import os
from typing import Any

from nanobot.agent.tools.base import Tool

BIN = os.path.expanduser(os.environ.get("PIPA_KIOSK_DIR", "~/.local/bin"))
APPS = {"netflix": "Netflix", "youtube": "YouTube", "primevideo": "Prime Video", "disney": "Disney+",
        "hbomax": "HBO Max", "globoplay": "Globoplay", "paramount": "Paramount+", "kodi": "Kodi"}


async def run(*args: str, timeout: float = 150) -> tuple[int, str]:
    proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE,
                                                stderr=asyncio.subprocess.STDOUT)
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        return 124, "timed out"
    return proc.returncode, out.decode(errors="replace").strip()


class _TvTool(Tool):
    program = "kiosk"

    @classmethod
    def enabled(cls, ctx: Any) -> bool:
        return os.access(os.path.join(BIN, cls.program), os.X_OK)

    @classmethod
    def create(cls, ctx: Any) -> "_TvTool":
        return cls()


class TvWatchTool(_TvTool):
    program = "kiosk-watch"

    @property
    def name(self) -> str:
        return "tv_assistir"

    @property
    def description(self) -> str:
        return ("Puts a series or film on the living room TV: opens Netflix on the given profile, searches "
                "for the title and plays it (a series resumes where that profile stopped). Netflix only. "
                "The account is shared: pass the profile the person named; if they didn't name one, call "
                "without it to get the profiles' names and ASK which one, never guess. Takes up to a minute.")

    @property
    def parameters(self) -> dict[str, Any]:
        return {"type": "object", "properties": {
            "titulo": {"type": "string", "description": "The title as the person said it, e.g. 'A Diplomata'"},
            "perfil": {"type": "string", "description": "The Netflix profile's name, only if the person said it"},
        }, "required": ["titulo"]}

    async def execute(self, titulo: str, perfil: str = "", **kwargs: Any) -> str:
        args = [os.path.join(BIN, "kiosk-watch")] + (["--profile", perfil] if perfil else []) + ["netflix", titulo]
        code, out = await run(*args)
        try:
            result = json.loads(out.splitlines()[-1])
        except (ValueError, IndexError):
            return f"The TV didn't answer properly ({out[-200:]}). Say it didn't work."
        if result.get("needs_profile"):
            names = ", ".join(result.get("profiles") or [])
            return f"Netflix needs a profile. Ask the person which one: {names}. Nothing is playing yet."
        if result.get("ok"):
            return f"Playing '{result['title']}' on the TV, on Netflix, profile {result.get('profile')}."
        return f"It didn't work: {result.get('error')}"


class TvOpenTool(_TvTool):
    @property
    def name(self) -> str:
        return "tv_abrir"

    @property
    def description(self) -> str:
        return ("Opens a streaming service or Kodi on the living room TV, on its home page (to put a specific "
                "title on, use tv_assistir).")

    @property
    def parameters(self) -> dict[str, Any]:
        return {"type": "object", "properties": {
            "app": {"type": "string", "enum": sorted(APPS), "description": "Which app to open"},
        }, "required": ["app"]}

    async def execute(self, app: str, **kwargs: Any) -> str:
        if app not in APPS:
            return f"Unknown app '{app}'. Options: {', '.join(APPS.values())}."
        code, out = await run(os.path.join(BIN, "kiosk"), "run", app, timeout=30)
        return f"Opened {APPS[app]} on the TV." if code == 0 else f"It didn't open: {out[-200:]}"


class TvPowerTool(_TvTool):
    @property
    def name(self) -> str:
        return "tv_energia"

    @property
    def description(self) -> str:
        return "Turns the living room TV on (to the TV box's input) or off (standby)."

    @property
    def parameters(self) -> dict[str, Any]:
        return {"type": "object", "properties": {
            "acao": {"type": "string", "enum": ["ligar", "desligar"]},
        }, "required": ["acao"]}

    async def execute(self, acao: str, **kwargs: Any) -> str:
        command = "wake" if acao == "ligar" else "standby"
        code, out = await run(os.path.join(BIN, "kiosk"), command, timeout=30)
        return ("TV on." if acao == "ligar" else "TV off.") if code == 0 else f"It didn't work: {out[-200:]}"
