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
    calls "category" — ServiceRequest.category, ProviderBusinessProfile.
    categories, and the keyword table matching_engine.CATEGORY_TAXONOMY all
    key on this same string. Which slugs exist is decided here and nowhere
    else (see catalog.taxonomy).
    """

    category = models.ForeignKey(Category, on_delete=models.CASCADE, related_name="services")
    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100, unique=True)
    icon_name = models.CharField(max_length=50, default="build")
    what_we_cover = models.TextField(blank=True)
    worker_noun = models.CharField(max_length=100, blank=True)
    # English search phrase for finding businesses of this kind (outreach).
    google_places_query = models.CharField(max_length=200, blank=True)
    display_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    # `is_active` controls whether the service exists at all (website pages,
    # classification); `is_launched` controls whether we can actually serve
    # it yet. The app only offers launched services, and a request for an
    # active-but-not-launched one is saved as waitlisted ("coming soon").
    is_launched = models.BooleanField(default=False)

    class Meta:
        ordering = ["display_order", "name"]

    def __str__(self):
        return f"{self.name} ({self.category.name})"
