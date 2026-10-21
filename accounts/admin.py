from django.contrib import admin, messages
from django.template.response import TemplateResponse

from .deletion import AccountNotDeletable, delete_account, is_deleted
from .models import AccountDeletion, UserProfile


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "role", "full_name", "created_at")
    list_filter = ("role",)
    search_fields = ("user__email", "full_name")
    actions = ["delete_accounts"]

    @admin.action(description="Delete the selected accounts (anonymise their personal data; cannot be undone)", permissions=["delete"])
    def delete_accounts(self, request, queryset):
        """For a deletion request that arrived by email. Asks first, then does exactly what the app's
        "Delete my account" does (see accounts.deletion)."""
        profiles = list(queryset.select_related("user"))
        if request.POST.get("confirm_delete") != "yes":
            return TemplateResponse(
                request,
                "admin/accounts/delete_accounts_confirmation.html",
                {
                    **self.admin_site.each_context(request),
                    "title": "Delete these accounts?",
                    "profiles": profiles,
                    "opts": self.model._meta,
                    "action_checkbox_name": admin.helpers.ACTION_CHECKBOX_NAME,
                },
            )
        done = skipped = 0
        for profile in profiles:
            if is_deleted(profile.user):
                skipped += 1
                continue
            try:
                delete_account(profile.user, via=AccountDeletion.VIA_ADMIN)
                done += 1
            except AccountNotDeletable:
                skipped += 1
        self.message_user(request, f"Deleted {done} account(s). Skipped {skipped} (staff, or already deleted).", messages.SUCCESS)


@admin.register(AccountDeletion)
class AccountDeletionAdmin(admin.ModelAdmin):
    """The record that deletions happened. It holds no personal data and cannot be edited."""

    list_display = ("user_id", "role", "via", "deleted_at")
    list_filter = ("via", "role")
    readonly_fields = ("user_id", "role", "via", "deleted_at")

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
