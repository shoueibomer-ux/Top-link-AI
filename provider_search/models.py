from django.db import models


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
    """The customer's actual "job" — one row per request submitted either
    from the app's own request flow or (once it exists) the website form,
    both going through ServiceRequestCreateView. Holds the AI's
    classification of it when the request came with free text to classify
    (see chat_service.refine_request).

    Phase 0 of the marketplace build: this used to sit above ProviderMatch
    (one per client/provider engagement, created only on an explicit unlock
    of a Google-sourced listing); ProviderMatch and the whole Google-listing
    search/unlock flow were removed, so this is now the only record of a
    client's request. `status` is deliberately minimal for now — it only
    needs to exist, not describe a lifecycle yet — until the LeadOffer model
    (ServiceRequest -> LeadOffer -> a specific provider) replaces it with a
    real one.

    `phone` and `consent_given` back the explicit consent the request form
    collects: "I consent to Tabmatch sharing the details of this request,
    including my phone number, with service providers who may be able to
    help." (see ServiceRequestCreateView) — consent_given is only ever set
    True by that checkbox, never defaulted or inferred.
    """

    STATUS_NEW = "new"
    # The service is active in the catalog but not launched yet (see
    # catalog.Service.is_launched): the request is kept as demand signal and
    # the client is told it is coming soon, rather than being rejected.
    STATUS_WAITLISTED = "waitlisted"
    STATUS_CHOICES = [
        (STATUS_NEW, "New"),
        (STATUS_WAITLISTED, "Waitlisted"),
    ]

    device_id = models.CharField(max_length=64, db_index=True)
    # catalog.Service.slug (validated against the catalog on creation).
    category = models.CharField(max_length=50)
    city = models.CharField(max_length=100)
    problem_description = models.TextField(blank=True)
    phone = models.CharField(max_length=50)
    # Must be True to create a row at all (see ServiceRequestCreateView) —
    # stored anyway, rather than assumed, so consent is auditable per request
    # rather than inferred from the row merely existing.
    consent_given = models.BooleanField(default=False)

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

    URGENCY_TODAY = "today"
    URGENCY_THIS_WEEK = "this_week"
    URGENCY_EXPLORING = "exploring"
    URGENCY_CHOICES = [
        (URGENCY_TODAY, "Today"),
        (URGENCY_THIS_WEEK, "This week"),
        (URGENCY_EXPLORING, "Just exploring"),
    ]
    # What the client picked on the urgency step; blank for requests made
    # before this was stored.
    urgency = models.CharField(max_length=20, choices=URGENCY_CHOICES, blank=True)

    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_NEW)
    # Set once the "no YES after 2 hours" email has gone out for this request
    # (see leads.jobs), so it is only sent once.
    no_yes_alert_sent_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.device_id} -> {self.category} ({self.status})"


class WaitlistedRequest(ServiceRequest):
    """Admin-only lens on ServiceRequest: just the waitlisted ones, with a
    demand-per-service summary (see WaitlistDemandAdmin). A proxy, so it has
    no table of its own."""

    class Meta:
        proxy = True
        verbose_name = "waitlist demand"
        verbose_name_plural = "waitlist demand"
