"""
Nessie API Integration Adapter for CreditPilot AI / SpendAhead.
Owner: Bindhu (UI + Nessie API Integration)

Provides an asynchronous HTTPX-backed client for Capital One's Nessie API sandbox,
normalizing sandbox accounts, bills, purchases, and transfer executions.
"""

from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx

logger = logging.getLogger("creditpilot.integrations.nessie")

# Default Nessie endpoint
DEFAULT_NESSIE_BASE_URL = "http://api.nessieisreal.com"


class NessieError(Exception):
    """Base exception for all Nessie adapter errors."""

    def __init__(self, message: str, status_code: Optional[int] = None, details: Optional[dict] = None) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.details = details or {}


class NessieAuthError(NessieError):
    """Raised when authentication with Nessie fails (HTTP 401/403)."""


class NessieNotFoundError(NessieError):
    """Raised when a requested Nessie resource is not found (HTTP 404)."""


class NessieValidationError(NessieError):
    """Raised when invalid request parameters or payloads are rejected (HTTP 400)."""


class NessieConnectionError(NessieError):
    """Raised when network, DNS, or connection errors occur while reaching Nessie."""


class NessieUnavailableError(NessieError):
    """Raised when the Nessie sandbox is offline or returns 5xx."""


def mask_sensitive_url(url: str) -> str:
    """Sanitizes URLs by masking API keys in query parameters."""
    return re.sub(r"([?&]key=)[^&]+", r"\1***MASKED***", str(url))


