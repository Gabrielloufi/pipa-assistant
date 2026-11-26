#!/usr/bin/env python3
"""Tries pipa_links' reader on one link and prints what link_add would read (title,
description, text), for testing on the Pi without going through PiPA. Nothing is saved.

  probe.py URL
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pipa_links as pl  # noqa: E402


async def main() -> None:
    url = pl._canonical(sys.argv[1])
    final_url, kind, body, charset = await pl.fetch(url)
    title, description, text = pl.extract(final_url, kind, body, charset)
    print(f"final url: {final_url}\ntitle: {title}\ndescription: {description}\n"
          f"text ({len(text)} chars): {text[:600]}")


asyncio.run(main())
