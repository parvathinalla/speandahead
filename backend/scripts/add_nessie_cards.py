"""Admin-only, recoverable seeding of four fictional Nessie cards per planned user.

Default is a read-only preview. --apply creates sandbox accounts, never payments.
"""
import argparse
from copy import deepcopy
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
from scripts.import_nessie_slots import records
from scripts.seed_nessie_bulk import account_nickname

ROOT = Path(__file__).resolve().parents[1]
CARDS = {
    'card_a': {'name': 'Everyday Rewards', 'balance': 750, 'limit_usd': 1000,
               'rewards': {'groceries': .03, 'gas': .01, 'dining': .01}, 'statement_closes_in_days': 9},
    'card_b': {'name': 'Travel Rewards', 'balance': 200, 'limit_usd': 2000,
               'rewards': {'groceries': .02, 'gas': .02, 'travel': .03}, 'statement_closes_in_days': 13},
    'card_c': {'name': 'Dining Rewards', 'balance': 450, 'limit_usd': 3000,
               'rewards': {'dining': .04, 'groceries': .01, 'gas': .01}, 'statement_closes_in_days': 17},
    'card_d': {'name': 'Fuel Rewards', 'balance': 120, 'limit_usd': 4000,
               'rewards': {'gas': .04, 'groceries': .02, 'travel': .01}, 'statement_closes_in_days': 22},
}


def metadata(kind, account_id):
    card = CARDS[kind]
    return {'account_id': account_id, 'limit_usd': card['limit_usd'],
            'rewards': deepcopy(card['rewards']), 'statement_closes_in_days': card['statement_closes_in_days'],
            'display_name': card['name'] + ' (Demo)', 'issuer': 'CreditPilot Sandbox',
            'source': 'local_app_simulation'}


def find_card(rows, nickname, customer):
    matches = [row for row in rows if row.get('nickname') == nickname]
    if len(matches) > 1:
        raise ValueError('Duplicate card nicknames; manual review required')
    if matches and (matches[0].get('customer_id') != customer or matches[0].get('type') != 'Credit Card'):
        raise ValueError('Existing card ownership/type mismatch')
    return matches[0] if matches else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    config = dotenv_values(ROOT / '.env')
    dsn = config.get('TIGERDATA_DATABASE_URL', '')
    if conninfo_to_dict(dsn).get('host') != 'xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com':
        raise ValueError('Unexpected database target')
    key = config.get('NESSIE_API_KEY', '')
    fingerprint = hashlib.sha256(key.encode()).hexdigest()[:8]
    manifest_path = ROOT / 'nessie_bulk_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('sandbox_fingerprint') != fingerprint:
        raise ValueError('Sandbox fingerprint mismatch')
    plan = json.loads(args.plan.read_text(encoding='utf-8-sig'))
    base = config.get('NESSIE_BASE_URL', 'https://prod-api.nessieisreal.com').rstrip('/')
    if not base.startswith('https://') or not key:
        raise ValueError('Private Nessie key and HTTPS are required')
    store = TigerDataStore(dsn)
    planned = []
    with store.connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        for user in plan['users']:
            owner = NessieLinkStore.key(user['subject'])
            row = conn.execute('SELECT customer_id,accounts,scenario FROM cp_nessie_links WHERE owner_key=%s', (owner,)).fetchone()
            if not row or manifest['customers'].get(str(user['slot'])) != row[0]:
                raise ValueError('User/customer assignment mismatch')
            planned.append((user, owner, row))
    results = []
    with httpx.Client(timeout=25, follow_redirects=False) as client:
        def get_accounts(customer):
            response = client.get(base + '/customers/' + customer + '/accounts', params={'key': key})
            response.raise_for_status()
            return records(response.json())
        for user, owner, (customer, owned, scenario) in planned:
            remote = get_accounts(customer)
            updated = dict(owned)
            updated_scenario = deepcopy(scenario or {})
            app_cards = updated_scenario.setdefault('app_scenario', {})
            for kind, card in CARDS.items():
                nickname = account_nickname(fingerprint, user['slot'], kind)
                saved_id = owned.get(kind)
                if saved_id:
                    candidate = next((row for row in remote if row.get('_id') == saved_id), None)
                    if not candidate or candidate.get('customer_id') != customer or candidate.get('type') != 'Credit Card':
                        raise ValueError('Mapped credit card failed ownership validation')
                else:
                    candidate = find_card(remote, nickname, customer)
                if candidate is None and args.apply:
                    # Never retry ambiguous POSTs. Recover by deterministic nickname.
                    try:
                        client.post(base + '/customers/' + customer + '/accounts',
                            params={'key': key}, json={'type': 'Credit Card', 'nickname': nickname,
                                                       'balance': card['balance'], 'rewards': 0})
                    except httpx.HTTPError:
                        pass
                    remote = get_accounts(customer)
                    candidate = find_card(remote, nickname, customer)
                    if candidate is None:
                        raise ValueError('Creation outcome unresolved; rerun preview before retrying')
                if candidate:
                    updated[kind] = candidate['_id']
                    app_cards[kind] = metadata(kind, candidate['_id'])
            print(user['label'] + ': ' + str(sum(kind in updated for kind in CARDS)) +
                  (' verified cards ready' if args.apply else ' existing cards; target=4'))
            if args.apply:
                results.append((user, owner, customer, owned, updated, scenario, updated_scenario))
    if not args.apply:
        print('DRY RUN: no Nessie accounts or database rows changed')
        return
    with store.connect() as conn:
        conn.execute('SELECT pg_advisory_xact_lock(50315892)')
        for user, owner, customer, original, updated, old_scenario, scenario in results:
            current = conn.execute('SELECT customer_id,accounts,scenario FROM cp_nessie_links WHERE owner_key=%s FOR UPDATE', (owner,)).fetchone()
            if current != (customer, original, old_scenario):
                raise ValueError('Mapping changed during seeding; database changes rolled back')
            conn.execute('UPDATE cp_nessie_links SET accounts=%s,scenario=%s WHERE owner_key=%s',
                         (store.Jsonb(updated), store.Jsonb(scenario), owner))
            conn.execute('UPDATE cp_nessie_slots SET accounts=%s,verified_at=now() WHERE slot=%s AND customer_id=%s',
                         (store.Jsonb(updated), user['slot'], customer))
    # Synchronize the existing private seed manifest only after database commit.
    for user, _, _, _, updated, _, _ in results:
        manifest['accounts'][str(user['slot'])] = updated
    temporary = manifest_path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(manifest, indent=2) + '\n')
    temporary.replace(manifest_path)
    print('Committed four cards per user; source IDs are actual Nessie records. No transfers executed.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('Card provisioning stopped:', type(exc).__name__, '(private details suppressed)')
        sys.exit(1)
