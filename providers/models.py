from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from leads.phone import normalize_phone


class ProviderProfileQuerySet(models.QuerySet):
    def approved(self):
        """The only providers clients may ever be shown."""
        return self.filter(status=ProviderProfile.STATUS_APPROVED)


class ProviderProfile(models.Model):
    """The one provider model: a business that registered itself in the app
    (signed in with Google) and is waiting for, or has passed, a human review.

    Client requests are offered to providers (leads.LeadOffer) and clients are
    shown providers only through ProviderProfile.objects.approved(). Texting a
    provider additionally needs their recorded SMS consent and no STOP.
    """

    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending review"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_REJECTED, "Rejected"),
    ]

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="registered_provider")
    business_name = models.CharField(max_length=200)
    # Stored as +1XXXXXXXXXX, like client phones (leads.phone).
    phone = models.CharField(max_length=32)
    # Contact email; starts as the Google account's email but is editable.
    email = models.EmailField()
    # Leaf services from the catalog, like ServiceRequest.category: any active
    # service, launched or not, so providers can sign up for upcoming ones.
    categories = models.ManyToManyField("catalog.Service", blank=True, related_name="provider_profiles")
    # City names from provider_search.services.CITIES.
    cities = models.JSONField(default=list, blank=True)
    bio = models.TextField(blank=True)

    # When they ticked "you may text me about client requests" (CASL), or an
    # admin recorded that they agreed. Without it they can't be sent offers.
    sms_consent_at = models.DateTimeField(null=True, blank=True)
    # Set when they reply STOP; never text a provider who is opted out.
    sms_opt_out = models.BooleanField(default=False)
    # Admin-only notes; never shown to the provider.
    notes = models.TextField(blank=True)

    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING, db_index=True)
    # Shown to the provider, e.g. why they weren't approved.
    review_note = models.TextField(blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = ProviderProfileQuerySet.as_manager()

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.business_name

    def clean(self):
        if not normalize_phone(self.phone):
            raise ValidationError({"phone": "Enter a valid phone number, e.g. 780 555 0100 or +17805550100."})

    def save(self, *args, **kwargs):
        # Stored as E.164 so an inbound SMS `From` matches it.
        self.phone = normalize_phone(self.phone) or self.phone
        super().save(*args, **kwargs)

    @property
    def contact_name(self) -> str:
        profile = getattr(self.user, "profile", None)
        return profile.full_name if profile else ""

    @property
    def cannot_text_reason(self) -> str:
        """Why this provider can't be sent an offer, or "" if they can."""
        if self.status != self.STATUS_APPROVED:
            return "not approved"
        if self.sms_opt_out:
            return "opted out (STOP)"
        if self.sms_consent_at is None:
            return "no SMS consent recorded"
        return ""

    @property
    def can_text(self) -> bool:
        return not self.cannot_text_reason

    def _review(self, status, note=None):
        self.status = status
        self.reviewed_at = timezone.now()
        fields = ["status", "reviewed_at", "updated_at"]
        if note is not None:
            self.review_note = note
            fields.append("review_note")
        self.save(update_fields=fields)

    def approve(self):
        self._review(self.STATUS_APPROVED, note="")

    def reject(self, note=None):
        self._review(self.STATUS_REJECTED, note=note)


class GoogleIdentity(models.Model):
    """Which Google account (its stable `sub`) signed in as which user, so a
    changed Google email can't hand the account to someone else."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="google_identity")
    sub = models.CharField(max_length=255, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Google {self.sub} -> {self.user}"
