from django.db import models


class Notification(models.Model):
    """A single notification for one installation.

    Identified by `device_id`, same convention as matching.Subscription and
    provider_search.ProviderMatch — this app has no login system, so
    device_id is the only "who is this" the backend has.
    """

    device_id = models.CharField(max_length=64, db_index=True)
    title = models.CharField(max_length=200)
    body = models.CharField(max_length=500, blank=True)
    # Category slug (matches ServiceCategory.slug / matching_engine.CATEGORY_TAXONOMY)
    # this notification is about, if any — lets the client deep-link to that
    # category's detail page when the notification is tapped. Blank for
    # notifications with no specific category (e.g. the welcome message).
    category = models.CharField(max_length=50, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.device_id}: {self.title}"
