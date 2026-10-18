"""Seed 2 months of fictional activity into existing, owner-validated Nessie accounts.

No transfers, real payments, account deletions or balance overwrites. Dry run by
default. A private journal prevents replaying successful or uncertain POSTs.
"""
import argparse
import calendar
from collections import Counter
from datetime import date, timedelta
import hashlib
import json
from pathlib import Path
import random
import re
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dotenv import dotenv_values
import httpx
from psycopg.conninfo import conninfo_to_dict
from tigerdata_store import TigerDataStore
from nessie_links import NessieLinkStore
from scripts.import_nessie_slots import records

ROOT = Path(__file__).resolve().parents[1]
JOURNAL = ROOT / 'private/demo_history_journal.json'
PERSONAS = [
    {'income': 5200, 'rent': 1400, 'auto': 320, 'education': 140},
    {'income': 3600, 'rent': 1150, 'auto': 285, 'education': 110},
    {'income': 6800, 'rent': 1650, 'auto': 390, 'education': 180},
]
MERCHANTS = [('Coffee Corner', 'dining'), ('Campus Kitchen', 'dining'),
             ('Fresh Market', 'groceries'), ('City Fuel', 'gas'),
             ('Stream Plus', 'entertainment'), ('Tech Store', 'shopping'),
             ('Demo Pharmacy', 'health'), ('Transit Pass', 'transport')]


def two_months_before(day):
    month = day.month - 2
    year = day.year
    if month < 1:
        month += 12
        year -= 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def plan_user(user, accounts, as_of, index):
    persona = PERSONAS[index % len(PERSONAS)]
    prefix = f'CP2M-{as_of:%Y%m%d}-s{user["slot"]}'
    operations = []
    rng = random.Random(prefix)
    day = two_months_before(as_of)
    while day < as_of:
        for event in range(4):
            merchant = event if rng.random() < .85 else rng.randrange(len(MERCHANTS))
            kind = 'card_' + 'abcd'[(day.toordinal() + event) % 4]
            amount = round(rng.uniform(*[(4, 9), (10, 24), (24, 68), (8, 28)][event]) * (1 + index * .08), 2)
            marker = f'{prefix}-spend-{day:%Y%m%d}-{event}'
            category = MERCHANTS[merchant][1]
            operations.append({'resource': 'withdrawals', 'account': kind, 'marker': marker,
                'merchant': merchant, 'payload': {'medium': 'balance', 'transaction_date': day.isoformat(), 'status': 'completed',
                    'amount': amount, 'description': marker + ' | ' + category + ' | ' + MERCHANTS[merchant][0]}})
        if day.day in (1, 15):
            marker = f'{prefix}-salary-{day:%Y%m%d}'
            operations.append({'resource': 'deposits', 'account': 'checking', 'marker': marker,
                'payload': {'medium': 'balance', 'transaction_date': day.isoformat(), 'status': 'completed',
                    'amount': persona['income'] / 2, 'description': marker + ' | income | Demo payroll'}})
        if day.day in (3, 8, 12, 18, 22, 25):
            bills = {3: ('rent', persona['rent']), 8: ('utilities', 115 + index * 20),
                     12: ('internet', 65), 18: ('emi', persona['auto']),
                     22: ('emi', persona['education']), 25: ('subscription', 24.99)}
            category, amount = bills[day.day]
            marker = f'{prefix}-paidbill-{day:%Y%m%d}'
            operations.append({'resource': 'withdrawals', 'account': 'checking', 'marker': marker,
                'payload': {'medium': 'balance', 'transaction_date': day.isoformat(), 'status': 'completed',
                    'amount': amount, 'description': marker + ' | ' + category + ' | Demo bill/EMI payment'}})
        if day.day == 28:
            for card_index, kind in enumerate(('card_a', 'card_b', 'card_c', 'card_d')):
                amount = (220 + 60 * card_index) * (1 + .15 * index)
                marker = f'{prefix}-cardpayment-{day:%Y%m%d}-{kind}'
                operations.append({'resource': 'withdrawals', 'account': 'checking', 'marker': marker + '-debit',
                    'payload': {'medium': 'balance', 'transaction_date': day.isoformat(), 'status': 'completed',
                        'amount': amount, 'description': marker + '-debit | card_payment | Demo statement payment'}})
                operations.append({'resource': 'deposits', 'account': kind, 'marker': marker + '-credit',
                    'payload': {'medium': 'balance', 'transaction_date': day.isoformat(), 'status': 'completed',
                        'amount': amount, 'description': marker + '-credit | card_payment | Demo statement credit'}})
        day += timedelta(days=1)
    for kind, payment in (('auto', persona['auto']), ('education', persona['education'])):
        marker = prefix + '-loan-' + kind
        operations.append({'resource': 'loans', 'account': 'checking', 'marker': marker,
            'payload': {'type': kind, 'status': 'approved', 'credit_score': 700 + index * 15,
                'monthly_payment': payment, 'amount': payment * 24,
                'description': marker + ' | Demo existing ' + kind + ' installment loan'}})
    upcoming = {}
    for offset, category, amount in ((3, 'rent', persona['rent']), (5, 'utilities', 115 + index * 20),
                                    (7, 'internet', 65), (9, 'auto_emi', persona['auto']),
                                    (12, 'education_emi', persona['education']), (14, 'subscription', 24.99)):
        due = as_of + timedelta(days=offset)
        marker = prefix + '-upcoming-' + category
        bill = {'status': 'pending', 'payee': 'Demo ' + category.replace('_', ' ').title(),
                'nickname': marker, 'payment_date': due.isoformat(), 'recurring_date': due.day,
                'payment_amount': amount}
        operations.append({'resource': 'bills', 'account': 'checking', 'marker': marker, 'payload': bill})
        upcoming[marker] = {**bill, 'account_id': accounts['checking'], 'category': category,
                            'frequency': 'monthly', 'upcoming_payment_date': due.isoformat()}
    return operations, upcoming, persona


