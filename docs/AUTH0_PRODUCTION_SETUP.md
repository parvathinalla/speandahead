# CreditPilot Auth0 — existing users, login-only deployment

The app uses the official auth0_flutter SDK, Auth0 Universal Login and OAuth Authorization Code + PKCE. Passwords and client secrets are NEVER collected by Flutter. FastAPI validates signed access tokens (RS256 JWKS, issuer, audience, expiry and subject).

Important: implementation is complete in code, but live Auth0 is not active until you configure a tenant. Nessie data is fictional. This is NOT a real regulated banking system.

## 1. Auth0 Dashboard configuration

Open https://manage.auth0.com

1. Applications > APIs > Create API. Name it CreditPilot API; identifier example: https://api.creditpilot.example ; choose RS256. Copy the exact identifier as AUTH0_AUDIENCE.
2. Applications > Applications > Create Application > Single Page Web Application. Name CreditPilot Web. Copy the tenant Domain and Web Client ID. Client secret must NEVER be embedded into Flutter.
3. Create a second application of type Native. Name CreditPilot Mobile; copy Native Client ID.
4. Use an Auth0 database connection configured for existing, administrator-provisioned users; enable **Disable Sign Ups** under Authentication > Database > your connection > Settings. Restrict enabled connections on each CreditPilot application so another connection cannot allow open signups. Do not use social login if you need to prohibit unprovisioned users. Enable email verification, attack protections and MFA policies appropriate for financial information.
5. In the Auth0 Applications settings, select RS256 and OIDC-conformant mode.

Web SPA callback, logout and allowed web origins (development):
- http://localhost:8080
- http://127.0.0.1:8080

Add your actual HTTPS production web frontend URL to all three lists when deploying. For example, https://app.YOUR-OWN-DOMAIN.com. Never use wildcard callback or logout domains.

Native app callback AND logout URLs with current platform identifiers:
- Android: creditpilot://YOUR_AUTH0_DOMAIN/android/com.example.creditpilot_mobile/callback
- iOS: creditpilot://YOUR_AUTH0_DOMAIN/ios/com.example.creditpilotMobile/callback

Replace YOUR_AUTH0_DOMAIN without https://. These match the currently committed Android app ID, iOS bundle ID and custom URI scheme creditpilot. Update all of them after switching to company-owned store identifiers. Verified App Links / Universal Links are preferred for production mobile release.

## 2. Local backend Auth0 mode

Keep existing private Nessie key in backend/.env. Set:

    APP_ENV=development
    AUTH_MODE=auth0
    PAYMENT_MODE=simulate
    AUTH0_DOMAIN=YOUR_AUTH0_DOMAIN
    AUTH0_AUDIENCE=https://api.creditpilot.example
    CORS_ORIGINS=http://localhost:8080,http://127.0.0.1:8080

Restart FastAPI after updating the file:

    python -m uvicorn main:app --app-dir backend --host 127.0.0.1 --port 8765

## 3. Flutter Web login (no public signup)

Use the project root in PowerShell. Replace example values:

    flutter pub get
    flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8765 --dart-define=AUTH0_DOMAIN=YOUR_AUTH0_DOMAIN --dart-define=AUTH0_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID --dart-define=AUTH0_AUDIENCE=https://api.creditpilot.example

The welcome screen presents only **Log In**, using hosted Auth0 (not an app password form). After sign-in, the app checks GET /api/me with an Auth0 JWT. Unmapped users see a safe account-linking screen rather than anyone else's balances. Removing the Flutter signup button does not block Auth0 registrations by itself: enable Disable Sign Ups on the Auth0 database connection and verify it in the hosted Universal Login page.

A temporary local ONLY debug mode is available when the backend uses AUTH_MODE=demo:

    flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8765 --dart-define=DEV_DEMO_AUTH=true

This debug switch does NOT test Auth0 and is ineffective in release builds.

