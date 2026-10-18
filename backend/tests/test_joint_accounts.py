"""Real consent/state transitions; fake Nessie and Gemini, no external writes."""
import json

import pytest
from fastapi import Header
from fastapi.testclient import TestClient

import main
import joint_accounts as joint
from scripts.link_joint_account import provision

ACCOUNT = 'a' * 24
PAYEE = 'b' * 24
RECIPIENTS = [{'id': 'store', 'name': 'Sandbox store', 'account_id': PAYEE}]
PRIMARY = 'auth0|primary'
DEPENDENT = 'auth0|dependent'


class FakeGateway:
    def __init__(self):
        self.calls = []
        self.fail = False

    async def account(self, identity):
        assert identity == ACCOUNT
        return {'_id': identity, 'balance': 2000}

    async def transfer(self, payer, payee, value):
        self.calls.append((payer, payee, value))
        if self.fail:
            raise TimeoutError()
        return {'objectCreated': {'_id': 'c' * 24}}

    async def request(self, method, path):
        assert method == 'GET' and path == '/transfers/' + 'c' * 24
        payer, payee, value = self.calls[-1]
        return {'_id': 'c' * 24, 'payer_id': payer, 'payee_id': payee,
                'amount': value, 'status': 'executed'}


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'SQLITE', tmp_path / 'joint.sqlite3')
    monkeypatch.setattr(main, 'AUTH_MODE', 'auth0')
    monkeypatch.setattr(main, 'DATA_MODE', 'nessie')
    monkeypatch.setattr(main, 'PAYMENT_MODE', 'nessie')
    async def actor(x_test_user: str = Header(DEPENDENT)):
        return x_test_user
    async def review(merchant, reason):
        return {'suspicious': False, 'reason': 'No text indicators found', 'ai_used': True}
    main.app.dependency_overrides[main.actor] = actor
    monkeypatch.setattr(joint, 'assess_payment', review)
    fake = FakeGateway()
    monkeypatch.setattr(main.app.state, 'nessie', fake, raising=False)
    connection = main.db()
    try:
        provision(connection, ACCOUNT, PRIMARY, DEPENDENT, 'Family checking', RECIPIENTS)
    finally:
        connection.close()
    with TestClient(main.app) as c:
        yield c, fake
    main.app.dependency_overrides.clear()


def headers(user):
    return {'X-Test-User': user}


def create(client, amount=600):
    response = client.post('/api/joint/payments', json={
        'amount': amount, 'recipient_id': 'store', 'reason': 'Weekly shopping', 'confirmed': True})
    assert response.status_code == 200, response.text
    return response.json()


def limit(client, amount=500):
    return client.post('/api/joint/settings', json={'amount': amount}, headers=headers(PRIMARY))


def execute(client, identity):
    return client.post(f'/api/joint/payments/{identity}/execute', json={'confirmed': True})


def test_individual_account_cannot_read_or_act(client):
    c, _ = client
    assert c.get('/api/joint/membership', headers=headers('auth0|stranger')).json() == {'has_joint_account': False}
    assert c.get('/api/joint/payments', headers=headers('auth0|stranger')).status_code == 403
    assert c.post('/api/joint/settings', json={'amount': 100}, headers=headers('auth0|stranger')).status_code == 403


def test_only_primary_sets_limit_and_dependent_cannot_self_approve(client):
    c, _ = client
    assert c.post('/api/joint/settings', json={'amount': 500}).status_code == 403
    assert limit(c).status_code == 200
    payment = create(c)
    assert payment['status'] == 'awaiting_primary'
    identity = payment['payment_id']
    assert execute(c, identity).status_code == 409
    assert c.post(f'/api/joint/payments/{identity}/decision', json={'approve': True}).status_code == 403
    assert c.post(f'/api/joint/payments/{identity}/decision', json={'approve': True},
                  headers=headers('auth0|stranger')).status_code == 403


def test_primary_inbox_and_dependent_status_then_nessie_send_once(client):
    c, fake = client
    limit(c)
    identity = create(c)['payment_id']
    assert c.get('/api/joint/payments').json()['payments'][0]['can_decide'] is False
    assert c.get('/api/joint/payments', headers=headers(PRIMARY)).json()['payments'][0]['can_decide'] is True
    assert c.post(f'/api/joint/payments/{identity}/decision', json={'approve': True},
                  headers=headers(PRIMARY)).json()['status'] == 'approved'
    assert fake.calls == []
    item = c.get('/api/joint/payments').json()['payments'][0]
    assert item['approved_by_primary'] and item['can_execute']
    assert c.post(f'/api/joint/payments/{identity}/execute', json={'confirmed': True},
                  headers=headers(PRIMARY)).status_code == 403
    assert execute(c, identity).json()['status'] == 'submitted'
    assert execute(c, identity).json()['previous_request']
    assert fake.calls == [(ACCOUNT, PAYEE, 600.0)]


def test_decline_never_sends_and_cannot_be_reversed(client):
    c, fake = client
    identity = create(c)['payment_id']
    endpoint = f'/api/joint/payments/{identity}/decision'
    assert c.post(endpoint, json={'approve': False}, headers=headers(PRIMARY)).json()['status'] == 'declined'
    assert c.post(endpoint, json={'approve': True}, headers=headers(PRIMARY)).status_code == 409
    assert execute(c, identity).status_code == 409
    assert fake.calls == []


@pytest.mark.parametrize('value,expected', [(499.99, 'ready'), (500, 'ready'), (500.01, 'awaiting_primary')])
def test_primary_configured_threshold_boundary(client, value, expected):
    c, _ = client
    limit(c)
    assert create(c, value)['status'] == expected


