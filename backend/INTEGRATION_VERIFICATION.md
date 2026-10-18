# Integration verification — 2026-10-18

Changes are on `feature/tigerdata-nessie-joint-store`, uncommitted. No merge or push occurred. Original Flutter changes are preserved in the retained `codex-preserve-flutter-before-tigerdata` stash and already match this branch.

## Live database evidence

Successfully connected with TLS to **db-97301**, host `xjqzw54az9.xye00m46ck.tsdb.cloud.timescale.com`, port **31416**, database **tsdb**, schema **public**.

Exact application row counts, verified after two backend startup cycles:

| Table | Rows |
|---|---:|
| cp_nessie_links | 4 |
| cp_joint_accounts | 1 |
| cp_joint_payments | 0 |
| cp_nessie_slots | 500 |

The other public objects observed are PostgreSQL monitoring views (`pg_buffercache`, `pg_buffercache_numa`, `pg_stat_statements`, `pg_stat_statements_info`); their dynamic counts are not application data.

The uploaded mapping table had no constraints and used JSON. The applied transaction preserved its row, converted accounts to JSONB, added an owner primary key, customer unique index, NOT NULL requirements, and hash/object/checking shape constraints. Missing joint tables and their payment index were created using the PR schema. Repeated startup was successful. No synthetic portfolio tables were created.

## Mapping validation

The one row has a valid 64-character hex owner hash and points to an existing Nessie customer. All six referenced accounts exist. Five accounts (`checking`, `savings`, `card_a`, `card_b`, `joint_demo`) belong to that customer. `partner_checking` belongs to another customer. The original JSON remains intact; the backend now excludes that legacy partner reference from owned accounts and checks customer ownership on returned banking records. Explicit joint access still requires administrator-provisioned membership.

The complete uploaded mapping does not exactly match any bulk-manifest slot. It must not be treated as a proven Auth0 binding based on hash shape alone. A genuine login is still needed to confirm that the stored hash matches the verified subject. No live user token was available in this session.

All 500 manifest customers and 500 checking accounts were verified against live Nessie customer/account lists, including customer ownership and sandbox fingerprint. Their actual IDs were imported atomically into `cp_nessie_slots`, without balances, passwords, or invented Auth0 subjects. These are unassigned banking slots, not authenticated users. No customers were created. The import defaults to dry-run validation and supports `--apply`; conflicting existing slots roll back the import.

The uploaded `scenario` JSON contains app bills and card metadata. Authenticated account loading now reuses that metadata instead of returning empty app scenarios. Banking balances continue to come from Nessie.

The user supplied the three existing Auth0 test User IDs and authorized Parvathi as primary, Haswanth as dependent, and Bindhu as individual. Personal slots 0, 1, and 2 are now linked to those users; separate slot 3 backs the joint account. Both joint members' personal checking accounts are allowed recipients. All four slots were revalidated against live Nessie before the transaction. The original uploaded mapping belongs to none of these three supplied hashes and was preserved, explaining the four mapping rows.

Provisioning was rerun successfully to verify idempotency. Read-only administrative checks resolved all three mappings, validated customer ownership via actual Nessie reads, assembled dashboard data, and checked each expected joint role. Backend restart retained the rows. The test users have the seeded checking-only portfolios; extra cards, savings, bills, and banking transactions were not invented. The primary can set an approval threshold after login; until then dependent requests require approval. No payment records were created.

The private plan is `backend/private/provision_users.json` (ignored by Git); generic provisioning and verification scripts take `--plan` and never require passwords. These checks use administrator-supplied subject IDs directly, not genuine Auth0 tokens; real browser login/JWT still needs end-to-end confirmation. The supplied public Flutter web client ID is saved in backend/private/flutter.public.json alongside the public domain and audience. No passwords or API keys are included in that Flutter file.

SQLite contains actions with zero rows and no joint tables. There was no joint data to copy. Ordinary actions and AutoPay plans remain SQLite-backed.

## Configuration and code

Private backend/.env now selects AUTH_MODE=auth0, DEMO_DATA_MODE=nessie, DEMO_STORE=sqlite, JOINT_STORE=tigerdata, PAYMENT_MODE=simulate. GEMINI_API_KEY is still absent; assessment fails closed to primary review.

