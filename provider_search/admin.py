from django.contrib import admin

from .models import ProviderAvailability, ProviderMatch, ProviderOnboarding, ServiceRequest


@admin.register(ProviderMatch)
class ProviderMatchAdmin(admin.ModelAdmin):
    list_display = (
        "id", "device_id", "provider_name", "category", "city", "status",
        "service_request", "first_unlocked_at", "last_viewed_at",
    )
    list_filter = ("category", "city", "status")
    search_fields = ("device_id", "provider_name", "place_id")
    date_hierarchy = "first_unlocked_at"


@admin.register(ServiceRequest)
class ServiceRequestAdmin(admin.ModelAdmin):
    list_display = (
        "id", "device_id", "category", "city", "job_size", "job_complexity",
        "estimated_team_size", "status", "created_at",
    )
    list_filter = ("category", "city", "job_size", "job_complexity", "status")
    search_fields = ("device_id", "problem_description")
    date_hierarchy = "created_at"


@admin.register(ProviderAvailability)
class ProviderAvailabilityAdmin(admin.ModelAdmin):
    list_display = ("place_id", "is_available_now", "updated_at")
    list_filter = ("is_available_now",)
    search_fields = ("place_id",)


@admin.register(ProviderOnboarding)
class ProviderOnboardingAdmin(admin.ModelAdmin):
    list_display = ("provider_id", "full_name", "city", "completion_percentage", "is_complete", "updated_at")
    search_fields = ("provider_id", "full_name", "email")