def _resolve_env_var(name: str, default: str = "") -> str:
    """Helper to check os.getenv first, then parse local .env file if available."""
    val = os.getenv(name)
    if val:
        return val
    candidates = [
        Path(".env"),
        Path(__file__).resolve().parents[3] / ".env",
        Path(__file__).resolve().parents[2] / ".env",
    ]
    for candidate in candidates:
        if candidate.is_file():
            try:
                with open(candidate, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            k, v = line.split("=", 1)
                            if k.strip() == name:
                                return v.strip().strip("'\"")
            except Exception:
                pass
    return default


class NessieClient:
    """
    Asynchronous client for Nessie API sandbox.
    Normalizes sandbox data into CreditPilot domain models with 'nessie' source tags.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        timeout: float = 10.0,
        client: Optional[httpx.AsyncClient] = None,
        fallback_fixture_path: Optional[str | Path] = None,
    ) -> None:
        self.api_key = api_key or _resolve_env_var("NESSIE_API_KEY", "")
        self.base_url = (base_url or _resolve_env_var("NESSIE_BASE_URL", DEFAULT_NESSIE_BASE_URL)).rstrip("/")
        self.timeout = timeout
        self._external_client = client
        self.fallback_fixture_path = fallback_fixture_path

    def _get_client(self) -> httpx.AsyncClient:
        if self._external_client is not None:
            return self._external_client
        return httpx.AsyncClient(timeout=self.timeout)

    def _auth_params(self, extra_params: Optional[dict[str, Any]] = None) -> dict[str, Any]:
        params: dict[str, Any] = {}
        if self.api_key:
            params["key"] = self.api_key
        if extra_params:
            params.update(extra_params)
        return params

    def _now_iso(self) -> str:
        return datetime.now(timezone.utc).isoformat()

    async def _request(
        self,
        method: str,
        path: str,
        *,
        params: Optional[dict[str, Any]] = None,
        json_body: Optional[dict[str, Any]] = None,
    ) -> Any:
        """Internal helper with sanitized logging and typed exception handling."""
        url = f"{self.base_url}{path}"
        all_params = self._auth_params(params)
        sanitized_url = mask_sensitive_url(url)
        logger.debug("Nessie %s request to %s", method, sanitized_url)

        client = self._get_client()
        should_close = self._external_client is None

        try:
            response = await client.request(
                method,
                url,
                params=all_params,
                json=json_body,
                headers={"Accept": "application/json", "Content-Type": "application/json"},
            )
        except httpx.TimeoutException as exc:
            logger.error("Nessie request timeout for %s", sanitized_url)
            raise NessieConnectionError(f"Nessie timeout connecting to {sanitized_url}") from exc
        except httpx.RequestError as exc:
            logger.error("Nessie network error for %s: %s", sanitized_url, str(exc))
            raise NessieConnectionError(f"Network error contacting Nessie: {exc}") from exc
        finally:
            if should_close:
                await client.aclose()

        if response.status_code in (401, 403):
            logger.warning("Nessie authentication failed: %d", response.status_code)
            raise NessieAuthError("Invalid or missing Nessie API key", status_code=response.status_code)

        if response.status_code == 404:
            raise NessieNotFoundError(f"Resource not found at {sanitized_url}", status_code=404)

        if response.status_code == 400:
            try:
                body = response.json()
            except Exception:
                body = {"raw": response.text}
            raise NessieValidationError("Nessie rejected invalid payload", status_code=400, details=body)

        if response.status_code >= 500:
            raise NessieUnavailableError(
                f"Nessie sandbox server error: {response.status_code}", status_code=response.status_code
            )

        if not response.is_success:
            raise NessieError(
                f"Nessie error: {response.status_code} {response.text}", status_code=response.status_code
            )

        try:
            return response.json()
        except Exception:
            return response.text

    # -------------------------------------------------------------------------
    # 1. Accounts
    # -------------------------------------------------------------------------
    async def get_customer_accounts(self, customer_id: str) -> list[dict[str, Any]]:
        """
        Fetch customer accounts from Nessie and normalize them.
        GET /customers/{customer_id}/accounts?key={key}
        """
        try:
            raw_data = await self._request("GET", f"/customers/{customer_id}/accounts")
            if not isinstance(raw_data, list):
                raw_data = [raw_data] if isinstance(raw_data, dict) else []

            normalized = []
            for item in raw_data:
                norm = self._normalize_account(item)
                normalized.append(norm)
            return normalized
        except (NessieConnectionError, NessieUnavailableError) as err:
            logger.warning("Nessie unavailable (%s); attempting fixture fallback", err)
            fallback = self._load_fallback_accounts()
            if fallback is not None:
                return fallback
            raise

    async def get_account_by_id(self, account_id: str) -> dict[str, Any]:
        """
        Fetch a single account by ID from Nessie and normalize it.
        GET /accounts/{account_id}?key={key}
        """
        raw = await self._request("GET", f"/accounts/{account_id}")
        return self._normalize_account(raw)

    def _normalize_account(self, raw: dict[str, Any]) -> dict[str, Any]:
        balance_float = float(raw.get("balance", 0.0))
        return {
            "account_id": raw.get("_id") or raw.get("account_id", ""),
            "type": raw.get("type", "Checking"),
            "nickname": raw.get("nickname", "Account"),
            "rewards": raw.get("rewards", 0),
            "balance": balance_float,
            "balance_cents": int(round(balance_float * 100)),
            "account_number_masked": raw.get("account_number", "•••• 0000"),
            "source": "nessie",
            "fetched_at": self._now_iso(),
            "_raw": raw,
        }

    # -------------------------------------------------------------------------
    # 2. Bills
    # -------------------------------------------------------------------------
    async def get_account_bills(self, account_id: str) -> list[dict[str, Any]]:
        """
        Fetch bills associated with an account from Nessie and normalize them.
        GET /accounts/{account_id}/bills?key={key}
        """
        try:
            raw_data = await self._request("GET", f"/accounts/{account_id}/bills")
            if not isinstance(raw_data, list):
                raw_data = [raw_data] if isinstance(raw_data, dict) else []

            normalized = []
            for item in raw_data:
                normalized.append(self._normalize_bill(item, account_id))
            return normalized
        except (NessieConnectionError, NessieUnavailableError) as err:
            logger.warning("Nessie bills unavailable (%s); attempting fallback", err)
            fallback = self._load_fallback_bills()
            if fallback is not None:
                return fallback
            raise

    def _normalize_bill(self, raw: dict[str, Any], default_account_id: str = "") -> dict[str, Any]:
        amount_float = float(raw.get("payment_amount", 0.0))
        return {
            "bill_id": raw.get("_id") or raw.get("bill_id", ""),
            "account_id": raw.get("account_id", default_account_id),
            "status": raw.get("status", "pending"),
            "payee": raw.get("payee") or raw.get("nickname", "Unknown Payee"),
            "nickname": raw.get("nickname", ""),
            "payment_date": raw.get("payment_date", ""),
            "recurring_date": raw.get("recurring_date", 0),
            "payment_amount": amount_float,
            "payment_amount_cents": int(round(amount_float * 100)),
            "source": "nessie",
            "fetched_at": self._now_iso(),
            "_raw": raw,
        }

    # -------------------------------------------------------------------------
    # 3. Purchases
    # -------------------------------------------------------------------------
    async def get_account_purchases(self, account_id: str) -> list[dict[str, Any]]:
        """
        Fetch purchases for a given account from Nessie.
        GET /accounts/{account_id}/purchases?key={key}
        """
        try:
            raw_data = await self._request("GET", f"/accounts/{account_id}/purchases")
            if not isinstance(raw_data, list):
                raw_data = [raw_data] if isinstance(raw_data, dict) else []

            normalized = []
            for item in raw_data:
                normalized.append(self._normalize_purchase(item, account_id))
            return normalized
        except (NessieConnectionError, NessieUnavailableError) as err:
            logger.warning("Nessie purchases unavailable (%s); attempting fallback", err)
            fallback = self._load_fallback_purchases()
            if fallback is not None:
                return fallback
            raise

    def _normalize_purchase(self, raw: dict[str, Any], default_account_id: str = "") -> dict[str, Any]:
        amount_float = float(raw.get("amount", 0.0))
        return {
            "purchase_id": raw.get("_id") or raw.get("purchase_id", ""),
            "account_id": raw.get("payer_id") or raw.get("account_id", default_account_id),
            "merchant_id": raw.get("merchant_id", ""),
            "purchase_date": raw.get("purchase_date", ""),
            "amount": amount_float,
            "amount_cents": int(round(amount_float * 100)),
            "status": raw.get("status", "completed"),
            "medium": raw.get("medium", "balance"),
            "description": raw.get("description", ""),
            "source": "nessie",
            "fetched_at": self._now_iso(),
            "_raw": raw,
        }

    # -------------------------------------------------------------------------
    # 4. Transfers (Sandbox Execution)
    # -------------------------------------------------------------------------
    async def create_supported_transfer(
        self,
        *,
        source_id: str,
        destination_id: str,
        amount_cents: int,
        description: str = "CreditPilot safe transfer",
    ) -> dict[str, Any]:
        """
        Execute a sandbox transfer between two accounts in Nessie.
        POST /accounts/{source_id}/transfers?key={key}
        Payload:
        {
            "medium": "balance",
            "payee_id": destination_id,
            "amount": amount_dollars,
            "transaction_date": YYYY-MM-DD,
            "description": description
        }
        Returns normalized transfer result or raises typed error.
        """
        if amount_cents <= 0:
            raise NessieValidationError("Transfer amount must be greater than zero", status_code=400)

        amount_dollars = round(amount_cents / 100.0, 2)
        today_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

        payload = {
            "medium": "balance",
            "payee_id": destination_id,
            "amount": amount_dollars,
            "transaction_date": today_date,
            "description": description,
        }

        raw_response = await self._request("POST", f"/accounts/{source_id}/transfers", json_body=payload)

        # Nessie returns 201 Created with transfer metadata
        created_obj = raw_response.get("objectCreated", raw_response)
        transfer_id = created_obj.get("_id", f"transfer_{int(datetime.now(timezone.utc).timestamp())}")

        return {
            "transfer_id": transfer_id,
            "status": created_obj.get("status", "executed"),
            "medium": "balance",
            "source_id": source_id,
            "destination_id": destination_id,
            "amount": amount_dollars,
            "amount_cents": amount_cents,
            "description": description,
            "transaction_date": today_date,
            "executed_in_sandbox": True,
            "source": "nessie",
            "fetched_at": self._now_iso(),
            "_raw": raw_response,
        }

    # -------------------------------------------------------------------------
    # 5. Customer Lookup
    # -------------------------------------------------------------------------
    async def get_customer_by_id(self, customer_id: str) -> dict[str, Any]:
        """
        Fetch customer record from Nessie.
        GET /customers/{customer_id}?key={key}
        """
        raw = await self._request("GET", f"/customers/{customer_id}")
        return {
            "customer_id": raw.get("_id", customer_id),
            "first_name": raw.get("first_name", ""),
            "last_name": raw.get("last_name", ""),
            "address": raw.get("address", {}),
            "source": "nessie",
            "fetched_at": self._now_iso(),
            "_raw": raw,
        }

    # -------------------------------------------------------------------------
    # 6. Fallback helpers (Truthful read-only demo fallback)
    # -------------------------------------------------------------------------
    def _find_fixture_path(self) -> Optional[Path]:
        if self.fallback_fixture_path:
            p = Path(self.fallback_fixture_path)
            if p.exists():
                return p

        # Search standard fixture locations
        candidates = [
            Path(__file__).resolve().parents[3] / "fixtures" / "seed_profile_v1.json",
            Path("fixtures/seed_profile_v1.json").resolve(),
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    def _load_fallback_accounts(self) -> Optional[list[dict[str, Any]]]:
        path = self._find_fixture_path()
        if not path:
            return None
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            accounts = data.get("accounts", [])
            for a in accounts:
                a["source"] = "demo_fixture"
                a["fetched_at"] = self._now_iso()
            return accounts
        except Exception as e:
            logger.error("Failed to load fallback accounts from fixture: %s", e)
            return None

    def _load_fallback_bills(self) -> Optional[list[dict[str, Any]]]:
        path = self._find_fixture_path()
        if not path:
            return None
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            bills = data.get("bills", [])
            for b in bills:
                b["source"] = "demo_fixture"
                b["fetched_at"] = self._now_iso()
            return bills
        except Exception as e:
            logger.error("Failed to load fallback bills from fixture: %s", e)
            return None

    def _load_fallback_purchases(self) -> Optional[list[dict[str, Any]]]:
        path = self._find_fixture_path()
        if not path:
            return None
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            purchases = data.get("purchases", [])
            for p in purchases:
                p["source"] = "demo_fixture"
                p["fetched_at"] = self._now_iso()
            return purchases
        except Exception as e:
            logger.error("Failed to load fallback purchases from fixture: %s", e)
            return None
