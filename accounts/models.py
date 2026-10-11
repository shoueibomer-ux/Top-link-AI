from django.conf import settings
from django.db import models


class UserRole(models.TextChoices):
    CUSTOMER = "customer", "Customer"
    PROVIDER = "provider", "Provider"
    ADMIN = "admin", "Admin"


class UserProfile(models.Model):
    """Extends Django's built-in User with the role this platform checks in
    API views. Real accounts (this app) — Customer and Provider — exist
    alongside the pre-existing anonymous device_id (matching.models.Subscription,
    provider_search.models.ProviderMatch) and self-issued provider_id
    (provider_search.models.ProviderOnboarding) patterns rather than
    replacing them: today's Ask AI / History / matching flow keeps working
    exactly as before, unauthenticated. Reconciling that anonymous history
    with a logged-in account is deliberately left for a later phase.

    Django's own is_staff/is_superuser already gate the real Django admin —
    ADMIN here is for API-side authorization checks (e.g. a future admin
    API), not a replacement for that. The public registration endpoint
    (see accounts.views.RegisterView) refuses to create ADMIN accounts;
    those are only ever created via `createsuperuser` or the Django admin.
    """

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="profile")
    role = models.CharField(max_length=20, choices=UserRole.choices, default=UserRole.CUSTOMER)
    full_name = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.email} ({self.role})"
