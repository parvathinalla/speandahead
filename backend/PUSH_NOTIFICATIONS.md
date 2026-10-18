# Device push notifications

CreditPilot uses Firebase Cloud Messaging (FCM) for the daily seven-day cashflow warning. The backend checks each registered user's upcoming bills after the configured local hour. It sends nothing when checking funds cover the forecast. It records a delivery before another cycle can notify that user again on the same day.

The phone asks for notification permission after a successful Auth0 login. Tapping a cashflow notification opens the app on **Cashflow & Bills**, where the forecast offers **Move money from savings** and **Request money from a contact**.

## Firebase setup

1. Create Android and iOS apps in one Firebase project. Their package IDs must match the release IDs configured for this Flutter app.
2. Give the Flutter build these public Firebase client values:

   ```text
   --dart-define=FIREBASE_API_KEY=...
   --dart-define=FIREBASE_APP_ID=...
   --dart-define=FIREBASE_MESSAGING_SENDER_ID=...
   --dart-define=FIREBASE_PROJECT_ID=...
   ```

   Android and iOS Firebase app IDs are different, so build each platform with its own `FIREBASE_APP_ID`. These identifiers configure the client; the server credential below is private.

3. Create a Firebase service account for the backend and point Application Default Credentials to the downloaded JSON file. Keep the file outside the repository:

   ```text
   GOOGLE_APPLICATION_CREDENTIALS=C:/private/creditpilot/firebase-service-account.json
   FIREBASE_PROJECT_ID=your-project-id
   PUSH_NOTIFICATIONS_ENABLED=true
   PUSH_DAILY_HOUR_LOCAL=9
   ```

4. For iOS, upload an APNs authentication key in Firebase Cloud Messaging settings and enable the Push Notifications capability for the Apple App ID and provisioning profile. The Xcode project already includes the remote-notification background mode and APS entitlement.

Run the API continuously to use its built-in 15-minute scheduler. A hosting platform's daily job can instead execute:

```powershell
python backend/scripts/send_daily_push_notifications.py
```

The job still deduplicates per user and date. Chrome intentionally does not register for these mobile notifications.
