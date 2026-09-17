from django.db import models


class ProviderMatch(models.Model):
    """A real (Google Places) provider a subscribed device has unlocked full
    contact details for.

    NOTE: identifies "the client" by `device_id`, not a FK to Django's User
    model — this app has no login/signup system, so there's no User row to
    point at. `device_id` is the same client identifier already used by
    matching.models.Subscription (see provider_search.views for the
    subscription check), which is the real mechanism this project uses to
    answer "who is asking" everywhere else.
    """

    device_id = models.CharField(max_length=64)
    category = models.CharField(max_length=50)
    city = models.CharField(max_length=100)
    place_id = models.CharField(max_length=255)
    provider_name = models.CharField(max_length=255)
    provider_phone = models.CharField(max_length=50, blank=True)
    provider_address = models.CharField(max_length=500, blank=True)
    provider_website = models.URLField(max_length=500, blank=True)
    first_unlocked_at = models.DateTimeField(auto_now_add=True)
    last_viewed_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("device_id", "place_id")

    def __str__(self):
        return f"{self.device_id} -> {self.provider_name}"