## 4. Explicitly link one fictional Nessie sandbox per authenticated user

After an administrator creates the Auth0 user, log in once and note the Account ID from the app's account-linking screen. On the trusted backend machine:

    python backend/scripts/link_user_sandbox.py --subject "auth0|YOUR_USER_SUB"

Optional invited partner:

    python backend/scripts/link_user_sandbox.py --subject "auth0|OWNER_SUB" --partner-sub "auth0|PARTNER_SUB"

Return to Flutter, click Check account connection. The script creates a SHA256-named file with strict owner_sub checking under backend/private/tenants. Other users cannot read the mapped data.

A second user must get a separate Nessie seed with DIFFERENT account IDs. The script rejects reuse of any bank account ID across two Auth0 users. No public API can assign a bank account.

Do not confuse this with real bank onboarding. Actual consumer banking requires regulated data providers, explicit consent and proper account ownership proof.

## 5. Native mobile

For Android build, pass Gradle property auth0Domain (see android/app/build.gradle.kts) and Flutter compile flags AUTH0_DOMAIN, AUTH0_NATIVE_CLIENT_ID and AUTH0_AUDIENCE. In Flutter, set API_BASE_URL to an HTTPS backend URL reachable from the device.

For iOS verify app bundle ID and creditpilot callback in Xcode. Mobile SDK stores credentials in OS-managed secure storage. Verify callback links, logout, renewal and a signed release build on real devices before store distribution. Never ship an Android release signed using debug keystore.

## 6. Production backend

Environment must use:

    APP_ENV=production
    AUTH_MODE=auth0
    PAYMENT_MODE=simulate
    AUTH0_DOMAIN=YOUR_AUTH0_DOMAIN
    AUTH0_AUDIENCE=https://api.creditpilot.example
    CORS_ORIGINS=https://app.YOUR-OWN-DOMAIN.com
    TENANT_MANIFEST_DIR=/app/private/tenants
    DB_PATH=/app/private/creditpilot.sqlite3

Mount tenant data and action database on protected server-only persistent storage. Provide NESSIE_API_KEY from secret manager. Serve HTTPS via trusted reverse proxy. Production startup rejects demo auth, non-HTTPS / wildcard CORS, and Nessie transfer mode.

Before deploying at scale, replace demo SQLite with a production transactional DB, implement migrations/backups, per-user consent-based bank linking, security monitoring and proper account ownership verification. Current financial data and joint approvals are simulations.

## 7. Verify

- The CreditPilot app shows Log In only; public Sign Up and Create Account are absent.
- Auth0 database connection has Disable Sign Ups enabled for every database connection exposed to the app; test that public registration is rejected.
- Administrator-provisioned Auth0 user logs in via Universal Login; the callback works.
- Refresh browser to restore authenticated session.
- Logout clears app financial screens and removes the bearer token source.
- Correctly signed JWT with expected audience gets authenticated.
- Wrong issuer, audience, signature or expired JWT returns HTTP 401.
- New user has onboarding only, never Sarah's sandbox data.
- Only owner with independently provisioned manifest sees own accounts.
- Only the invited authenticated partner can approve a joint proposal.
- API CORS in production is HTTPS-only with specific origins.
- Frontend has no server API keys, Auth0 client secret or demo passwords.

Official SDK: https://pub.dev/packages/auth0_flutter
Official Auth0 web quickstart: https://auth0.com/docs/quickstart/spa/flutter

## Important distinction: Nessie accounts vs Auth0 logins

Nessie customer/account records have no bank login credentials. The 500-account Nessie seeder creates banking sandbox records, **not** 500 Auth0 identities. For this login-only prototype, an administrator must provision authorized Auth0 identities and establish one-to-one backend ownership mappings before a user sees their Nessie accounts. Do not ask customers to enter bank credentials into CreditPilot. A real bank app or financial-data connection would require bank-approved identity and consent integrations.
