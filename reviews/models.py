from datetime import timedelta

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

REVIEW_EDIT_WINDOW = timedelta(days=7)
MAX_COMMENT_CHARS = 1000


class Review(models.Model):
    """A client's rating of the provider they hired, for one completed job. One per job (the offer that was
    marked completed), written only by the client who owns that request, editable for 7 days. It is public:
    it appears on the provider's profile with the client's name shortened ("Pat P."), and the provider may post
    one public reply. Staff can hide a review (it then counts for nothing and shows nowhere)."""

    offer = models.OneToOneField("leads.LeadOffer", on_delete=models.CASCADE, related_name="review")
    # Kept as a blank if the account is ever deleted, so the provider's rating history stays whole.
    client = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="reviews_written")
    provider = models.ForeignKey("providers.ProviderProfile", on_delete=models.CASCADE, related_name="reviews")
    rating = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    # Set when the client changes the rating or comment after posting (so the app can say "edited").
    edited_at = models.DateTimeField(null=True, blank=True)

    # The provider's one public reply. It can't be edited or removed by the provider; staff can clear it.
    reply = models.TextField(blank=True)
    reply_at = models.DateTimeField(null=True, blank=True)

    # Moderation.
    hidden = models.BooleanField(default=False, db_index=True)
    hidden_reason = models.CharField(max_length=200, blank=True)
    hidden_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.CheckConstraint(condition=models.Q(rating__gte=1, rating__lte=5), name="review_rating_1_to_5"),
        ]
        indexes = [models.Index(fields=["provider", "hidden", "-created_at"])]

    def __str__(self):
        return f"{self.rating}/5 for {self.provider_id} (offer {self.offer_id})"

    @property
    def editable_until(self):
        return self.created_at + REVIEW_EDIT_WINDOW

    def can_be_edited(self, now=None) -> bool:
        return (now or timezone.now()) <= self.editable_until


class ReviewReport(models.Model):
    REASON_SPAM = "spam"
    REASON_ABUSIVE = "abusive"
    REASON_FAKE = "fake"
    REASON_PERSONAL = "personal"
    REASON_OTHER = "other"
    REASON_CHOICES = [
        (REASON_SPAM, "Spam or advertising"),
        (REASON_ABUSIVE, "Abusive or hateful"),
        (REASON_FAKE, "Fake or not a real customer"),
        (REASON_PERSONAL, "Shares personal information"),
        (REASON_OTHER, "Something else"),
    ]
    STATUS_OPEN = "open"
    STATUS_ACTIONED = "actioned"
    STATUS_DISMISSED = "dismissed"
    STATUS_CHOICES = [(STATUS_OPEN, "Open"), (STATUS_ACTIONED, "Action taken"), (STATUS_DISMISSED, "Dismissed")]

    review = models.ForeignKey(Review, on_delete=models.CASCADE, related_name="reports")
    reporter = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="review_reports")
    reason = models.CharField(max_length=20, choices=REASON_CHOICES)
    details = models.CharField(max_length=500, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_OPEN, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["review", "reporter"], name="one_review_report_per_reporter")]

    def __str__(self):
        return f"Report #{self.pk} on review {self.review_id} ({self.reason})"


class Favorite(models.Model):
    """A provider a client saved (the heart)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="favorite_providers")
    provider = models.ForeignKey("providers.ProviderProfile", on_delete=models.CASCADE, related_name="favorited_by")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["user", "provider"], name="one_favorite_per_provider")]

    def __str__(self):
        return f"{self.user_id} likes {self.provider_id}"
