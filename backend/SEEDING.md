# CreditPilot — Seed the Nessie Sandbox

**Owner:** Bindhu (Nessie integration). Everyone else consumes the generated IDs and API responses.

## 1. Get the latest code

From PowerShell, inside the Flutter repository:

```powershell
git pull origin main
Copy-Item backend\.env.example backend\.env
notepad backend\.env
```

Set `NESSIE_API_KEY` to **your own** Nessie sandbox key in `backend/.env`. Keep the HTTPS URL unchanged:

```dotenv
NESSIE_API_KEY=YOUR_PRIVATE_KEY
NESSIE_BASE_URL=https://prod-api.nessieisreal.com
```

Do not push the real `.env`, and rotate a key that has already been exposed in chat.

## 2. Preview then insert

```powershell
py backend\scripts\seed_nessie.py
py backend\scripts\seed_nessie.py --apply
py backend\scripts\seed_nessie.py --verify
```

**Only `--apply` inserts data**. The default command previews the data without contacting Nessie. On success, the script writes `backend/seed_manifest.json` with the real sandbox IDs. This file is deliberately Git-ignored and can be shared directly with teammates if they use the same sandbox; it contains no API key.

### Records created in Nessie

| Record | Demo value |
|---|---|
| Sarah (fictional customer) | Primary app user |
| Jamie (fictional customer) | Trusted partner |
| Sarah checking | $500 |
| Sarah savings | $1,200 |
| Card A | $750 balance |
| Card B | $200 balance |
| Shared demo checking | $2,000 (owned by Sarah in Nessie) |
| Jamie checking | $350 |
| Grocery, fuel, cafe | 3 fictional merchant records |
| Rent due +3 days | $400 |
| Electricity due +7 days | $150 |
| Internet due +12 days | $100 |

The three upcoming bills total $650, versus $500 in checking: a projected $150 shortfall.

### NOT written to Nessie

The script puts these fictional values in `seed_manifest.json.app_scenario` for our own backend: credit limits, rewards rates, statement close offsets, utilization targets, simulated partner association, a proposed unusual $850 payment and an unexpected $1,000 emergency.

Nessie account types are not equivalent to live credit bureau reports; and **shared_demo is not a real jointly owned account**. Nessie doesn't approve, pause or intercept all external bank payments.

### No transactions yet

This **Stage 1** seeder sets initial balances directly and creates unpaid future bills. It does **not** create deposits, purchases, credit-card repayments or transfers. That deliberately avoids accidentally changing the seeded balances before we've verified how the sandbox applies transaction writes. Stage 2 can add a realistic transaction history after verification.

## 3. Team dependencies

1. **Bindhu:** runs the seed on one Nessie key and verifies all records exist.
2. **Parvathi:** receives the manifest IDs and builds FastAPI `GET /accounts` and `GET /forecast` responses from Nessie.
3. **Rohith:** uses the exact balances, bill due dates and app-only card metadata to calculate risk and rewards.
4. **Ajit:** uses deterministic backend results in Gemini explanations and builds Auth0-protected access.

**Do not run `--apply` from four different computers**. Run it once with the shared demo sandbox key, then distribute the generated manifest IDs securely. Re-running using the same local manifest is designed to reuse records. `--apply` in a new directory with a new manifest generates a separate dataset.

**Definition of done:** Bindhu confirms `--verify` succeeds; Flutter displays the seeded checking and savings accounts and three future bills from a backend response.
