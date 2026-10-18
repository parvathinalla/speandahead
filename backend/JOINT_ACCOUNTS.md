# Joint account workflow

Only explicitly linked joint members see the Joint tab. Individual portfolio
records (including an old `joint_demo` account) do not establish joint ownership.
Auth0 verifies identity; the app database maps the primary and dependent roles.
These are application permissions for a fictional Nessie sandbox account.

## Link a test pair

An operator must verify both users' Auth0 subject IDs and the joint-account
association before linking them. One joint account per user is currently supported.
The existing per-user portfolio mappings remain private and separate.

Create an ignored file `backend/private/joint_recipients.json`:

```json
[
  {
    "id": "store",
    "name": "Sandbox merchant",
    "account_id": "REPLACE_WITH_RECIPIENT_NESSIE_ACCOUNT_ID"
  }
]
```

From the repository root with the backend virtual environment active:

```powershell
python backend/scripts/link_joint_account.py --account-id JOINT_NESSIE_ACCOUNT_ID --primary-sub 'auth0|PRIMARY' --dependent-sub 'auth0|DEPENDENT' --recipients backend/private/joint_recipients.json
```

No role or account ID can be assigned through a public API. Provisioning rejects
duplicate assignments and self-pairs. It creates no remote accounts or transactions.
Each recipient is a Nessie **account**, suitable for the existing transfer API;
the display name may be a merchant. This is not Nessie's merchant purchase API.

Set these values in the ignored `backend/.env`, then restart the backend:

```dotenv
AUTH_MODE=auth0
DEMO_DATA_MODE=nessie
PAYMENT_MODE=nessie
```

Keep the existing Auth0 domain/audience, Nessie key, Gemini key and CORS origins.
`PAYMENT_MODE=nessie` also enables the existing savings-transfer path for subjects
explicitly allowed by `NESSIE_TRANSFER_ALLOWED_SUB`; it does not grant that path
to other users. The joint path uses its own membership authorization.

## Primary and dependent

The primary sets the threshold in the Joint tab. Amounts strictly above it require
approval; equal amounts do not. Until a limit is set, all dependent payments require
approval. Gemini assesses merchant and reason text on every proposal. Suspicious
or unavailable/invalid assessments require primary review even below the limit.
The app discloses that this text is sent to Gemini; account IDs and tokens are omitted.

Only the primary sees approval actions. The dependent sees their request status;
approval never sends money. The initiator must explicitly confirm the frozen amount
and recipient through "Proceed with payment". Changes require a new request. A
stricter limit is checked again before an unreviewed dependent payment can execute.
Primary-initiated payments do not require dependent approval.

The notification bell and activity list refresh every 10 seconds while the app is
open. This does not provide background push notifications or email. A declined
request cannot execute or be approved later.

## Submission and reconciliation

The proposal ID is the execution idempotency key. A durable processing state is
committed before the single outbound Nessie POST. Repeating execution returns its
existing state. Money uses integer cents in local storage. Pending, submitted and
unknown sends reserve funds, so multiple outstanding requests cannot overspend the
same observed balance. Funds are re-read immediately before submission.

"Submitted" does not mean settled. Use **Check bank status** to match the returned
Nessie transfer ID, payer, payee, amount and status. An `executed` or `cancelled`
receipt releases the conservative local reservation. It can temporarily reduce
available funds twice if Nessie has already debited a still-pending transfer.

If the POST times out or lacks a receipt, execution is marked `unknown` and never
automatically retried. A process crash can leave `processing` with the same
no-retry rule. An operator must inspect Nessie before correcting those records;
never create a replacement request to bypass an unknown outcome. Account/membership
changes also require operator maintenance. There is no automated settlement worker.

## Verification

```powershell
$env:PYTHONPATH = 'backend'
python -m pytest -q backend/tests
```

Tests fake Nessie/Gemini and verify role isolation, threshold boundaries, unavailable
reviews, decline, approval, balance guards, reconciliation and duplicate execution.
Live two-user Auth0/Gemini/Nessie verification needs the operator's actual linked
test pair and an explicitly confirmed sandbox payment.