Code fixes cover PostgreSQL dictionary-row reservations; transactional limit/proposal changes; legacy table schema upgrade; mapping validation for UUID/legacy IDs; partner-account isolation; ownership validation in dashboard reads and offline provisioning; safe diagnostics and startup smoke scripts.

## Verification

- 176 backend tests passed with service credentials disabled. Banking calls and JWT key retrieval are mocked; JWT tests use actual locally signed RS256 tokens.
- 13 Flutter tests passed. Flutter analysis exited successfully with 98 informational findings.
- Live backend startup and restart passed; /health returned 200 and /api/dashboard rejected unauthenticated and spoofed-subject requests with 401.
- Live PostgreSQL aggregate reservation lookup passed. Counts persisted as (4, 1, 0).
- No Nessie transfer was executed. Live approval persistence, concurrent payment execution, and an authenticated Flutter dashboard remain unverified because no genuine user session was available. Saved membership persistence is not evidence of saved payment approval persistence.

## Run from the repository root

```powershell
.\.venv\Scripts\python.exe backend/scripts/verify_nessie_tigerdata.py
.\.venv\Scripts\python.exe backend/scripts/smoke_tigerdata_startup.py
.\.venv\Scripts\python.exe backend/scripts/verify_provisioned_users.py --plan backend/private/provision_users.json
.\.venv\Scripts\python.exe -m uvicorn main:app --app-dir backend --host 127.0.0.1 --port 8765 --reload
```

The configured FastAPI port is 8765 because another local service already occupies 8000. In a second terminal, use the prepared public Flutter configuration:

```powershell
.\backend\scripts\run_web.ps1
```

Open http://localhost:8080. The app redirects through Auth0 Universal Login; no credentials are embedded in Flutter.

Register http://localhost:8080 as the Auth0 callback/logout/web origin. Sign in as the intended user and inspect GET /api/dashboard in the browser network panel. A login without a mapping must return onboarding/409, never another user's accounts. Keep PAYMENT_MODE=simulate. Parvathi and Haswanth should see their primary/dependent joint membership; Bindhu should see individual banking only.

## Four-card portfolios and Gemini update

At the user's request, four fictional credit-card accounts were added for each of Parvathi, Haswanth, and Bindhu: Everyday Rewards, Travel Rewards, Dining Rewards, and Fuel Rewards. Twelve actual Nessie account IDs were retrieved from the provider and verified against their respective customers. Their TigerData mappings, slot inventory, and private bulk manifest were updated. Starting balances live in Nessie; card limits, issuer names, rewards, and statement timing are explicitly app demo metadata. No payments, purchases, or transfers were executed by this provisioning operation.

All three portfolios now have one checking account and four credit cards. A read-only rerun found all four existing cards per user without creating duplicates. The provisioning script uses deterministic nicknames to recover created accounts, rather than blindly retrying an ambiguous POST.

Live administrative checks passed all 12 card ownership validations and all 12 AutoPay previews. AutoPay was fixed to support checking-only funding without a savings account and to reject savings-transfer scenarios when no savings account exists. Backend regression suite: 179 passed.

GEMINI_API_KEY is now present. Google accepted model listing but rejected gemini-2.5-flash generation with HTTP 404 because it is no longer available to new users. Google's recommended gemini-3.8-flash passed the actual structured payment-assessment integration with ai_used=true. GEMINI_MODEL was updated privately to gemini-3.8-flash and the backend restarted. No private key was printed.

The live row check during this work reported (slots, mappings, joint memberships, payments) = (500, 4, 1, 1). The payment record was created through the user's app activity; provisioning did not create payment requests or execute transfers. Earlier zero-payment counts above record the earlier verification state.

## Chat reliability and latency update

The chat previously allocated only 520 output tokens, did not set a low thinking level, accepted truncated responses, and lost follow-up conversation context whenever persistent memory was off. Updated the Gemini chat prompt to answer the question directly, reuse the prior purchase target, and request missing monthly savings rather than inventing a timeline. Gemini 3.8 Flash uses supported low thinking (minimal was rejected by the provider); output budget is now 1600 tokens, with thought parts filtered and MAX_TOKENS responses rejected. Timeouts and rate limits now have distinct user messages and sanitized server diagnostics.

