from django.db import models


class ProviderMatch(models.Model):
    """The client's request/connection record for one real (Google Places)
    provider — created ONLY when a device actually unlocks that provider's
    full contact details (see provider_search.views.ProviderUnlockView), not
    merely because the provider showed up in a search result. A provider
    appearing in `search_providers()` results is ephemeral (see
    ServiceRequest.status / STATUS_FOUND) until a client explicitly unlocks
    it, at which point this row is created and the client's device gains
    permanent access to the real phone/address/website for that provider.

    NOTE: identifies "the client" by `device_id`, not a FK to Django's User
    model — this app has no login/signup system, so there's no User row to
    point at. `device_id` is the same client identifier already used by
    matching.models.Subscription (see provider_search.views for the
    subscription check), which is the real mechanism this project uses to
    answer "who is asking" everywhere else.
    """

    STATUS_SEARCHING = "searching"
    STATUS_FOUND = "found"
    STATUS_REQUESTED = "requested"
    STATUS_RESPONDED = "responded"
    STATUS_CONTACTED = "contacted"
    STATUS_BOOKED = "booked"
    STATUS_IN_PROGRESS = "in_progress"
    STATUS_COMPLETED = "completed"
    STATUS_CANCELLED = "cancelled"
    STATUS_ARCHIVED = "archived"
    # Retired: rows created before the unlock-gated flow default to this.
    # Kept only so old data and ProviderMatchStatusView can still read/set
    # it if ever needed — no longer offered as a fresh default or (in the
    # Flutter app) as a manual status choice.
    STATUS_MATCHED = "matched"
    STATUS_CHOICES = [
        (STATUS_SEARCHING, "Searching"),
        (STATUS_FOUND, "Found"),
        (STATUS_REQUESTED, "Requested"),
        (STATUS_RESPONDED, "Responded"),
        (STATUS_CONTACTED, "Contacted"),
        (STATUS_BOOKED, "Booked"),
        (STATUS_IN_PROGRESS, "In Progress"),
        (STATUS_COMPLETED, "Completed"),
        (STATUS_CANCELLED, "Cancelled"),
        (STATUS_ARCHIVED, "Archived"),
        (STATUS_MATCHED, "Matched (legacy)"),
    ]

    device_id = models.CharField(max_length=64)
    category = models.CharField(max_length=50)
    city = models.CharField(max_length=100)
    # Nullable/optional: rows created before ServiceRequest existed have
    # none, and nothing about the client's own History view depends on it
    # being set — see ServiceRequest's docstring for what this links to.
    service_request = models.ForeignKey(
        "ServiceRequest", null=True, blank=True, on_delete=models.SET_NULL, related_name="provider_matches"
    )
    place_id = models.CharField(max_length=255)
    provider_name = models.CharField(max_length=255)
    provider_phone = models.CharField(max_length=50, blank=True)
    provider_address = models.CharField(max_length=500, blank=True)
    provider_website = models.URLField(max_length=500, blank=True)
    # How this unlock was paid for — "subscription" (device had an active
    # Subscription at unlock time, no charge) or "paid" (one-off $4.99,
    # trusted from the client same as SubscriptionActivateView — there's no
    # real payment processor wired up for this yet either). Blank on rows
    # created before this field existed.
    UNLOCK_METHOD_SUBSCRIPTION = "subscription"
    UNLOCK_METHOD_PAID = "paid"
    UNLOCK_METHOD_CHOICES = [
        (UNLOCK_METHOD_SUBSCRIPTION, "Subscription"),
        (UNLOCK_METHOD_PAID, "Paid ($4.99)"),
    ]
    unlock_method = models.CharField(max_length=20, choices=UNLOCK_METHOD_CHOICES, blank=True)
    # The free-text problem description that led to this match, when it
    # came from the chat flow (see ChatRefineView) — blank for matches found
    # via the fixed category-tap onboarding flow, since there's no free text
    # to capture there. Never backfilled/fabricated for older rows.
    problem_description = models.TextField(blank=True)
    # A row only ever gets created by an explicit unlock (see this model's
    # docstring), so "requested" — a real request was just sent — is the
    # correct default, never "searching"/"found" (those describe a provider
    # that doesn't have a row here yet) and never "matched" (retired).
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_REQUESTED)
    # Set only by ProviderRequestRespondView, the one place a provider can
    # act on a request — accept/decline is intentionally a separate field
    # from `status` (which just moves requested -> responded either way) so
    # the client can tell the two apart and show a decline clearly instead
    # of a request that merely looks "responded".
    DECISION_ACCEPTED = "accepted"
    DECISION_DECLINED = "declined"
    DECISION_CHOICES = [
        (DECISION_ACCEPTED, "Accepted"),
        (DECISION_DECLINED, "Declined"),
    ]
    provider_decision = models.CharField(max_length=20, choices=DECISION_CHOICES, blank=True)
    # The provider's optional reply message, captured at the same time as
    # the decision — blank for a response with no message, and always blank
    # until then.
    provider_message = models.TextField(blank=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    first_unlocked_at = models.DateTimeField(auto_now_add=True)
    last_viewed_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("device_id", "place_id")

    def __str__(self):
        return f"{self.device_id} -> {self.provider_name}"


class ProviderAvailability(models.Model):
    """This platform's own "available now / busy" override for a real
    (Google Places) business, keyed by place_id rather than a provider
    account — there's no provider login/signup system in this app (see
    ProviderMatch's docstring for the same limitation on the client side),
    so any provider toggling this is trusted by place_id alone, via the demo
    Provider Dashboard screen. A missing row means "available" (the default
    a newly-found provider should show as, rather than unknown/busy).
    """

    place_id = models.CharField(max_length=255, unique=True)
    is_available_now = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.place_id}: {'available' if self.is_available_now else 'busy'}"


