# Device push notifications

CreditPilot uses Firebase Cloud Messaging (FCM) for the daily seven-day cashflow warning. The backend checks each registered user's upcoming bills after the configured local hour. It sends nothing when checking funds cover the forecast. It records a delivery before another cycle can notify that user again on the same day.

The Emergency screen also offers an opt-in hurricane budget simulation. The
phone supplies its location once, the backend immediately reduces it to a broad
region, and precise coordinates are discarded. The simulation compares a
fixed, visible $850 expense basket with checking, savings, upcoming bills, and
the user's safety reserve. It is a planning exercise, not an official forecast,
warning, or evacuation order. When enabled, the backend sends at most one
simulation notification per user per day.

The repository is connected to Firebase project `creditpilot-ai-rohith-2026`.
Its registered apps use Android package `com.example.creditpilot_mobile` and
iOS bundle ID `com.example.creditpilotMobile`.

The phone asks for notification permission after a successful Auth0 login. Tapping a cashflow notification opens the app on **Cashflow & Bills**, where the forecast offers **Move money from savings** and **Request money from a contact**.

## Firebase setup

1. Create Android and iOS apps in one Firebase project. Their package IDs must match the release IDs configured for this Flutter app.
2. The platform client files are committed at `android/app/google-services.json`
   and `ios/Runner/GoogleService-Info.plist`. Firebase documents these client
   identifiers as non-secret configuration. The backend credential below is
   private and must never be committed.

3. Create a Firebase service account for the backend and point Application Default Credentials to the downloaded JSON file. Keep the file outside the repository:

   ```text
   GOOGLE_APPLICATION_CREDENTIALS=C:/private/creditpilot/firebase-service-account.json
   FIREBASE_PROJECT_ID=your-project-id
   PUSH_NOTIFICATIONS_ENABLED=true
   PUSH_DAILY_HOUR_LOCAL=9
   # Development demo only. Production rejects nonzero values.
   PUSH_DEMO_INTERVAL_MINUTES=0
   HURRICANE_SIMULATION_ENABLED=true
   ```

4. For iOS, upload an APNs authentication key in Firebase Cloud Messaging settings and enable the Push Notifications capability for the Apple App ID and provisioning profile. The Xcode project already includes the remote-notification background mode and APS entitlement.

Run the API continuously to use its built-in 15-minute scheduler. A hosting platform's daily job can instead execute:

```powershell
python backend/scripts/send_daily_push_notifications.py
```

To run the opt-in hurricane simulation immediately during a demo:

```powershell
python backend/scripts/send_hurricane_simulation.py
```

The job still deduplicates per user and date. Chrome intentionally does not register for these mobile notifications.

For a live judging demo, set `PUSH_DEMO_INTERVAL_MINUTES=1` in the private
`backend/.env` and restart the API. Eligible cashflow warnings and subscribed
hurricane simulations are then deduplicated per one-minute window. Restore the
value to `0` after the demo to return to the once-daily schedule. Production
mode rejects this demo setting.
