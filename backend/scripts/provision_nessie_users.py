"""Admin-only assignment of existing Nessie slots to actual Auth0 test users.

Requires a private JSON plan. Dry run by default; --apply writes atomically.
Never creates customers, stores passwords or executes banking transfers.
"""
import argparse
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

ROOT = Path(__file__).resolve().parents[1]


def validate_plan(plan):
    users = plan['users']
    labels = [user['label'] for user in users]
    subjects = [user['subject'] for user in users]
    slots = [user['slot'] for user in users]
    if not users or len(set(labels)) != len(users) or len(set(subjects)) != len(users):
        raise ValueError('User labels and Auth0 subjects must be unique')
    for subject in subjects:
        if not isinstance(subject, str) or not subject.startswith('auth0|'):
            raise ValueError('Use actual Auth0 database user IDs')
        NessieLinkStore.key(subject)
    joint = plan['joint']
    if joint['primary'] not in labels or joint['dependent'] not in labels or joint['primary'] == joint['dependent']:
        raise ValueError('Joint primary and dependent must be distinct planned users')
    slots.append(joint['slot'])
    if len(set(slots)) != len(slots) or any(type(slot) is not int or slot < 0 for slot in slots):
        raise ValueError('Personal and joint slots must be distinct nonnegative integers')
    return users, joint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    users, joint = validate_plan(json.loads(args.plan.read_text(encoding='utf-8-sig')))
    config = dotenv_values(ROOT / '.env')
    dsn = config.get('TIGERDATA_DATABASE_URL', '')
    if conninfo_to_dict(dsn).get('host') != 'xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com':
        raise ValueError('Unexpected database service')
    store = TigerDataStore(dsn)
    requested_slots = [user['slot'] for user in users] + [joint['slot']]
    with store.connect() as conn:
        conn.execute('SET TRANSACTION READ ONLY')
        slots = {}
        for slot in requested_slots:
            row = conn.execute('SELECT customer_id,accounts FROM cp_nessie_slots WHERE slot=%s', (slot,)).fetchone()
            if not row:
                raise ValueError('Requested verified slot is missing')
            NessieLinkStore.validate_mapping(*row)
            slots[slot] = row
    base = config.get('NESSIE_BASE_URL', 'https://prod-api.nessieisreal.com').rstrip('/')
    key = config.get('NESSIE_API_KEY', '')
    if not base.startswith('https://') or not key:
        raise ValueError('HTTPS Nessie endpoint and private key are required')
    with httpx.Client(timeout=30) as client:
        response = client.get(base + '/customers', params={'key': key})
        response.raise_for_status()
        customers = {row['_id'] for row in records(response.json())}
        response = client.get(base + '/accounts', params={'key': key})
        response.raise_for_status()
        accounts = {row['_id']: row for row in records(response.json())}
    for customer, owned in slots.values():
        if customer not in customers or any(accounts.get(ident, {}).get('customer_id') != customer for ident in owned.values()):
            raise ValueError('Nessie slot ownership verification failed')
    by_label = {user['label']: user for user in users}
    primary = NessieLinkStore.key(by_label[joint['primary']]['subject'])
    dependent = NessieLinkStore.key(by_label[joint['dependent']]['subject'])
    joint_id = slots[joint['slot']][1]['checking']
    recipients = [{'id': label.lower() + '-personal', 'name': label + ' personal checking',
                   'account_id': slots[by_label[label]['slot']][1]['checking']}
                  for label in (joint['primary'], joint['dependent'])]
    print('Verified personal users:', len(users), '; verified joint account: 1')
    print('Roles:', joint['primary'], 'primary;', joint['dependent'], 'dependent')
    if not args.apply:
        print('DRY RUN: no rows changed')
        return
    with store.connect() as conn:
        conn.execute('SELECT pg_advisory_xact_lock(50315892)')
        for slot, expected in slots.items():
            if conn.execute('SELECT customer_id,accounts FROM cp_nessie_slots WHERE slot=%s FOR UPDATE', (slot,)).fetchone() != expected:
                raise ValueError('Slot changed during validation')
        for user in users:
            customer, owned = slots[user['slot']]
            owner = NessieLinkStore.key(user['subject'])
            if conn.execute('SELECT 1 FROM cp_joint_accounts WHERE account_id=ANY(%s)', (list(owned.values()),)).fetchone():
                raise ValueError('Personal slot is already reserved as a joint account')
            conn.execute('''INSERT INTO cp_nessie_links(owner_key,customer_id,accounts)
                VALUES(%s,%s,%s) ON CONFLICT(owner_key) DO NOTHING''', (owner, customer, store.Jsonb(owned)))
            saved = conn.execute('SELECT customer_id,accounts FROM cp_nessie_links WHERE owner_key=%s', (owner,)).fetchone()
            if saved != (customer, owned):
                raise ValueError('Existing user mapping differs; no rows committed')
        if conn.execute('SELECT 1 FROM cp_nessie_links WHERE customer_id=%s', (slots[joint['slot']][0],)).fetchone():
            raise ValueError('Joint slot is already assigned as a personal customer')
        existing = conn.execute('SELECT primary_sub,dependent_sub,name,recipients FROM cp_joint_accounts WHERE account_id=%s', (joint_id,)).fetchone()
        if existing:
            if existing[:3] != (primary, dependent, joint['name']) or json.loads(existing[3]) != recipients:
                raise ValueError('Joint membership differs; no rows committed')
        else:
            for subject in (primary, dependent):
                if conn.execute('SELECT 1 FROM cp_joint_accounts WHERE primary_sub=%s OR dependent_sub=%s', (subject, subject)).fetchone():
                    raise ValueError('User already has a different joint membership')
            conn.execute('''INSERT INTO cp_joint_accounts(account_id,name,primary_sub,dependent_sub,recipients)
                VALUES(%s,%s,%s,%s,%s)''', (joint_id, joint['name'], primary, dependent, json.dumps(recipients)))
    print('Committed personal mappings and joint membership. Threshold remains primary-configured; no payments created.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('Provisioning stopped:', type(exc).__name__, '(private details suppressed)')
        sys.exit(1)
