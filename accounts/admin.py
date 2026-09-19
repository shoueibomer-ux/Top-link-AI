from django.contrib import admin

from .models import ProviderBusinessProfile, UserProfile


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "role", "full_name", "created_at")
    list_filter = ("role",)
    search_fields = ("user__email", "full_name")


@admin.register(ProviderBusinessProfile)
class ProviderBusinessProfileAdmin(admin.ModelAdmin):
    list_display = (
        "business_name", "user", "provider_type", "city", "place_id", "is_available_now", "rating", "updated_at",
    )
    list_filter = ("city", "provider_type", "is_available_now")
    search_fields = ("business_name", "user__email", "place_id")
