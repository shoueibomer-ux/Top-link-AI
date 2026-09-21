from django.db import models


class Sector(models.Model):
    """A marketing-site grouping of services (e.g. "Outdoor Services").

    Deliberately separate from catalog.Category: sectors are a presentation
    concern of the website, so one catalog.Service can appear in several
    sectors (Landscaping) without the app's own taxonomy changing.
    """

    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100, unique=True)
    blurb = models.CharField(max_length=200, blank=True)
    display_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["display_order", "name"]

    def __str__(self):
        return self.name


class SectorItem(models.Model):
    """One line in a sector's dropdown. Points at a real catalog.Service;
    `label` is what the website shows (e.g. "Electrician" for the service
    named "Electrical Services")."""

    sector = models.ForeignKey(Sector, on_delete=models.CASCADE, related_name="items")
    service = models.ForeignKey("catalog.Service", on_delete=models.PROTECT, related_name="sector_items")
    label = models.CharField(max_length=100)
    display_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["display_order", "label"]
        constraints = [
            models.UniqueConstraint(fields=["sector", "label"], name="unique_label_per_sector"),
        ]

    def __str__(self):
        return f"{self.sector.name}: {self.label}"
