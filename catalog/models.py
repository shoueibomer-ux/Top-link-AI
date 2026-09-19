from django.db import models


class Category(models.Model):
    """A top-level service grouping (e.g. "Home Services") shown on the
    customer-facing categories page. Admin-managed — adding, editing, or
    deactivating a category needs no code change or app rebuild. See
    Service below for the bookable leaf items inside each category.
    """

    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100, unique=True)
    icon_name = models.CharField(max_length=50, default="category")
    display_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["display_order", "name"]
        verbose_name_plural = "categories"

    def __str__(self):
        return self.name


class Service(models.Model):
    """A bookable leaf service inside a Category (e.g. "Plumbing" inside
    "Trades & Professional Services"). `slug` is what the rest of the app
    already calls "category" — ProviderMatch.category, ServiceRequest.category,
    ProviderBusinessProfile.categories, and matching_engine.CATEGORY_TAXONOMY
    all key on this same string, so a Service here maps one-to-one onto that
    pre-existing flat concept rather than replacing it.
    """

    category = models.ForeignKey(Category, on_delete=models.CASCADE, related_name="services")
    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100, unique=True)
    icon_name = models.CharField(max_length=50, default="build")
    what_we_cover = models.TextField(blank=True)
    worker_noun = models.CharField(max_length=100, blank=True)
    # English search phrase sent to Google Places (see
    # provider_search.services.CATEGORY_QUERIES, which this seeds/extends).
    google_places_query = models.CharField(max_length=200, blank=True)
    display_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["display_order", "name"]

    def __str__(self):
        return f"{self.name} ({self.category.name})"
