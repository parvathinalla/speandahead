"""Only actual sandbox records may become assignable slots."""
import hashlib
import pytest
from scripts.import_nessie_slots import validate


def data():
    key = 'fictional-test-key'
    manifest = {'sandbox_fingerprint': hashlib.sha256(key.encode()).hexdigest()[:8],
                'customers': {'0': 'a' * 24}, 'accounts': {'0': {'checking': 'b' * 24}}}
    return key, manifest, [{'_id': 'a' * 24}], [{'_id': 'b' * 24, 'customer_id': 'a' * 24}]


def test_import_retains_actual_provider_references():
    key, manifest, customers, accounts = data()
    assert validate(manifest, customers, accounts, key) == [(0, 'a' * 24, {'checking': 'b' * 24})]


@pytest.mark.parametrize('fault', ['missing_customer', 'wrong_owner', 'wrong_sandbox'])
def test_import_rejects_unverified_records(fault):
    key, manifest, customers, accounts = data()
    if fault == 'missing_customer':
        customers = []
    elif fault == 'wrong_owner':
        accounts[0]['customer_id'] = 'c' * 24
    else:
        key = 'another-sandbox'
    with pytest.raises(ValueError):
        validate(manifest, customers, accounts, key)
