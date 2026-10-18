"""Test two chat turns using only fictional context; no banking writes."""
import asyncio
import os
from pathlib import Path
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dotenv import load_dotenv
from agent_service import ask_gemini


async def run():
    load_dotenv(Path(__file__).resolve().parents[1] / '.env')
    context = {'source': 'nessie_sandbox', 'banking_is_sandbox': True,
               'account_balances': [{'role': 'checking', 'balance_usd': 500}],
               'cashflow_14days': {'checking_balance_usd': 500},
               'monthly_income_usd': None}
    history = []
    for question in ('Can I buy a $900 laptop?', 'In how many months can I save and get one?'):
        start = time.monotonic()
        reply, used = await ask_gemini(question, context, [], history)
        print({'elapsed_seconds': round(time.monotonic() - start, 2), 'ai_used': used})
        print(reply)
        if not used:
            raise RuntimeError('Live chat smoke check failed')
        history.extend([{'role': 'user', 'content': question}, {'role': 'assistant', 'content': reply}])


if __name__ == '__main__':
    asyncio.run(run())
