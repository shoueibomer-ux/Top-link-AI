from django.contrib import admin

from .models import ProviderMatch


@admin.register(ProviderMatch)
class ProviderMatchAdmin(admin.ModelAdmin):
    list_display = ("id", "device_id", "provider_name", "category", "city", "first_unlocked_at", "last_viewed_at")
    list_filter = ("category", "city")
    search_fields = ("device_id", "provider_name", "place_id")
    date_hierarchy = "first_unlocked_at"
