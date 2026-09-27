from django.db import models


class Category(models.Model):
    """Controlled taxonomy — edit this table anytime without touching code."""
    name = models.CharField(max_length=100, unique=True)
    keywords = models.JSONField(default=list, blank=True)  # used by ai_categorize() fallback/seed

    class Meta:
        verbose_name_plural = "categories"

    def __str__(self):
        return self.name


class Profile(models.Model):
    ROLE_CHOICES = [("business", "Business"), ("individual", "Individual")]

    name = models.CharField(max_length=200)
    role = models.CharField(max_length=20, choices=ROLE_CHOICES)
    description = models.TextField(blank=True)          # free text, AI reads this
    categories = models.ManyToManyField(Category, blank=True)  # AI-assigned
    lat = models.FloatField()
    lng = models.FloatField()
    available = models.BooleanField(default=True)
    rating = models.FloatField(default=0.0)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name


class MatchRequest(models.Model):
    requester = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="requests_made")
    request_text = models.TextField()                   # free text, AI reads this
    categories = models.ManyToManyField(Category, blank=True)  # AI-assigned
    lat = models.FloatField()
    lng = models.FloatField()
    max_distance_km = models.FloatField(default=25.0)
    created_at = models.DateTimeField(auto_now_add=True)


class Subscription(models.Model):
    """Tracks paywall access per installation.

    The app has no login/signup, so there's no User to key this off of —
    `device_id` is a UUID the client generates once and persists locally,
    standing in for "the user" until/unless real accounts are added.

    NOTE: activation is currently trusted from the client (see
    SubscriptionActivateView) since there's no App Store/Play Store receipt
    validation wired up yet. That must be added before this can be trusted
    for real billing — right now it only gates the UI, it doesn't verify
    anyone actually paid.
    """

    STATUS_CHOICES = [
        ("trial", "Trial"),
        ("active", "Active"),
        ("inactive", "Inactive"),
    ]

    device_id = models.CharField(max_length=64, unique=True)
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default="inactive")
    start_date = models.DateTimeField(null=True, blank=True)
    expiry_date = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.device_id} ({self.status})"


class UnlockCredit(models.Model):
    """One pre-paid, single-use provider unlock, bought as the paywall's
    "$4.99 one-time" option. Deliberately keyed by `device_id` and NOT tied
    to a provider: at purchase time no provider has been chosen yet (the
    paywall comes before any search), so the credit just sits here until the
    next provider this device unlocks — see provider_search.views.
    ProviderUnlockView, which consumes the oldest unconsumed credit instead
    of demanding `paid: true` again, and records that unlock as
    ProviderMatch.unlock_method="paid".

    A device that has bought at least one credit keeps app access afterwards
    (see matching.access.has_access): browsing/search is always free by
    design, and otherwise the contact details it just paid for would be
    locked behind the paywall on the next launch.

    NOTE: like Subscription, granting is currently trusted from the client
    (see UnlockCreditActivateView) — no App Store/Play Store receipt
    validation exists yet, so this does not verify anyone actually paid.
    `transaction_id` (the store's purchase id, when one exists) makes
    granting idempotent so a retried or replayed purchase can't mint a
    second credit.
    """

    device_id = models.CharField(max_length=64, db_index=True)
    transaction_id = models.CharField(max_length=255, unique=True, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    consumed_at = models.DateTimeField(null=True, blank=True)
    # Which provider this credit was spent on — for reporting on one-time
    # vs subscription usage. Blank while unconsumed.
    consumed_place_id = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        state = f"spent on {self.consumed_place_id}" if self.consumed_at else "unspent"
        return f"{self.device_id} ({state})"
