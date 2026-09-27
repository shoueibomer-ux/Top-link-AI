"""Who may do what, per device — shared by the subscription-status endpoint
and provider_search's unlock view so the rules live in exactly one place."""

from django.utils import timezone

from .models import Subscription, UnlockCredit


def is_subscribed(device_id: str) -> bool:
    subscription = Subscription.objects.filter(device_id=device_id).first()
    if subscription is None or subscription.status not in ("trial", "active"):
        return False
    if subscription.expiry_date and subscription.expiry_date < timezone.now():
        return False
    return True


def credits_available(device_id: str) -> int:
    return UnlockCredit.objects.filter(device_id=device_id, consumed_at__isnull=True).count()


def has_bought_credit(device_id: str) -> bool:
    """True once this device has ever bought a one-time credit, spent or not."""
    return UnlockCredit.objects.filter(device_id=device_id).exists()


def has_access(device_id: str) -> bool:
    """Whether the app's up-front gate (subscription.AppEntryPoint) lets this
    device in: an active subscription, or having bought a one-time unlock —
    the latter stays true after the credit is spent, since search is free
    and the unlocked provider's details must remain viewable."""
    return is_subscribed(device_id) or has_bought_credit(device_id)


def consume_credit(device_id: str, place_id: str) -> bool:
    """Spends this device's oldest unconsumed credit on `place_id`. Returns
    False if there wasn't one. MUST be called inside transaction.atomic() —
    the row lock is what stops two concurrent unlocks spending one credit."""
    credit = (
        UnlockCredit.objects.select_for_update()
        .filter(device_id=device_id, consumed_at__isnull=True)
        .order_by("created_at")
        .first()
    )
    if credit is None:
        return False
    credit.consumed_at = timezone.now()
    credit.consumed_place_id = place_id
    credit.save(update_fields=["consumed_at", "consumed_place_id"])
    return True
