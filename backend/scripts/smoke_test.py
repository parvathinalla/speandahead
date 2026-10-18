#!/usr/bin/env python3
"""Read-only end-to-end smoke test for CreditPilot running at localhost:8000.

Prerequisites: seed_nessie.py --apply; uvicorn main:app --app-dir backend.
No transfers, plans, purchases or Nessie writes are made by this test.
"""
import argparse
import json
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError


def call(base, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = Request(base + path, data=data,
                  headers={"Content-Type": "application/json"},
                  method="POST" if data is not None else "GET")
    with urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--synthetic", action="store_true",
                        help="Verify labeled fictional data from run_local_demo.py")
    args = parser.parse_args()
    base = args.url.rstrip("/")
    passed = 0

    def check(label, condition):
        nonlocal passed
        print(("PASS " if condition else "FAIL ") + label)
        if not condition:
            raise RuntimeError("Smoke test failed: " + label)
        passed += 1

    health = call(base, "/health")
    check("Backend health", health.get("status") == "ok")
    if args.synthetic:
        check("Synthetic demo mode", health.get("data_mode") == "synthetic")
        check("No provider writes", health.get("payment_mode") == "simulate")
    else:
        check("Local sandbox seed exists", health.get("seed_manifest_present") is True)

    dashboard = call(base, "/api/dashboard")
    accounts = dashboard.get("accounts", [])
    expected_source = "synthetic_banking_demo" if args.synthetic else "nessie_sandbox"
    check("Expected demo accounts", len(accounts) >= (4 if args.synthetic else 6))
    check("Balances have expected provenance", all(x.get("source") == expected_source for x in accounts))
    check("Bills explicitly simulated", dashboard["data_sources"]["bills"] ==
          ("synthetic_banking_demo" if args.synthetic else "local_app_simulation"))

    bill = call(base, "/api/bills/forecast", {"horizon_days": 14})
    check("Forecast matches total itemized bills",
          round(sum(x["amount"] for x in bill["upcoming_bills"]), 2) ==
          round(bill["total_bills_due"], 2))

    purchase_a = call(base, "/api/cards/evaluate",
                      {"purchase_amount": 100, "purchase_category": "groceries",
                       "merchant_name": "Fresh Fields Market"})
    purchase_b = call(base, "/api/cards/evaluate",
                      {"purchase_amount": 200, "purchase_category": "groceries",
                       "merchant_name": "Fresh Fields Market"})
    check("Card utilization responds to different purchases",
          purchase_b["cards"][0]["utilization_after_pct"] >
          purchase_a["cards"][0]["utilization_after_pct"])

    autopay = call(base, "/api/autopay/preview",
                   {"target_utilization_pct": 29, "assumed_savings_transfer": 0})
    check("AutoPay preview protects bill funds",
          autopay["recommended_payment_amount"] <= autopay["max_safe_payment_today"])
    check("AutoPay preview never executes a real payment",
          autopay["auto_execution"] is False)

    emergency = call(base, "/api/emergency/evaluate",
                     {"emergency_cost": 1000, "safety_buffer": 300})
    check("Emergency gap is nonnegative", emergency["potential_gap"] >= 0)

    joint = call(base, "/api/joint/evaluate",
                 {"amount": 850, "merchant": "Demo electronics"})
    check("Joint check is a pre-transaction simulation",
          joint["transaction_status"] == "NOT SUBMITTED")

    print("\nSUCCESS: " + str(passed) + " smoke checks passed.")
    print(("Synthetic demo balances" if args.synthetic else "Nessie balances") +
          " were read by FastAPI; no banking actions were executed.")


if __name__ == "__main__":
    try:
        main()
    except (HTTPError, URLError, RuntimeError, KeyError, ValueError) as exc:
        print("\nSMOKE TEST FAILED: " + str(exc), file=sys.stderr)
        print("Check backend/.env, seed manifest, network, and uvicorn logs.", file=sys.stderr)
        sys.exit(1)
