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


class ProviderBusinessProfile(models.Model):
    """A real, authenticated provider's business profile — one per User with
    role=PROVIDER. Deliberately a fresh model rather than a reuse of
    matching.models.Profile: that one is wired to the unused
    matching.models.Category table and the dead from-scratch matching
    engine (matching_engine.find_matches), which nothing in the live app
    calls; forcing it to also carry real-account business data would tie
    new work to that dead subsystem. Fields mirror how this app already
    models a business (see provider_search.models.ProviderOnboarding /
    ProviderAvailability) rather than the legacy Profile's shape.

    As of the marketplace build plan's Phase 1A, this is now the ONE
    permanent provider identity the plan calls for — ProviderOnboarding's
    fields (personal_info/services/service_area/credentials/photos) are
    folded in below so a real account can hold everything the old
    self-issued-UUID wizard could. ProviderOnboarding itself is NOT deleted
    or migrated automatically: its screen and any existing demo rows keep
    working untouched (see provider_onboarding_screen.dart), while new
    provider signups go through registration + this profile instead.
    ProviderAvailability's place_id is bridged via the nullable `place_id`
    field below — set once a provider claims an existing Google-sourced
    listing as their own; matching/leads (Phase 1B/1C) only ever consider
    profiles reachable this way, never an unclaimed place_id alone.
    """

    PROVIDER_TYPE_INDIVIDUAL = "individual"
    PROVIDER_TYPE_BUSINESS = "business"
    PROVIDER_TYPE_CHOICES = [
        (PROVIDER_TYPE_INDIVIDUAL, "Individual"),
        (PROVIDER_TYPE_BUSINESS, "Business"),
    ]

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="provider_business_profile"
    )
    business_name = models.CharField(max_length=200, blank=True)
    description = models.TextField(blank=True)
    # List of category slugs — mirrors provider_search.services.CATEGORY_QUERIES
    # keys / ProviderOnboarding.services, kept as plain JSON rather than a
    # FK to matching.models.Category since nothing else in the app treats
    # that table as the source of truth for categories.
    categories = models.JSONField(default=list, blank=True)
    # One of provider_search.services.CITIES — kept as a plain string (not a
    # FK) for the same reason: cities are a configured list, not a DB table,
    # everywhere else in the app today.
    city = models.CharField(max_length=100, blank=True)
    phone = models.CharField(max_length=50, blank=True)
    is_available_now = models.BooleanField(default=True)

    # --- Capability fields (build plan Phase 1A / task 1) — feed the
    # revived matching_engine.find_matches() scoring in Phase 1B. ---
    provider_type = models.CharField(max_length=20, choices=PROVIDER_TYPE_CHOICES, default=PROVIDER_TYPE_INDIVIDUAL)
    team_size = models.PositiveIntegerField(null=True, blank=True)
    equipment = models.JSONField(default=list, blank=True)
    certifications = models.JSONField(default=list, blank=True)
    service_radius_km = models.FloatField(null=True, blank=True)
    languages = models.JSONField(default=list, blank=True)
    # Computed from real Lead/response data once Phase 1C exists — plain
    # nullable fields for now rather than fabricated defaults.
    response_time_minutes = models.PositiveIntegerField(null=True, blank=True)
    completion_rate = models.FloatField(null=True, blank=True)
    # The claim bridge to an existing Google-sourced listing (see class
    # docstring). unique + nullable: many profiles can have no place_id, but
    # a given place_id can only ever be claimed by one profile.
    place_id = models.CharField(max_length=255, unique=True, null=True, blank=True)

    # --- Folded in from ProviderOnboarding (build plan rule 4) — that
    # model's full_name/email/services/city map onto UserProfile.full_name,
    # the account's own email, `categories`, and `city` above respectively,
    # so only its remaining, non-duplicate fields are added here. ---
    years_experience = models.PositiveIntegerField(null=True, blank=True)
    is_insured = models.BooleanField(default=False)
    photo_urls = models.JSONField(default=list, blank=True)

    # Populated for real once Phase 1E (verified reviews) exists.
    rating = models.FloatField(default=0.0)
    rating_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.business_name or self.user.email
