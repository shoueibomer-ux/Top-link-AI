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
