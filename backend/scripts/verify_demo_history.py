"""Verify provider-backed history, bills and EMIs; optionally store derived summaries."""
import argparse
import asyncio
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


async def run(save):
    import main
    from nessie_activity import history
    from nessie_links import NessieLinkStore
    root = Path(__file__).resolve().parents[1]
    plan = json.loads((root / 'private/provision_users.json').read_text(encoding='utf-8-sig'))
    g = main.NessieGateway()
    seen = set()
    total = Counter()
    for user in plan['users']:
        m = main.manifest(user['subject'])
        owned = await main.accounts(g, m)
        activity = await history(g, m)
        ids = {row['id'] for row in activity['transactions']}
        if ids & seen:
            raise ValueError('History leaked across users')
        seen |= ids
        dates = [row['date'] for row in activity['transactions']]
        counts = Counter(row['record_type'] for row in activity['transactions'])
        loan_rows = await g.request('GET', '/accounts/' + m['ids']['accounts']['checking'] + '/loans')
        categories = Counter()
        for row in activity['transactions']:
            if row['direction'] == 'debit' and row['category'] not in ('transfer', 'card_payment'):
                categories[row['category']] += row['amount']
        summary = {'source': 'nessie_verified_history', 'start': min(dates), 'end': max(dates),
            'verified_at': datetime.now(timezone.utc).isoformat(), 'transaction_count': len(ids),
            'observed_months': 2, 'total_spending_usd': round(sum(categories.values()), 2),
            'average_monthly_spending_usd': round(sum(categories.values()) / 2, 2),
            'categories': {name: round(value, 2) for name, value in categories.items()},
            'monthly_emi_usd': sum(row['monthly_payment'] for row in loan_rows),
            'note': 'Historical seeded spending, including EMI payments; not a guarantee of future expenses.'}
        print(user['label'], {'accounts': len(owned), 'transactions': len(ids), 'types': dict(counts),
              'start': min(dates), 'end': max(dates), 'loans': len(loan_rows),
              'upcoming_bills': len(m['app_bills']), 'coverage_warnings': len(activity['warnings'])}, flush=True)
        if len(ids) != 276 or len(loan_rows) != 2 or len(m['app_bills']) != 6:
            raise ValueError('Unexpected history coverage; inspect provider records')
        if save:
            with main.nessie_links().store.connect() as conn:
                owner = NessieLinkStore.key(user['subject'])
                row = conn.execute('SELECT scenario FROM cp_nessie_links WHERE owner_key=%s FOR UPDATE', (owner,)).fetchone()
                scenario = row[0] or {}
                scenario['observed_history'] = summary
                conn.execute('UPDATE cp_nessie_links SET scenario=%s WHERE owner_key=%s',
                             (main.nessie_links().store.Jsonb(scenario), owner))
        total.update(counts)
    print('Verified aggregate transaction counts:', dict(total))
    print('Cross-user isolation verified. No transactions posted during verification.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--save-summary', action='store_true')
    args = parser.parse_args()
    try:
        asyncio.run(run(args.save_summary))
    except Exception as exc:
        print('Verification stopped:', type(exc).__name__, '(private details suppressed)')
        sys.exit(1)