Flutter sends a bounded recent conversation for the active session; it is not persisted unless memory was explicitly enabled. The backend continues to fetch balances independently and treats client conversation as untrusted context. Agent consent/history/notes now load through one database connection, concurrently with Nessie account retrieval, with blocking database calls moved off the async event loop.

Live Gemini laptop test: initial 900-dollar purchase question returned a complete answer in 2.94 seconds; follow-up asking how many months retained the target and asked for monthly savings capacity in 4.05 seconds. These are sampled provider timings, not guaranteed end-to-end latency. No user banking identifiers or actual account snapshot were sent in this smoke test; context was fictional. Latest backend suite: 183 passed.

## Login loading performance

The user reported a delay after clicking Continue in Auth0. Public resource sampling showed Auth0 discovery at 0.44 seconds and the SDK at 0.14 seconds; these timings do not measure actual password validation or the complete callback. The debug Flutter bootstrap itself took 2.66 seconds in a sample, before application startup and account checks.

The app previously waited for /api/me and /api/joint/membership sequentially before opening the shell. They now run concurrently, and simultaneous token lookups share an in-flight SDK request. The SDK's authentication/HTTP timeouts are explicitly bounded at 10 seconds rather than leaving the UI waiting on long defaults. Session restoration and account-loading stages have separate status labels and non-secret timing logs in debug/profile mode. Token persistence and JWT validation are unchanged.

A branded HTML startup placeholder is visible before Flutter's first frame. For local performance testing, use the optimized profile build instead of the debug web-server build:

```powershell
.\backend\scripts\run_web.ps1
```

This builds into build/web-profile and serves localhost:8080. Use -SkipBuild for subsequent restarts without code changes. Profile mode is a local performance configuration; production still requires an HTTPS deployment. The complete real-user Auth0 callback time still requires another sign-in after rebuilding. Flutter regression tests: 13 passed.

## Two-month intensive demo data — final verification

Live Nessie reads verified the following for each of Parvathi, Haswanth, and Bindhu: one checking account, four credit cards, 276 transactions (264 withdrawals and 12 deposits), six upcoming bills, and two loans. History covers 2026-08-18 through 2026-10-17. Across the three users this is 828 readable transactions, 18 upcoming bills, and six loans. All account ownership checks passed, and transaction coverage returned zero warnings. The existing joint membership remains Parvathi primary and Haswanth dependent; Bindhu remains individual.

The seeded history includes daily card spending, payroll deposits, card statement payments and credits, and historical bill/EMI payments. Spending and historical bill payments use readable Nessie withdrawal records with category and merchant descriptions. Purchase creation exposed a provider read-schema error, so these records are not presented as provider purchase objects. Upcoming bills are actual pending Nessie bills fetched by the application. Completed historical bills are excluded from future-bill forecasts; their payment history remains in transactions. Monthly income is labeled demo payroll metadata, while spending summaries are derived from verified provider history.

The private journal records all created IDs and deterministic operation markers. A completed rerun reused confirmed resources without duplicating them. The user explicitly approved deleting only four failed purchase probes and one failed completed-bill test; those five newly created test records were removed. Original records, all 828 verified transactions, and all 18 upcoming bills were preserved. No Nessie transfers or real banking payments were executed.

The final backend regression suite passed 187 tests; Flutter passed 13 tests. The optimized web build is served on port 8080 and FastAPI on port 8765. Read-only provider verification can be repeated with:

```powershell
.\.venv\Scripts\python.exe backend/scripts/verify_demo_history.py
```

## Team integration — 2026-10-18

Merged origin/main at 398e6fe into the TigerData/Nessie feature branch. Main already contains Bindhu's Flutter/joint work, Rohith's finance/location/push work, and Ajit's cards/AutoPay update (eaaf4a1). Resolved three overlapping edits while retaining both the trip planner and concise advisor, live Nessie activity, the updated cashflow screen, and request-specific connection errors. Login retries cannot overlap, and connection errors no longer claim that an existing account is unlinked.

Combined regression checks: 206 backend tests and 14 Flutter tests passed. No real banking transfer or notification delivery was triggered by these tests. Browser login remains a separate user-session check. Private environment settings and identity provisioning plans remain ignored by Git.
