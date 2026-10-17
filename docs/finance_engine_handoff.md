# Finance engine handoff

Rohith owns the pure Python calculations in `backend/app/domain` and their unit tests.
They return sandbox decision previews and an execution eligibility check. They do
not call Nessie, run a server, authorize users, store consent, or move money.

## Run the engine tests and demo

Requires Python 3.11 or later. From the repository root on Windows:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m app.domain.demo
```

On macOS/Linux, use `.venv/bin/python` instead. The engine has no runtime
dependencies outside the standard library. API dependencies belong in Parvathi's
backend requirements file. `pytest.ini` currently discovers Rohith's unit tests;
run `python -m pytest tests` when other teams add integration/security suites.

## Ownership and repository findings

The initial repository commit was `cc413a5`. It contains Flutter only. At kickoff,
GitHub reported no open PRs. The individual task files update the original plan:
Bindhu owns the backend Nessie HTTP adapter as well as Flutter; Parvathi owns
FastAPI routes, normalized context assembly, storage, actions and the scheduler;
Ajit owns authentication, partner authorization, Gemini and integration QA.

Existing `lib/services/api_service.dart` calls `/api/...` with floating point
dollar amounts and silently returns local fixtures after errors. The Cards,
Joint and Emergency screens also contain static demo content. These are integration
gaps, not a working authenticated backend. Bindhu and Parvathi should move to the
agreed `/v1/...` routes, integer cents, explicit fixture labels and error states.
Rohith's branch leaves their Flutter files and API implementation to their owners.

## Proposed contract choices for team review

The source documents disagree in several places. This branch uses these explicit
choices until the team settles its API contract:

| Topic | Branch contract |
| --- | --- |
| Domain models | One shared `backend/app/domain/models.py`; routes import these rather than duplicate the math |
| Money | Strict integer cents; reject floats, booleans and numeric strings |
| Rates | Integer basis points; 2900 means 29%, 300 means 3% |
| Card fields | `limit_cents`, `balance_cents`, `projected_charges_cents`, `close_estimate` |
| Result metrics | Object keyed by metric name, matching Parvathi's task-file example |
| AutoPay target amount | `target_payment_cents`; Ajit's illustrative `theoretical_payment_cents` maps to this |
| Protected amounts | `protected_obligations_cents` includes bills and other approved outflows |
| Percentages on JSON wire | Decimal strings such as `"50.00"`; money stays integer cents |
| Dates and time | ISO dates; timezone-aware timestamps normalized to UTC |
| Errors | Invalid domain input raises `ValueError`; API validates/maps to 422 and handles authentication errors separately |

`MoneyContext.from_dict()` parses the canonical JSON context. Dataclasses can also
be constructed directly. `DecisionResult.to_dict()` produces JSON-safe values.
Metrics and reason-code evidence carry the exact numbers used in explanations.
Scenario IDs identify calculation content; they are not payment authorization or
idempotency tokens. `source_flags` must be truthfully set by the API.

The adapter must normalize all accounts in a context to the same fresh snapshot
window. `captured_at` represents that snapshot; `evaluated_at` is explicitly supplied
by the trusted caller's UTC clock. It defaults to `captured_at` only for reproducible
fixtures. Live callers, especially the scheduler, must always supply current
`evaluated_at`; otherwise a freshness check has no current clock to compare with.

## Function handoffs

| Parvathi's route or service | Rohith's function |
| --- | --- |
| `GET /v1/bills/forecast` | `forecast_bills(context, horizon=14, account_id=None)` |
| `POST /v1/bills/savings-options` | `preview_savings_move(context, source_id, target_id, amount_cents, horizon=14)` |
| `POST /v1/cards/recommend` | `recommend_cards(context, purchase_cents, category, merchant_id=None, preference="rewards", max_utilization_bps=None)` |
| `POST /v1/cards/autopay/preview` | `preview_autopay(context, card_id, target_bps, max_payment_cents, source_account_id=None, horizon=14)` |
| Scheduler before action gate | `recheck_autopay_plan(context_fresh, plan, max_snapshot_age_seconds=300)` |
| `POST /v1/joint/precheck` | `precheck_joint_payment(context, actor, payee, amount_cents, rule_config)` |
| `POST /v1/emergency/evaluate` | `evaluate_emergency(context, scenario_cost_cents, reserve_cents=None, account_ids=None, allow_savings=False, horizon=14)` |

When there are multiple checking accounts, Bills and AutoPay require an explicit
account ID. A large unrelated account cannot fund the selected account's bills.
Emergency can aggregate only explicitly permitted accounts; savings use is opt-in.

## Accounting rules and limitations

- `available_cents` is already net of provider holds. Mark a pending bill or cash
  flow `reflected_in_available=true` only if the adapter confirms it is included.
  Projected card charges are additional to the card's posted balance.
- Paid/canceled bills and reflected debits are excluded. An approved outflow with
  `bill_id` represents that same bill and is counted once. Duplicate IDs, duplicate
  scheduled references and mismatched linked amounts are rejected. A later payment
  schedule cannot postpone a bill's due date. Partial linked bill payments require
  API normalization into remaining obligations before calling the engine.
- Forecasts cover today through `horizon - 1` days. Overdue unpaid obligations are
  protected today. Uncertain deposits and past unposted deposits are excluded.
  Day-end balances include confirmed dated income, but same-day debit-before-credit
  lows drive safe spending because settlement order is unknown.
- AutoPay protects the minimum projected cash balance over at least 14 days and
  through the estimated close date. This is deliberately more conservative than
  stopping at the next deposit. Total horizon is limited to 366 days. The cap cannot
  exceed current spendable cash or posted card debt, even when pending charges
  increase the theoretical paydown. Optional savings transfers are never assumed.
- Checking account reserves and the context safety buffer are additive. Emergency's
  explicit `reserve_cents` replaces the context buffer and adds selected account
  reserves. It uses current cash minus commitments, not previously computed forecast
  balances; future deposits do not fund an emergency occurring now.
- Reward caps describe remaining eligible purchase spend, not remaining reward
  dollars. Excess spend earns the configured fallback rate. Rewards round half up
  to cents. Missing rules disable a recommendation rather than invent benefits.
  Preferences explicitly choose rewards first or utilization first. Promo dates and
  merchant-specific eligibility must be normalized into current rules by the caller.
- The target balance is floored to cents so rounding cannot exceed the selected
  utilization target. Display percentages have two decimals; target feasibility
  uses exact integers. No credit score or reporting-date outcome is predicted.
- Joint history is scoped to the selected account. Rules explain new payees and
  configurable amount thresholds; unusual does not mean fraudulent. These checks
  do not verify JWT identity or approve a partner review. External payments cannot
  be blocked. Payee text is data, never an instruction to Gemini.
- An incomplete snapshot disables all decision options and executable paydown
  eligibility. A fixture can show preview options; provider actions still require
  fresh live cash, API ownership/consent checks and idempotency.

## AutoPay recheck responsibilities

Construct `AutoPayPlan` from persisted, authenticated consent, not a client payload.
Set `consent_valid` only after Ajit's scope/ownership verification. Store the exact
approved amount, cap, run time, consent expiry, close estimate and state. A recheck
never increases or silently reduces the approved amount: changed affordability
returns `NEEDS_REVIEW` and zero permitted payment. Only a valid scheduled plan with
fresh live cash can return `READY_FOR_ACTION_GATE`; that is not an executed payment.

If a plan is already represented among approved outflows, provide its trusted
`reserved_outflow_id`. The recheck replaces that plan's matching reservation while
protecting other schedules. The database must bind that reservation to the plan;
the engine cannot establish ownership of an arbitrary matching ID. Missing or
mismatched reservations fail closed. Recheck, claim, consent/cancellation checks,
idempotency and the provider write must run under Parvathi's coordinated transaction
and locking policy. No pure function can make a provider write exactly once.

## Shared fixture and expected values

`fixtures/seed_profile_v1.json` is one versioned source with common data and named
scenario overrides. Overrides replace entire fields. Separate scenarios avoid
mixing the different balances used by the demo examples. All IDs are simulated;
Bindhu should maintain real sandbox ID mappings separately and preserve fixtures
for offline tests. Refresh live demo dates deliberately, together with expected tests.

| Scenario | Expected result |
| --- | --- |
| Bills | 45000 checking minus 62000 bills = 17000 shortfall |
| Cards | 12000 purchase earns 360 vs 240 cents; first card reaches 87% |
| AutoPay | 46000 theoretical, 25000 safe, projected utilization 50%, target unreachable |
| Joint | New payee and 85000 amount produce explicit flags and policy-based review |
| Emergency | 200000 funds minus 120000 bills leaves 80000; 100000 cost has 20000 gap |

Generate all five complete response samples with `python -m app.domain.demo`.
Bindhu can use these responses for her typed fixture repository; Ajit can feed their
`explanation_inputs` into grounded templates or Gemini. No backend route or live
provider integration is claimed by these standalone tests.