def test_unset_limit_requires_review_and_lowered_limit_rechecks(client):
    c, _ = client
    assert create(c, 10)['status'] == 'awaiting_primary'
    limit(c, 100)
    identity = create(c, 80)['payment_id']
    limit(c, 50)
    assert execute(c, identity).status_code == 409
    assert c.get('/api/joint/payments').json()['payments'][0]['status'] == 'awaiting_primary'


def test_suspicious_small_payment_requires_primary(client, monkeypatch):
    c, _ = client
    limit(c)
    async def suspicious(*args):
        return {'suspicious': True, 'reason': 'Possible advance-fee request', 'ai_used': True}
    monkeypatch.setattr(joint, 'assess_payment', suspicious)
    assert create(c, 10)['status'] == 'awaiting_primary'


def test_unknown_nessie_outcome_is_not_retried(client):
    c, fake = client
    limit(c)
    identity = create(c, 10)['payment_id']
    fake.fail = True
    assert execute(c, identity).status_code == 502
    assert execute(c, identity).json()['status'] == 'unknown'
    assert len(fake.calls) == 1


def test_funds_confirmation_and_recipient_guards(client):
    c, fake = client
    limit(c, 10000)
    identity = create(c, 2500)['payment_id']
    assert execute(c, identity).status_code == 409
    assert c.post(f'/api/joint/payments/{identity}/execute', json={}).status_code == 400
    assert c.post('/api/joint/payments', json={'amount': 10, 'recipient_id': 'forged',
        'reason': 'test', 'confirmed': True}).status_code == 400
    assert fake.calls == []


def test_pending_transfers_reserve_funds(client):
    c, fake = client
    limit(c, 10000)
    assert execute(c, create(c, 1500)['payment_id']).status_code == 200
    assert execute(c, create(c, 600)['payment_id']).status_code == 409
    assert len(fake.calls) == 1


def test_reconciliation_matches_receipt_and_releases_local_reserve(client):
    c, _ = client
    limit(c, 10000)
    identity = create(c, 1500)['payment_id']
    assert execute(c, identity).status_code == 200
    assert c.post(f'/api/joint/payments/{identity}/reconcile').json()['status'] == 'completed'
    assert execute(c, identity).status_code == 409
    assert execute(c, create(c, 600)['payment_id']).status_code == 200


def test_mismatched_receipt_does_not_release_funds(client):
    c, fake = client
    limit(c, 10000)
    identity = create(c, 1500)['payment_id']
    assert execute(c, identity).status_code == 200
    async def forged(*args):
        return {'_id': 'c' * 24, 'payer_id': ACCOUNT, 'payee_id': PAYEE,
                'amount': 1, 'status': 'executed'}
    fake.request = forged
    assert c.post(f'/api/joint/payments/{identity}/reconcile').status_code == 502
    assert execute(c, create(c, 600)['payment_id']).status_code == 409


def test_sandbox_send_requires_server_mode(client, monkeypatch):
    c, fake = client
    limit(c)
    identity = create(c, 10)['payment_id']
    monkeypatch.setattr(main, 'PAYMENT_MODE', 'simulate')
    assert execute(c, identity).status_code == 409
    assert fake.calls == []


def test_primary_does_not_request_dependent_approval(client):
    c, _ = client
    response = c.post('/api/joint/payments', headers=headers(PRIMARY), json={
        'amount': 900, 'recipient_id': 'store', 'reason': 'Purchase', 'confirmed': True})
    assert response.json()['status'] == 'ready'
    assert c.get('/api/joint/payments').json()['payments'] == []


def test_admin_does_not_allow_role_escalation_or_duplicate_pair(client):
    c, _ = client
    connection = main.db()
    try:
        with pytest.raises(ValueError, match='already belongs'):
            provision(connection, 'd' * 24, DEPENDENT, 'auth0|third', 'Other', RECIPIENTS)
    finally:
        connection.close()


def test_money_precision_and_negative_limits_rejected(client):
    c, _ = client
    assert limit(c, -1).status_code == 422
    assert limit(c, 0.001).status_code == 422
    assert c.post('/api/joint/payments', json={'amount': 10.001, 'recipient_id': 'store',
        'reason': 'test', 'confirmed': True}).status_code == 422


def test_gemini_missing_key_falls_back_to_review(monkeypatch):
    import asyncio
    monkeypatch.delenv('GEMINI_API_KEY', raising=False)
    result = asyncio.run(joint.assess_payment('Merchant', 'Reason'))
    assert result['suspicious'] and not result['ai_used']


def test_linking_accepts_uuid_accounts(tmp_path):
    import sqlite3
    connection = sqlite3.connect(tmp_path / 'uuid.sqlite3')
    account = '0d1a7380-d173-4d02-96af-b352fb188c17'
    recipient = '72be6052-3049-4b2e-8e88-7451b3eda087'
    try:
        provision(connection, account, PRIMARY, DEPENDENT, 'Joint',
                  [{'id': 'recipient', 'name': 'Test recipient', 'account_id': recipient}])
        assert connection.execute('SELECT account_id FROM joint_accounts').fetchone()[0] == account
    finally:
        connection.close()


@pytest.mark.parametrize('value', ['', '../accounts', 'not-an-id', '0d1a7380-d173-4d02-96af-b352fb188c17/extra'])
def test_linking_rejects_invalid_account_ids(value):
    from scripts.link_joint_account import valid_account_id
    assert not valid_account_id(value)
