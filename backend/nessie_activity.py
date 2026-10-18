"""Read-only, account-scoped Nessie transaction normalization and short caching."""
import asyncio
from datetime import date
from decimal import Decimal, InvalidOperation
import time
from fastapi import HTTPException


async def refresh_bills(gateway, mapping):
    if mapping.get('bill_source') != 'nessie_sandbox':
        return
    account = mapping['ids']['accounts']['checking']
    if not hasattr(gateway, '_bill_cache'):
        gateway._bill_cache = {}
    cached = gateway._bill_cache.get(account)
    if cached and cached[0] > time.monotonic():
        raw = cached[1]
    else:
        raw = await gateway.request('GET', '/accounts/' + account + '/bills')
        if not isinstance(raw, list):
            raise HTTPException(502, 'Unexpected Nessie bill response')
        for bill in raw:
            if bill.get('account_id') and bill['account_id'] != account:
                raise HTTPException(502, 'Nessie bill ownership mismatch')
        gateway._bill_cache[account] = (time.monotonic() + 20, raw)
    metadata = {bill.get('nickname'): bill for bill in mapping.get('app_bills', {}).values()}
    mapping['past_bills'] = [bill for bill in raw if bill.get('status') == 'completed']
    mapping['app_bills'] = {bill['_id']: {
        **metadata.get(bill.get('nickname'), {}), **bill, 'bill_id': bill['_id'],
        'account_id': account, 'source': 'nessie_sandbox',
        'upcoming_payment_date': bill.get('upcoming_payment_date') or bill.get('payment_date'),
    } for bill in raw if bill.get('status') in ('pending', 'recurring')}


def normalize(raw, account_id, account_kind, resource):
    returned_account = raw.get('account_id') or raw.get('payer_id') or raw.get('payee_id')
    if returned_account and returned_account != account_id:
        raise HTTPException(502, 'Nessie activity ownership mismatch')
    identity = raw.get('_id')
    if not isinstance(identity, str) or not identity:
        raise HTTPException(502, 'Nessie transaction identifier missing')
    try:
        amount = Decimal(str(raw['amount']))
        if not amount.is_finite() or amount < 0:
            raise ValueError()
        when = str(raw.get('transaction_date') or raw.get('purchase_date') or '')[:10]
        date.fromisoformat(when)
    except (KeyError, ValueError, InvalidOperation):
        raise HTTPException(502, 'Invalid Nessie transaction amount/date') from None
    description = str(raw.get('description') or resource.title())
    pieces = description.split(' | ', 2)
    seeded = description.startswith('CP2M-') and len(pieces) == 3
    return {'id': identity, 'account_id': account_id, 'account_kind': account_kind,
            'merchant': pieces[2] if seeded else description[:100],
            'category': pieces[1] if seeded else ('income' if resource == 'deposits' else 'other'),
            'direction': 'credit' if resource == 'deposits' else 'debit',
            'amount': float(amount), 'date': when, 'status': raw.get('status', 'unknown'),
            'source': 'nessie_sandbox', 'record_type': resource}


async def history(gateway, mapping):
    # Caller verifies account ownership against the authenticated customer first.
    fingerprint = tuple(sorted(mapping['ids']['accounts'].items()))
    if not hasattr(gateway, '_history_cache'):
        gateway._history_cache = {}
        gateway._history_locks = {}
    cached = gateway._history_cache.get(fingerprint)
    if cached and cached[0] > time.monotonic():
        return cached[1]
    lock = gateway._history_locks.setdefault(fingerprint, asyncio.Lock())
    async with lock:
        cached = gateway._history_cache.get(fingerprint)
        if cached and cached[0] > time.monotonic():
            return cached[1]
        gate = asyncio.Semaphore(4)
        async def fetch(kind, account, resource):
            async with gate:
                try:
                    raw = await gateway.request('GET', '/accounts/' + account + '/' + resource)
                except HTTPException as exc:
                    # Nessie's legacy PurchaseCreate omits a required read-model
                    # status. Surface coverage warnings instead of fabricating rows.
                    if resource == 'purchases' and exc.status_code == 502:
                        return [], ['Nessie purchase history is unreadable for an account; other activity is shown.']
                    raise
                if not isinstance(raw, list):
                    raise HTTPException(502, 'Unexpected Nessie activity response')
                return [normalize(row, account, kind, resource) for row in raw], []
        batches = await asyncio.gather(*(fetch(kind, account, resource)
            for kind, account in fingerprint for resource in ('withdrawals', 'deposits', 'purchases')))
        transactions = [row for rows, _ in batches for row in rows]
        transactions.sort(key=lambda row: (row['date'], row['id']), reverse=True)
        result = {'transactions': transactions, 'source': 'nessie_sandbox',
                  'warnings': sorted({warning for _, warnings in batches for warning in warnings})}
        if len(gateway._history_cache) >= 8:
            oldest = next(iter(gateway._history_cache))
            gateway._history_cache.pop(oldest, None)
            gateway._history_locks.pop(oldest, None)
        gateway._history_cache[fingerprint] = (time.monotonic() + 20, result)
        return result
