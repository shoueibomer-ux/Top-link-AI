from .models import Notification


def notify(device_id: str, title: str, body: str = "", category: str = "") -> None:
    """Create a notification for a device.

    A plain function (not a signal) so callers — SubscriptionActivateView,
    ProviderSearchView — stay explicit about when a notification fires,
    rather than something implicit reacting to model saves. `category`
    (a slug, e.g. "plumbing") lets the client deep-link to that category's
    detail page when the notification is tapped; leave blank for
    notifications with no specific category.
    """
    Notification.objects.create(device_id=device_id, title=title, body=body, category=category)
