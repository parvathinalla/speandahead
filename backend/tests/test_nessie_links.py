"""Validate private mappings without connecting to banking services."""
import pytest
from nessie_links import NessieLinkStore


@pytest.mark.parametrize('customer,account', [
    ('a' * 24, 'b' * 24),
    ('0d1a7380-d173-4d02-96af-b352fb188c17', '72be6052-3049-4b2e-8e88-7451b3eda087'),
])
def test_supported_nessie_identifiers(customer, account):
    NessieLinkStore.validate_mapping(customer, {'checking': account})


@pytest.mark.parametrize('customer,accounts', [
    ('invented', {'checking': 'b' * 24}),
    ('a' * 24, []), ('a' * 24, {}),
    ('a' * 24, {'checking': '../other-account'}),
    ('a' * 24, {'checking': 'b' * 24, 'savings': 'b' * 24}),
])
def test_rejects_malformed_mappings(customer, accounts):
    with pytest.raises(ValueError):
        NessieLinkStore.validate_mapping(customer, accounts)


def test_legacy_partner_reference_is_not_an_owned_account():
    from types import SimpleNamespace
    from contextlib import nullcontext
    customer = 'a' * 24
    stored = {'checking': 'b' * 24, 'partner_checking': 'c' * 24}
    queries = []
    class Connection:
        def execute(self, query, params):
            queries.append(params)
            return SimpleNamespace(fetchone=lambda: (customer, stored, {'app_bills': {'bill': {}}, 'app_scenario': {}}))
    store = NessieLinkStore.__new__(NessieLinkStore)
    store.store = SimpleNamespace(connect=lambda: nullcontext(Connection()))
    result = store.get('auth0|verified-test-subject')
    assert result['accounts'] == {'checking': 'b' * 24}
    assert 'bill' in result['scenario']['app_bills']
    assert 'partner_checking' in stored  # persisted source data is preserved
    assert queries == [(NessieLinkStore.key('auth0|verified-test-subject'),)]


@pytest.mark.asyncio
async def test_nessie_ownership_mismatch_is_rejected(monkeypatch):
    import main
    from fastapi import HTTPException
    monkeypatch.setattr(main, 'using_nessie_links', lambda: True)
    class Gateway:
        async def account(self, identity):
            return {'_id': identity, 'customer_id': 'other-customer'}
    with pytest.raises(HTTPException) as error:
        await main.accounts(Gateway(), {'ids': {'customers': {'primary': 'expected-customer'},
                                               'accounts': {'checking': 'b' * 24}}})
    assert error.value.status_code == 502
