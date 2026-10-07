from django.contrib import admin, messages
from django.db.models import Count, Max
from django.http import HttpResponseRedirect
from django.urls import reverse
from django.utils.html import format_html

from catalog.models import Service

from .models import ProviderOnboarding, ServiceRequest, WaitlistedRequest


@admin.register(ServiceRequest)
class ServiceRequestAdmin(admin.ModelAdmin):
    list_display = (
        "id", "device_id", "category", "city", "phone", "consent_given",
        "urgency", "job_size", "job_complexity", "estimated_team_size", "status", "created_at", "offers_link",
    )
    list_filter = ("category", "city", "consent_given", "urgency", "job_size", "job_complexity", "status")
    search_fields = ("device_id", "phone", "problem_description")
    date_hierarchy = "created_at"
    actions = ["send_to_providers"]

    @admin.display(description="Offers")
    def offers_link(self, obj):
        count = obj.offers.count()
        if not count:
            return "-"
        return format_html('<a href="{}">{} offer{}</a>', reverse("admin:leads_tracker", args=[obj.pk]), count, "" if count == 1 else "s")

    @admin.action(description="Send to providers...")
    def send_to_providers(self, request, queryset):
        """Opens the provider-picking page for one request. Nothing is sent
        from here: that needs a click on the next page."""
        if queryset.count() != 1:
            self.message_user(request, "Select exactly one request to send to providers.", messages.ERROR)
            return None
        return HttpResponseRedirect(reverse("admin:leads_send_to_providers", args=[queryset.get().pk]))


@admin.register(ProviderOnboarding)
class ProviderOnboardingAdmin(admin.ModelAdmin):
    list_display = ("provider_id", "full_name", "city", "completion_percentage", "is_complete", "updated_at")
    search_fields = ("provider_id", "full_name", "email")


@admin.register(WaitlistedRequest)
class WaitlistDemandAdmin(admin.ModelAdmin):
    """Waitlisted requests only, with a demand-per-service table on top (see
    the change_list template). The table is built from the *filtered*
    changelist, so filtering by city narrows it too. Read-only: requests are
    created by the app, not here."""

    change_list_template = "admin/provider_search/waitlistedrequest/change_list.html"
    list_display = ("service_name", "device_id", "phone", "city", "created_at")
    list_filter = ("category", "city")
    search_fields = ("device_id", "phone", "problem_description")
    ordering = ("category", "-created_at")
    date_hierarchy = "created_at"

    def get_queryset(self, request):
        return super().get_queryset(request).filter(status=ServiceRequest.STATUS_WAITLISTED)

    def has_add_permission(self, request):
        return False

    @admin.display(description="Service", ordering="category")
    def service_name(self, obj):
        return dict(Service.objects.values_list("slug", "name")).get(obj.category, obj.category)

    def changelist_view(self, request, extra_context=None):
        response = super().changelist_view(request, extra_context)
        context = getattr(response, "context_data", None)
        if context and "cl" in context:
            services = {s.slug: s for s in Service.objects.all()}
            rows = (
                context["cl"].queryset.order_by()
                .values("category")
                .annotate(requests=Count("id"), devices=Count("device_id", distinct=True), latest=Max("created_at"))
                .order_by("-requests", "category")
            )
            context["demand"] = [
                {
                    **row,
                    "service_name": services[row["category"]].name if row["category"] in services else row["category"],
                    "launched": row["category"] in services and services[row["category"]].is_launched,
                }
                for row in rows
            ]
        return response