class ProviderOnboarding(models.Model):
    """A provider's structured sign-up, broken into 5 independent sections
    so they can be completed in any order/session — completion_percentage
    (see the property below) is what flags an incomplete profile for
    follow-up.

    Keyed by a self-issued `provider_id` (a UUID minted client-side, see
    lib/provider/provider_id.dart), the same "no real accounts yet" pattern
    as device_id/ProviderMatch — this is a NEW provider signing up, distinct
    from an existing Google-Places business (ProviderAvailability's
    place_id) toggling its own status.
    """

    SECTION_FIELDS = {
        "personal_info": ["full_name", "phone", "email"],
        "services": ["services"],
        "service_area": ["city"],
        "credentials": ["years_experience", "is_insured"],
        "photos": ["photo_urls"],
    }

    provider_id = models.CharField(max_length=64, unique=True)

    # Personal Info
    full_name = models.CharField(max_length=200, blank=True)
    phone = models.CharField(max_length=50, blank=True)
    email = models.EmailField(blank=True)

    # Services Offered — list of category slugs (see onboarding.service_category.dart)
    services = models.JSONField(default=list, blank=True)

    # Service Area — one of provider_search.services.CITIES
    city = models.CharField(max_length=100, blank=True)

    # Credentials / Verification
    years_experience = models.PositiveIntegerField(null=True, blank=True)
    is_insured = models.BooleanField(default=False)

    # Photos — URLs only; there's no file upload/storage pipeline in this
    # app yet, so a provider pastes links to photos hosted elsewhere.
    photo_urls = models.JSONField(default=list, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def section_complete(self, section: str) -> bool:
        if section == "personal_info":
            return bool(self.full_name and self.phone and self.email)
        if section == "services":
            return bool(self.services)
        if section == "service_area":
            return bool(self.city)
        if section == "credentials":
            return self.years_experience is not None
        if section == "photos":
            return bool(self.photo_urls)
        raise ValueError(f"Unknown section: {section!r}")

    @property
    def completion_percentage(self) -> int:
        sections = list(self.SECTION_FIELDS)
        done = sum(1 for section in sections if self.section_complete(section))
        return round(done / len(sections) * 100)

    @property
    def is_complete(self) -> bool:
        return self.completion_percentage == 100

    def __str__(self):
        return f"{self.provider_id} ({self.completion_percentage}% complete)"


class ServiceRequest(models.Model):
    """The customer's actual "job" — one row per request, holding the AI's
    classification of it (see chat_service.refine_request). Build plan
    Phase 1A, task 4.

    This is new modeling that sits ABOVE ProviderMatch, not a replacement
    for it: ProviderMatch keeps its existing job as the customer's own
    per-provider engagement/status row (unchanged shape, unchanged API —
    see its docstring); a ServiceRequest is created alongside it and linked
    via ProviderMatch.service_request so the "right job" side of the
    Right Provider -> Right Job -> Right Place chain has a real anchor.
    Phase 1B's ranking and Phase 1C's Lead model both read from here.

    Status reuses ProviderMatch.STATUS_CHOICES directly (not a duplicated
    copy) since the plan calls for a request's lifecycle to "mirror" that
    vocabulary one level up.
    """

    device_id = models.CharField(max_length=64, db_index=True)
    category = models.CharField(max_length=50)
    city = models.CharField(max_length=100)
    problem_description = models.TextField(blank=True)

    # --- AI classification (chat_service.refine_request) — blank for
    # requests that came from the fixed category-tap flow, which has no
    # free text for Claude to classify beyond the category itself. ---
    JOB_SIZE_SMALL = "small"
    JOB_SIZE_MEDIUM = "medium"
    JOB_SIZE_LARGE = "large"
    JOB_SIZE_CHOICES = [
        (JOB_SIZE_SMALL, "Small"),
        (JOB_SIZE_MEDIUM, "Medium"),
        (JOB_SIZE_LARGE, "Large"),
    ]
    JOB_COMPLEXITY_SIMPLE = "simple"
    JOB_COMPLEXITY_MODERATE = "moderate"
    JOB_COMPLEXITY_COMPLEX = "complex"
    JOB_COMPLEXITY_CHOICES = [
        (JOB_COMPLEXITY_SIMPLE, "Simple"),
        (JOB_COMPLEXITY_MODERATE, "Moderate"),
        (JOB_COMPLEXITY_COMPLEX, "Complex"),
    ]

    job_size = models.CharField(max_length=20, choices=JOB_SIZE_CHOICES, blank=True)
    job_complexity = models.CharField(max_length=20, choices=JOB_COMPLEXITY_CHOICES, blank=True)
    required_skills = models.JSONField(default=list, blank=True)
    estimated_team_size = models.PositiveIntegerField(null=True, blank=True)
    required_equipment = models.JSONField(default=list, blank=True)
    required_qualifications = models.JSONField(default=list, blank=True)

    status = models.CharField(max_length=20, choices=ProviderMatch.STATUS_CHOICES, default=ProviderMatch.STATUS_SEARCHING)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.device_id} -> {self.category} ({self.status})"
