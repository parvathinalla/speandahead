"""Run one opt-in hurricane budget simulation push cycle."""
import asyncio
from pathlib import Path
import sys

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

import main  # noqa: E402


if __name__ == "__main__":
    if not main.PUSH_ENABLED:
        raise SystemExit("Set PUSH_NOTIFICATIONS_ENABLED=true before sending pushes.")
    result = asyncio.run(main.run_hurricane_push_cycle())
    print("Users notified:", result["users_notified"])
