"""PiPA's clock for nanobot: tells the model the current date, time and channel on every turn.

nanobot 0.4.1 knows the household's timezone (agents.defaults.timezone) but never puts the
time in the prompt. Asked "me lembra daqui a 1 minuto", the model had to guess the absolute
time that the cron tool's `at` needs, and on Telegram it answered without scheduling anything.

This plugin (entry point `nanobot.tools`) adds one line to the runtime context that nanobot
appends to each user message. That block sits at the end of the prompt, so the long prefix
the LLM server has cached doesn't change. It is also a small read-only tool, `clock`, for
turns that run long. And it starts nanobot's tokenizer at start-up (see create()).
"""

from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

from nanobot.agent.tools.base import Tool
from nanobot.runtime_context import RuntimeContextBlock, wrap_runtime_context_lines

WEEKDAYS = ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]
MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro",
          "outubro", "novembro", "dezembro"]


def now_line(timezone: str) -> str:
    now = datetime.now(ZoneInfo(timezone))
    return (f"Current time: {WEEKDAYS[now.weekday()]}, {now.day} de {MONTHS[now.month - 1]} de {now.year}, "
            f"{now:%H:%M} (ISO {now.isoformat(timespec='seconds')}, {timezone})")


class ClockTool(Tool):
    def __init__(self, timezone: str = "UTC"):
        self._timezone = timezone

    @classmethod
    def create(cls, ctx: Any) -> "ClockTool":
        # nanobot starts loading its tokenizer on the first request and sizes that request at
        # one token per byte meanwhile (~25k for a 6k-token prompt): with a 16k window, the
        # first message after every restart was refused (HTTP 500). Tools are created at
        # start-up, so the load starts here instead (it takes about half a second).
        try:
            from nanobot.utils.token_encoding import warmup_token_encoding
            warmup_token_encoding()
        except Exception:
            pass
        return cls(getattr(ctx, "timezone", None) or "UTC")

    @property
    def name(self) -> str:
        return "clock"

    @property
    def description(self) -> str:
        return "Returns the current date and time in the household's timezone."

    @property
    def parameters(self) -> dict[str, Any]:
        return {"type": "object", "properties": {}}

    @property
    def read_only(self) -> bool:
        return True

    def runtime_context_provider(self):
        async def provide(request: Any) -> RuntimeContextBlock:
            lines = [now_line(self._timezone)]
            if getattr(request, "channel", None):
                lines.append(f"Channel: {request.channel}")
            if getattr(request, "session_key", None):  # lets pipa-llm-log group a conversation's calls
                lines.append(f"Session: {request.session_key}")
            return RuntimeContextBlock(source="pipa_clock", content=wrap_runtime_context_lines(lines))
        return provide

    async def execute(self, **kwargs: Any) -> str:
        return now_line(self._timezone)
