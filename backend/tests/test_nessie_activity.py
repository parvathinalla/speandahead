from datetime import date
import pytest
from fastapi import HTTPException
from nessie_activity import normalize, history, refresh_bills
from scripts.seed_demo_history import plan_user, two_months_before


def test_two_month_plan_is_deterministic_and_has_no_transfers():
    user = {'slot': 0}
    first = plan_user(user, {'checking': 'checking'}, date(2026, 10, 18), 0)
    assert first == plan_user(user, {'checking': 'checking'}, date(2026, 10, 18), 0)
    operations, future, persona = first
    assert two_months_before(date(2026, 10, 18)) == date(2026, 8, 18)
    assert len({row['marker'] for row in operations}) == len(operations)
    assert sum(row['resource'] == 'withdrawals' for row in operations) == 264
    assert all(row['resource'] != 'transfers' for row in operations)
    assert len(future) == 6 and persona['income'] > 0


def test_normalization_preserves_actual_identity_and_enforces_ownership():
    row = {'_id': 'actual-provider-id', 'account_id': 'owned', 'amount': 12.5,
           'transaction_date': '2026-10-01', 'description': 'CP2M-test | groceries | Demo Market'}
    value = normalize(row, 'owned', 'card_a', 'withdrawals')
    assert value['id'] == row['_id'] and value['category'] == 'groceries'
    assert value['source'] == 'nessie_sandbox'
    with pytest.raises(HTTPException):
        normalize(row, 'someone-else', 'card_a', 'withdrawals')


@pytest.mark.asyncio
async def test_activity_cache_is_account_scoped_and_discloses_unreadable_purchases():
    class Gateway:
        def __init__(self): self.calls = []
        async def request(self, method, path):
            self.calls.append(path)
            if path.endswith('/purchases'):
                raise HTTPException(502, 'Nessie sandbox returned HTTP 400.')
            if path.endswith('/deposits'): return []
            account = path.split('/')[2]
            return [{'_id': account + '-transaction', 'account_id': account, 'amount': 10,
                     'transaction_date': '2026-10-01'}]
    g = Gateway()
    owner = {'ids': {'accounts': {'checking': 'owner'}}}
    other = {'ids': {'accounts': {'checking': 'other'}}}
    result = await history(g, owner)
    assert result['warnings'] and result['transactions'][0]['id'] == 'owner-transaction'
    count = len(g.calls)
    assert await history(g, owner) is result
    assert len(g.calls) == count
    assert (await history(g, other))['transactions'][0]['id'] == 'other-transaction'


@pytest.mark.asyncio
async def test_paid_bills_are_not_forecast_as_upcoming_payments():
    class Gateway:
        async def request(self, method, path):
            return [{'_id': 'paid', 'status': 'completed', 'account_id': 'owned', 'payment_date': '2026-09-01'},
                    {'_id': 'due', 'status': 'pending', 'account_id': 'owned', 'payment_date': '2026-10-21'}]
    mapped = {'bill_source': 'nessie_sandbox', 'ids': {'accounts': {'checking': 'owned'}}, 'app_bills': {}}
    await refresh_bills(Gateway(), mapped)
    assert list(mapped['app_bills']) == ['due']
    assert mapped['past_bills'][0]['_id'] == 'paid'