class Seeder:
    def __init__(self, config, apply):
        self.config, self.apply = config, apply
        self.client = httpx.Client(timeout=25, follow_redirects=False)
        self.base = config['NESSIE_BASE_URL'].rstrip('/')
        if not self.base.startswith('https://'):
            raise ValueError('HTTPS required')
        self.state = json.loads(JOURNAL.read_text()) if JOURNAL.exists() else {'version': 1, 'operations': {}}
        self.cache = {}

    def save(self):
        temp = JOURNAL.with_suffix('.json.tmp')
        for attempt in range(8):
            try:
                temp.write_text(json.dumps(self.state, indent=2) + '\n')
                temp.replace(JOURNAL)
                return
            except PermissionError:
                if attempt == 7:
                    raise
                time.sleep(.15 * (attempt + 1))

    def request(self, method, path, payload=None):
        return self.client.request(method, self.base + path,
            params={'key': self.config['NESSIE_API_KEY']}, json=payload)

    def listing(self, path):
        if path not in self.cache:
            response = self.request('GET', path)
            response.raise_for_status()
            self.cache[path] = records(response.json())
        return self.cache[path]

    def ensure(self, path, marker, payload, match_field='description'):
        entry = self.state['operations'].get(marker)
        if entry and entry.get('status') == 'confirmed':
            return entry['id']
        rows = self.listing(path)
        matches = [row for row in rows if str(row.get(match_field, '')).startswith(marker)]
        if len(matches) > 1:
            raise ValueError('Duplicate demo seed marker')
        if matches:
            identity = matches[0]['_id']
        else:
            if entry and entry.get('status') == 'posting':
                raise ValueError('Uncertain prior creation requires manual reconciliation')
            if not self.apply:
                return None
            self.state['operations'][marker] = {'status': 'posting', 'resource': path.rsplit('/', 1)[-1]}
            self.save()
            response = self.request('POST', path, payload)
            if response.status_code >= 400:
                self.state['operations'][marker]['status'] = 'rejected' if response.status_code < 500 else 'posting'
                self.state['operations'][marker]['http_status'] = response.status_code
                self.save()
                # Field-validation messages contain only our fictional payload.
                print('Provider rejected', path.rsplit('/', 1)[-1], 'HTTP', response.status_code,
                      response.text.replace(self.config['NESSIE_API_KEY'], '[REDACTED]')[:350])
                response.raise_for_status()
            data = response.json()
            created = data.get('objectCreated', data)
            identity = created.get('_id') if isinstance(created, dict) else None
            if not identity:
                self.cache.pop(path, None)
                matches = [row for row in self.listing(path) if str(row.get(match_field, '')).startswith(marker)]
                if len(matches) != 1:
                    raise ValueError('Uncertain creation outcome; no automatic retry')
                identity = matches[0]['_id']
            self.cache.setdefault(path, []).append({**payload, '_id': identity})
        if self.apply:
            self.state['operations'][marker] = {'status': 'confirmed', 'id': identity, 'resource': path.rsplit('/', 1)[-1]}
            self.save()
        return identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--as-of', type=date.fromisoformat, default=date(2026, 10, 18))
    parser.add_argument('--max-new', type=int, default=0, help='Limit new records for a safe initial probe (0 = all)')
    args = parser.parse_args()
    config = dotenv_values(ROOT / '.env')
    if conninfo_to_dict(config['TIGERDATA_DATABASE_URL']).get('host') != 'xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com':
        raise ValueError('Unexpected database target')
    plan = json.loads((ROOT / 'private/provision_users.json').read_text(encoding='utf-8-sig'))
    store = TigerDataStore(config['TIGERDATA_DATABASE_URL'])
    seeded = Seeder(config, args.apply)
    fingerprint = hashlib.sha256(config['NESSIE_API_KEY'].encode()).hexdigest()[:8]
    if seeded.state.get('sandbox_fingerprint', fingerprint) != fingerprint:
        raise ValueError('Journal belongs to another sandbox')
    seeded.state['sandbox_fingerprint'] = fingerprint
    initial = len(seeded.state['operations'])
    merchant_ids = []
    for name, category in MERCHANTS:
        marker = 'CP-Demo-History-' + name
        merchant_ids.append(seeded.ensure('/merchants', marker, {'name': marker, 'category': category}, 'name'))
    for index, user in enumerate(plan['users']):
        owner = NessieLinkStore.key(user['subject'])
        with store.connect() as conn:
            row = conn.execute('SELECT customer_id,accounts,scenario FROM cp_nessie_links WHERE owner_key=%s', (owner,)).fetchone()
        if not row:
            raise ValueError('User mapping missing')
        customer, owned, scenario = row
        for account in owned.values():
            response = seeded.request('GET', '/accounts/' + account)
            response.raise_for_status()
            if response.json().get('customer_id') != customer:
                raise ValueError('Account ownership mismatch')
        operations, upcoming, persona = plan_user(user, owned, args.as_of, index)
        print(user['label'], 'planned:', dict(Counter(op['resource'] for op in operations)), flush=True)
        if not args.apply:
            continue
        bill_readable = seeded.state.get('bill_readable', True)
        for number, operation in enumerate(operations):
            resource = operation['resource']
            payload = dict(operation['payload'])
            if resource == 'purchases':
                payload['merchant_id'] = merchant_ids[operation['merchant']]
            if resource == 'bills' and not bill_readable:
                continue
            path = '/accounts/' + owned[operation['account']] + '/' + resource
            identity = seeded.ensure(path, operation['marker'], payload, 'nickname' if resource == 'bills' else 'description')
            if resource == 'bills':
                if operation['marker'] in upcoming:
                    upcoming[operation['marker']]['bill_id'] = identity
                    upcoming[operation['marker']]['source'] = 'nessie_sandbox'
                check = seeded.request('GET', path)
                if check.status_code >= 400:
                    bill_readable = False
                    seeded.state['bill_readable'] = False
                    seeded.save()
                    print('Nessie bill read-model error; stopping additional bill creation; retaining explicit app schedule.', flush=True)
            if number % 50 == 0:
                print(user['label'], 'progress:', number + 1, '/', len(operations), flush=True)
            if args.max_new and len(seeded.state['operations']) - initial >= args.max_new:
                print('Probe limit reached; safe to resume using the same journal.', flush=True)
                return
        new_scenario = dict(scenario or {})
        new_scenario['monthly_income'] = persona['income']
        new_scenario['app_bills'] = {**new_scenario.get('app_bills', {}), **upcoming}
        for bill in new_scenario['app_bills'].values():
            bill.setdefault('source', 'app_simulation' if not bill_readable else 'nessie_sandbox')
        new_scenario['history_seed'] = {'as_of': args.as_of.isoformat(), 'start': two_months_before(args.as_of).isoformat(),
            'source': 'nessie_sandbox', 'bill_schedule_source': 'nessie_sandbox' if bill_readable else 'app_simulation'}
        with store.connect() as conn:
            conn.execute('SELECT pg_advisory_xact_lock(50315892)')
            current = conn.execute('SELECT accounts,scenario FROM cp_nessie_links WHERE owner_key=%s FOR UPDATE', (owner,)).fetchone()
            if current != (owned, scenario):
                raise ValueError('User mapping changed; preserve journal and review before resuming')
            conn.execute('UPDATE cp_nessie_links SET scenario=%s WHERE owner_key=%s', (store.Jsonb(new_scenario), owner))
        print(user['label'], 'history and future schedule complete', flush=True)
    print('Confirmed journal records:', dict(Counter(x['resource'] for x in seeded.state['operations'].values() if x.get('status') == 'confirmed')))
    if not args.apply:
        print('DRY RUN: nothing created or modified')


if __name__ == '__main__':
    try:
        main()
    except httpx.HTTPStatusError as exc:
        safe = re.sub(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}|[0-9a-fA-F]{24}', '[ID]', exc.response.text)
        print('Provider failure:', exc.response.status_code, safe[:1100], flush=True)
        sys.exit(1)
    except Exception as exc:
        print('Seeding stopped:', type(exc).__name__, '(private details suppressed; journal preserved)', flush=True)
        sys.exit(1)
