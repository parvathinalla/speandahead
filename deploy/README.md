# CreditPilot HTTPS deployment (fictional banking sandbox only)

This directory contains the *deployment scaffold*: Caddy HTTPS + Flutter Web +
FastAPI, with private data on a persistent Docker volume. It is not deployed for
you until a server, real DNS, Auth0 tenant, keys, and release review are ready.

## 1. Prepare your server

Use a Linux VM with Docker Engine + Compose plugin, ports 80/443 available,
DNS A records for frontend and API domains pointing at the VM, and outbound
internet access to Auth0, Nessie and optional Gemini.

Copy deploy/.env.example to deploy/.env and edit it with actual values.
Never commit deploy/.env. It includes a PRIVATE Nessie sandbox key.

Set up the Auth0 Web SPA application:
- Allowed Callback URLs: https://APP_DOMAIN
- Allowed Logout URLs: https://APP_DOMAIN
- Allowed Web Origins: https://APP_DOMAIN
- Auth0 API identifier must equal the AUTH0_AUDIENCE in deploy/.env.
- Enable the desired signup connection, account verification and MFA policies.
- Web Client ID belongs to the SPA application, NOT the Native app.

## 2. Build & launch

From deploy/ on the remote server:

    docker compose --env-file .env -f compose.yaml config
    docker compose --env-file .env -f compose.yaml up -d --build
    docker compose --env-file .env -f compose.yaml ps

Caddy requests TLS certificates for both domain names. Test:
- https://APP_DOMAIN (Flutter login)
- https://API_DOMAIN/health (FastAPI health)

Do not serve the Flask/FastAPI container directly over public HTTP.
Only proxy exposes 80/443; web and api remain private to Compose networking.

## 3. Bind a logged-in user

New signup accounts start unlinked, by design. First perform Auth0 login on
the web app; copy the verified subject from its onboarding screen.

Upload a private Nessie demo seed to the container volume (example after
copying seed_manifest.json onto the server):

    docker compose -f compose.yaml cp /PATH/TO/seed_manifest.json api:/app/private/seed_manifest.json

Then run the offline operator-only binding command:

    docker compose -f compose.yaml exec api python scripts/link_user_sandbox.py --subject "auth0|USER_ID" --source /app/private/seed_manifest.json --tenant-dir /app/private/tenants

The owner can click Check account connection in Flutter. A second registered
user must have a DIFFERENT Nessie seed with six unique account IDs. The binding
script refuses reuse and does not offer API endpoints that take user-supplied
bank account IDs.

For a partner relationship pass --partner-sub "auth0|PARTNER_ID" during original
binding. Only the partner's verified bearer token can approve proposals.

## 4. Deploy security properties

- Auth0 Access Token signature, issuer, audience and expiry are checked server side.
- Per-user financial data is bound to the verified Auth0 subject; no shared
  Sarah/Jamie data for all signups.
- Demo login, non-HTTPS/wildcard browser origins and live Nessie transfers are
  prohibited by APP_ENV=production checks.
- All billing data is simulated; client is informed of its source.
- Secrets are not compiled into Flutter or copied into Docker images.
- Backend runs without root privileges and with a read-only container root.
- SQLite demo action records and tenant manifests live on private Docker volume.
- Production Caddy auto-enables TLS with DNS correctly configured.
- API responses have no-store and no-referrer headers.

Before broad consumer usage: managed PostgreSQL, migrations/backups, monitoring,
incident response, uptime/SLOs, authenticated consent-based bank account linking,
provider terms, privacy policy, account deletion and a security/compliance review.
Nessie is a fictional sandbox, not consumer bank connectivity.

## 5. Rollback and operational checks

    docker compose -f compose.yaml logs --tail 100 api
    docker compose -f compose.yaml logs --tail 100 web
    docker compose -f compose.yaml logs --tail 100 proxy

Back up private_data and Caddy volumes before upgrades. Do not dump private
manifest files or secrets into logs. Restore from tested backups.

Compose variables live in deploy/.env. Rebuilding web is required after
changing the PUBLIC Auth0 web client ID, audience, domain or API URL; restarting
api is required after changing its backend environment.
