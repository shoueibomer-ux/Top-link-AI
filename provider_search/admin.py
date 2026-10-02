from django.contrib import admin

from .models import ProviderOnboarding, ServiceRequest


@admin.register(ServiceRequest)
class ServiceRequestAdmin(admin.ModelAdmin):
    list_display = (
        "id", "device_id", "category", "city", "phone", "consent_given",
        "job_size", "job_complexity", "estimated_team_size", "status", "created_at",
    )
    list_filter = ("category", "city", "consent_given", "job_size", "job_complexity", "status")
    search_fields = ("device_id", "phone", "problem_description")
    date_hierarchy = "created_at"


@admin.register(ProviderOnboarding)
class ProviderOnboardingAdmin(admin.ModelAdmin):
    list_display = ("provider_id", "full_name", "city", "completion_percentage", "is_complete", "updated_at")
    search_fields = ("provider_id", "full_name", "email")
