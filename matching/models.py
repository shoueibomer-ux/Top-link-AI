from django.db import models


class Category(models.Model):
    """Controlled taxonomy — edit this table anytime without touching code."""
    name = models.CharField(max_length=100, unique=True)
    keywords = models.JSONField(default=list, blank=True)  # used by ai_categorize() fallback/seed

    class Meta:
        verbose_name_plural = "categories"

    def __str__(self):
        return self.name


class Profile(models.Model):
    ROLE_CHOICES = [("business", "Business"), ("individual", "Individual")]

    name = models.CharField(max_length=200)
    role = models.CharField(max_length=20, choices=ROLE_CHOICES)
    description = models.TextField(blank=True)          # free text, AI reads this
    categories = models.ManyToManyField(Category, blank=True)  # AI-assigned
    lat = models.FloatField()
    lng = models.FloatField()
    available = models.BooleanField(default=True)
    rating = models.FloatField(default=0.0)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name


class MatchRequest(models.Model):
    requester = models.ForeignKey(Profile, on_delete=models.CASCADE, related_name="requests_made")
    request_text = models.TextField()                   # free text, AI reads this
    categories = models.ManyToManyField(Category, blank=True)  # AI-assigned
    lat = models.FloatField()
    lng = models.FloatField()
    max_distance_km = models.FloatField(default=25.0)
    created_at = models.DateTimeField(auto_now_add=True)
