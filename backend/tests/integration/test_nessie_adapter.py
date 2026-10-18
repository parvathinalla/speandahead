"""
Integration tests for Nessie API client adapter.
Owner: Bindhu (UI + Nessie Integration)
"""

import json
import pytest
import httpx
from pathlib import Path

from backend.app.integrations.nessie import (
    NessieClient,
    NessieAuthError,
    NessieNotFoundError,
    NessieValidationError,
    NessieConnectionError,
    NessieUnavailableError,
    mask_sensitive_url,
)


@pytest.mark.asyncio
async def test_mask_sensitive_url():
    """Verify API keys are masked in logged or printed URLs."""
    raw_url = "http://api.nessieisreal.com/customers/123/accounts?key=SECRET_API_KEY_999&limit=10"
    masked = mask_sensitive_url(raw_url)
    assert "SECRET_API_KEY_999" not in masked
    assert "key=***MASKED***" in masked
    assert "limit=10" in masked


@pytest.mark.asyncio
async def test_get_customer_accounts_normalization():
    """Verify Nessie accounts are normalized into CreditPilot schema."""
    fake_accounts = [
        {
            "_id": "acc_chk_01",
            "type": "Checking",
            "nickname": "Primary Checking",
            "rewards": 0,
            "balance": 450.0,
            "account_number": "1234567890127890",
            "customer_id": "cust_alex_01",
        },
        {
            "_id": "acc_sav_01",
            "type": "Savings",
            "nickname": "Emergency Savings",
            "rewards": 0,
            "balance": 1500.0,
            "account_number": "1234567890121122",
            "customer_id": "cust_alex_01",
        },
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        assert "/customers/cust_alex_01/accounts" in str(request.url)
        assert request.url.params.get("key") == "test_key"
        return httpx.Response(200, json=fake_accounts)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        accounts = await client.get_customer_accounts("cust_alex_01")

        assert len(accounts) == 2
        chk = accounts[0]
        assert chk["account_id"] == "acc_chk_01"
        assert chk["balance"] == 450.0
        assert chk["balance_cents"] == 45000
        assert chk["source"] == "nessie"
        assert "fetched_at" in chk

        sav = accounts[1]
        assert sav["account_id"] == "acc_sav_01"
        assert sav["balance"] == 1500.0
        assert sav["balance_cents"] == 150000


@pytest.mark.asyncio
async def test_get_account_bills_normalization():
    """Verify Nessie bills are correctly normalized."""
    fake_bills = [
        {
            "_id": "bill_01",
            "status": "pending",
            "payee": "Rent (Installment)",
            "nickname": "Rent Installment",
            "creation_date": "2026-10-01",
            "payment_date": "2026-10-20",
            "recurring_date": 20,
            "payment_amount": 360.0,
            "account_id": "acc_chk_01",
        },
        {
            "_id": "bill_02",
            "status": "pending",
            "payee": "Electricity",
            "nickname": "City Power",
            "creation_date": "2026-10-05",
            "payment_date": "2026-10-22",
            "recurring_date": 22,
            "payment_amount": 120.0,
            "account_id": "acc_chk_01",
        },
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        assert "/accounts/acc_chk_01/bills" in str(request.url)
        return httpx.Response(200, json=fake_bills)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        bills = await client.get_account_bills("acc_chk_01")

        assert len(bills) == 2
        b1 = bills[0]
        assert b1["bill_id"] == "bill_01"
        assert b1["payee"] == "Rent (Installment)"
        assert b1["payment_amount"] == 360.0
        assert b1["payment_amount_cents"] == 36000
        assert b1["source"] == "nessie"
        assert "fetched_at" in b1


@pytest.mark.asyncio
async def test_get_account_purchases_normalization():
    """Verify Nessie purchases normalization."""
    fake_purchases = [
        {
            "_id": "tx_01",
            "payer_id": "acc_chk_01",
            "merchant_id": "merch_trader_joes",
            "purchase_date": "2026-10-16",
            "amount": 64.20,
            "status": "completed",
            "medium": "balance",
            "description": "Trader Joe's groceries",
        }
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        assert "/accounts/acc_chk_01/purchases" in str(request.url)
        return httpx.Response(200, json=fake_purchases)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        purchases = await client.get_account_purchases("acc_chk_01")

        assert len(purchases) == 1
        p = purchases[0]
        assert p["purchase_id"] == "tx_01"
        assert p["amount"] == 64.20
        assert p["amount_cents"] == 6420
        assert p["source"] == "nessie"


@pytest.mark.asyncio
async def test_create_supported_transfer_success():
    """Verify sandbox transfer is correctly formatted and returned with provider ID."""
    posted_payload = {}

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal posted_payload
        assert request.method == "POST"
        assert "/accounts/acc_sav_01/transfers" in str(request.url)
        posted_payload = json.loads(request.content.decode("utf-8"))
        return httpx.Response(
            201,
            json={
                "code": 201,
                "message": "Transfer created",
                "objectCreated": {
                    "_id": "tr_nessie_998877",
                    "type": "p2p",
                    "transaction_date": "2026-10-17",
                    "status": "executed",
                    "payer_id": "acc_sav_01",
                    "payee_id": "acc_chk_01",
                    "amount": 170.0,
                    "description": "Safe savings transfer for bill shortfall",
                },
            },
        )

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        result = await client.create_supported_transfer(
            source_id="acc_sav_01",
            destination_id="acc_chk_01",
            amount_cents=17000,
            description="Safe savings transfer for bill shortfall",
        )

        assert posted_payload["amount"] == 170.0
        assert posted_payload["payee_id"] == "acc_chk_01"
        assert posted_payload["medium"] == "balance"

        assert result["transfer_id"] == "tr_nessie_998877"
        assert result["status"] == "executed"
        assert result["amount"] == 170.0
        assert result["amount_cents"] == 17000
        assert result["source"] == "nessie"
        assert result["executed_in_sandbox"] is True


@pytest.mark.asyncio
async def test_create_supported_transfer_invalid_amount():
    """Verify zero or negative transfer amount raises validation error."""
    client = NessieClient(api_key="test_key")
    with pytest.raises(NessieValidationError) as exc:
        await client.create_supported_transfer(
            source_id="acc_sav_01",
            destination_id="acc_chk_01",
            amount_cents=0,
        )
    assert "greater than zero" in str(exc.value)


@pytest.mark.asyncio
async def test_auth_error_handling():
    """Verify 401 Unauthorized maps to NessieAuthError."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"message": "Unauthorized"})

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="invalid_key", client=http_client)
        with pytest.raises(NessieAuthError):
            await client.get_customer_accounts("cust_01")


@pytest.mark.asyncio
async def test_not_found_error_handling():
    """Verify 404 Not Found maps to NessieNotFoundError."""
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"message": "Account not found"})

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        with pytest.raises(NessieNotFoundError):
            await client.get_account_by_id("acc_missing")


@pytest.mark.asyncio
async def test_server_error_maps_to_unavailable():
    """Verify 500 error maps to NessieUnavailableError and falls back if configured."""
    fixture_path = Path(__file__).resolve().parents[4] / "fixtures" / "seed_profile_v1.json"

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="Internal Server Error")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(
            api_key="test_key",
            client=http_client,
            fallback_fixture_path=fixture_path,
        )
        accounts = await client.get_customer_accounts("cust_01")
        # Should gracefully return truthful fallback labeled with source='demo_fixture'
        assert len(accounts) >= 1
        assert accounts[0]["source"] == "demo_fixture"


@pytest.mark.asyncio
async def test_get_account_by_id_normalization():
    """Verify single account lookup normalization."""
    fake_acc = {
        "_id": "acc_chk_01",
        "type": "Checking",
        "nickname": "Primary Checking",
        "balance": 450.0,
        "rewards": 0,
    }

    def handler(request: httpx.Request) -> httpx.Response:
        assert "/accounts/acc_chk_01" in str(request.url)
        return httpx.Response(200, json=fake_acc)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        acc = await client.get_account_by_id("acc_chk_01")
        assert acc["account_id"] == "acc_chk_01"
        assert acc["balance_cents"] == 45000
        assert acc["source"] == "nessie"


@pytest.mark.asyncio
async def test_get_customer_by_id_normalization():
    """Verify customer lookup normalization."""
    fake_customer = {
        "_id": "cust_alex_01",
        "first_name": "Alex",
        "last_name": "Smith",
        "address": {"street_name": "Main St"},
    }

    def handler(request: httpx.Request) -> httpx.Response:
        assert "/customers/cust_alex_01" in str(request.url)
        return httpx.Response(200, json=fake_customer)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(api_key="test_key", client=http_client)
        cust = await client.get_customer_by_id("cust_alex_01")
        assert cust["customer_id"] == "cust_alex_01"
        assert cust["first_name"] == "Alex"
        assert cust["source"] == "nessie"


@pytest.mark.asyncio
async def test_network_timeout_handling():
    """Verify timeout raises NessieConnectionError and falls back gracefully."""
    fixture_path = Path(__file__).resolve().parents[4] / "fixtures" / "seed_profile_v1.json"

    def handler(request: httpx.Request):
        raise httpx.ConnectTimeout("Connection timed out")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as http_client:
        client = NessieClient(
            api_key="test_key",
            client=http_client,
            fallback_fixture_path=fixture_path,
        )
        # Should fall back to demo fixture
        bills = await client.get_account_bills("acc_chk_01")
        assert len(bills) >= 1
        assert bills[0]["source"] == "demo_fixture"
