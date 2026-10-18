"""Validate existing Nessie seed references and import unassigned TigerData slots.

No banking customers, balances, credentials or Auth0 identities are generated.
Default is read-only validation; --apply imports references atomically.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dotenv import dotenv_values
import httpx
from psycopg.conninfo import conninfo_to_dict
from nessie_links import NessieLinkStore
from tigerdata_store import TigerDataStore

ROOT = Path(__file__).resolve().parents[1]


def records(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get('results'), list):
        return payload['results']
    raise ValueError('Unexpected Nessie list response; no rows imported')


def validate(manifest, customers, accounts, key):
    if manifest.get('sandbox_fingerprint') != hashlib.sha256(key.encode()).hexdigest()[:8]:
        raise ValueError('Manifest belongs to a different Nessie sandbox')
    customer_index = {row['_id']: row for row in customers}
    account_index = {row['_id']: row for row in accounts}
    rows, seen_customers, seen_accounts = [], set(), set()
    for slot, customer in manifest['customers'].items():
        owned = manifest['accounts'].get(slot, {})
        NessieLinkStore.validate_mapping(customer, owned)
        if customer not in customer_index or customer in seen_customers:
            raise ValueError('Missing or duplicate seeded customer')
        for ident in owned.values():
            record = account_index.get(ident)
            if not record or record.get('customer_id') != customer or ident in seen_accounts:
                raise ValueError('Missing, shared or mismatched seeded account')
            seen_accounts.add(ident)
        seen_customers.add(customer)
        rows.append((int(slot), customer, owned))
    if not rows:
        raise ValueError('No seeded records available')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    config = dotenv_values(ROOT / '.env')
    dsn = config.get('TIGERDATA_DATABASE_URL', '')
    if conninfo_to_dict(dsn).get('host') != 'xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com':
        raise ValueError('Unexpected TigerData target')
    key = config.get('NESSIE_API_KEY', '')
    base = config.get('NESSIE_BASE_URL', 'https://prod-api.nessieisreal.com').rstrip('/')
    if not key or not base.startswith('https://'):
        raise ValueError('Configure private Nessie key and HTTPS endpoint')
    manifest = json.loads((ROOT / 'nessie_bulk_manifest.json').read_text())
    with httpx.Client(timeout=30, follow_redirects=False) as client:
        customer_response = client.get(base + '/customers', params={'key': key})
        customer_response.raise_for_status()
        account_response = client.get(base + '/accounts', params={'key': key})
        account_response.raise_for_status()
        rows = validate(manifest, records(customer_response.json()), records(account_response.json()), key)
    print('Validated existing Nessie customer slots:', len(rows))
    print('Validated existing Nessie account references:', sum(len(row[2]) for row in rows))
    if not args.apply:
        print('DRY RUN: no changes made')
        return
    store = TigerDataStore(dsn)
    with store.connect() as conn:
        conn.execute('SELECT pg_advisory_xact_lock(50315892)')
        conn.execute('''CREATE TABLE IF NOT EXISTS public.cp_nessie_slots (
            slot INTEGER PRIMARY KEY CHECK (slot >= 0),
            customer_id TEXT NOT NULL UNIQUE,
            accounts JSONB NOT NULL CHECK (jsonb_typeof(accounts)='object' AND accounts ? 'checking'),
            verified_at TIMESTAMPTZ NOT NULL DEFAULT now())''')
        for slot, customer, accounts in rows:
            conn.execute('''INSERT INTO public.cp_nessie_slots(slot,customer_id,accounts)
                VALUES(%s,%s,%s) ON CONFLICT(slot) DO NOTHING''',
                (slot, customer, store.Jsonb(accounts)))
            saved = conn.execute('SELECT customer_id,accounts FROM public.cp_nessie_slots WHERE slot=%s', (slot,)).fetchone()
            if saved != (customer, accounts):
                raise ValueError('Existing slot differs; import rolled back')
        print('Imported slot count:', conn.execute('SELECT COUNT(*) FROM public.cp_nessie_slots').fetchone()[0])
    print('Committed. Slots remain unassigned until an administrator links actual Auth0 users.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('Import stopped:', type(exc).__name__, '(private details suppressed)')
        sys.exit(1)
