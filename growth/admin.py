from django.contrib import admin
from django.template.response import TemplateResponse

from .dashboard import weekly_report
from .models import GrowthReport, InviteCode, InviteSignup, ReminderPreference, ReminderSend


class _ReadOnly(admin.ModelAdmin):
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(GrowthReport)
class GrowthReportAdmin(_ReadOnly):
    """The growth dashboard instead of a list: requests per week by source,
    and how many were accepted and completed."""

    def has_delete_permission(self, request, obj=None):
        return False

    def changelist_view(self, request, extra_context=None):
        try:
            weeks = min(max(int(request.GET.get("weeks", 12)), 1), 52)
        except ValueError:
            weeks = 12
        context = {
            **self.admin_site.each_context(request),
            "title": "Growth dashboard",
            "opts": self.model._meta,
            "report": weekly_report(weeks),
            "week_choices": [4, 12, 26, 52],
        }
        return TemplateResponse(request, "admin/growth/dashboard.html", context)


@admin.register(InviteCode)
class InviteCodeAdmin(_ReadOnly):
    list_display = ("code", "user", "signup_count", "created_at")
    search_fields = ("code", "user__email")

    @admin.display(description="Sign-ups")
    def signup_count(self, obj):
        return obj.signups.count()


@admin.register(InviteSignup)
class InviteSignupAdmin(_ReadOnly):
    list_display = ("invitee", "code", "shared_provider", "created_at")
    search_fields = ("code", "invitee__email")
    date_hierarchy = "created_at"


@admin.register(ReminderSend)
class ReminderSendAdmin(_ReadOnly):
    list_display = ("sent_at", "user", "campaign", "service", "push_count", "email_sent", "note")
    list_filter = ("campaign", "email_sent", "season_year")
    search_fields = ("user__email",)
    date_hierarchy = "sent_at"


@admin.register(ReminderPreference)
class ReminderPreferenceAdmin(admin.ModelAdmin):
    list_display = ("user", "seasonal_reminders", "changed_via", "updated_at")
    list_filter = ("seasonal_reminders", "changed_via")
    search_fields = ("user__email",)
    raw_id_fields = ("user",)
    readonly_fields = ("changed_via", "updated_at")

    def save_model(self, request, obj, form, change):
        obj.changed_via = ReminderPreference.VIA_ADMIN
        super().save_model(request, obj, form, change)
