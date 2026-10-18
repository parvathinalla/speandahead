"""Firebase Cloud Messaging adapter.

Firebase credentials are loaded through Application Default Credentials. This
module deliberately imports firebase-admin only when a message is sent so the
API can still run locally when push notifications are disabled.
"""
from functools import lru_cache
import os


@lru_cache(maxsize=1)
def _firebase_app():
    import firebase_admin

    try:
        return firebase_admin.get_app()
    except ValueError:
        project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
        options = {"projectId": project_id} if project_id else None
        return firebase_admin.initialize_app(options=options)


def send_cashflow_warning(tokens: list[str], title: str, body: str) -> dict:
    """Send one visible notification to each device and report bad tokens."""
    if not tokens:
        return {"success_count": 0, "invalid_tokens": []}

    from firebase_admin import messaging

    messages = [
        messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data={"screen": "cashflow", "type": "cashflow_shortfall"},
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="cashflow_alerts",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default"),
                ),
            ),
        )
        for token in tokens
    ]
    response = messaging.send_each(messages, app=_firebase_app())
    invalid_tokens = []
    for token, result in zip(tokens, response.responses):
        if result.success:
            continue
        error_text = str(result.exception or "").lower()
        if "unregistered" in error_text or "registration-token-not-registered" in error_text:
            invalid_tokens.append(token)
    return {
        "success_count": response.success_count,
        "invalid_tokens": invalid_tokens,
    }
