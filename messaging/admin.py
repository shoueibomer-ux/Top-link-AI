from django.contrib import admin, messages
from django.utils import timezone
from django.utils.html import format_html

from . import storage
from .models import (
    ChatTermsAcceptance,
    Conversation,
    DeviceToken,
    Message,
    MessageReport,
    PhotoDeletion,
    UserBlock,
)


def _hide(message, reason):
    message.hidden = True
    message.hidden_reason = reason[:200]
    message.hidden_at = timezone.now()
    message.save(update_fields=["hidden", "hidden_reason", "hidden_at"])


class MessageInline(admin.TabularInline):
    model = Message
    extra = 0
    can_delete = False
    fields = ("id", "sender", "body", "photo_key", "hidden", "created_at")
    readonly_fields = fields

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    """Read-only: staff can read a conversation when reviewing a report, not write in it."""

    list_display = ("id", "offer", "client_email", "provider_name", "message_count", "created_at")
    search_fields = ("offer__provider__business_name", "offer__service_request__user__email")
    inlines = [MessageInline]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    @admin.display(description="Client")
    def client_email(self, obj):
        return obj.client.email if obj.client else ""

    @admin.display(description="Provider")
    def provider_name(self, obj):
        return obj.offer.provider.business_name

    @admin.display(description="Messages")
    def message_count(self, obj):
        return obj.messages.count()


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("id", "conversation", "sender", "short_body", "has_photo", "hidden", "created_at")
    list_filter = ("hidden",)
    search_fields = ("body", "sender__email")
    readonly_fields = ("conversation", "sender", "body", "photo_key", "photo", "created_at", "hidden_at")
    actions = ["hide_selected", "restore_selected"]

    def has_add_permission(self, request):
        return False

    @admin.display(description="Message")
    def short_body(self, obj):
        return (obj.body or "")[:60]

    @admin.display(boolean=True, description="Photo")
    def has_photo(self, obj):
        return bool(obj.photo_key)

    @admin.display(description="Photo (opens a 15-minute private link)")
    def photo(self, obj):
        if obj.photo_key and storage.configured():
            return format_html('<a href="{}" target="_blank" rel="noopener">View photo</a>', storage.presign_get(obj.photo_key))
        return "-"

    @admin.action(description="Hide selected messages (they show as removed)")
    def hide_selected(self, request, queryset):
        count = 0
        for message in queryset.filter(hidden=False):
            _hide(message, "Hidden by an admin")
            count += 1
        self.message_user(request, f"Hid {count} message(s).")

    @admin.action(description="Restore selected messages")
    def restore_selected(self, request, queryset):
        count = queryset.filter(hidden=True).update(hidden=False, hidden_reason="", hidden_at=None)
        self.message_user(request, f"Restored {count} message(s).")


@admin.register(MessageReport)
class MessageReportAdmin(admin.ModelAdmin):
    """The moderation queue: open reports first, with the message, who wrote it and who reported it."""

    list_display = ("id", "status", "reason", "reported_message", "sender", "reporter", "created_at")
    list_filter = ("status", "reason")
    search_fields = ("message__body", "reporter__email", "message__sender__email", "details")
    readonly_fields = ("message", "reporter", "reason", "details", "created_at", "reviewed_at", "message_text",
                       "message_sender", "conversation_link")
    fields = ("status", "reason", "details", "message_text", "message_sender", "conversation_link", "reporter",
              "created_at", "reviewed_at")
    actions = ["hide_message", "suspend_sender", "dismiss"]
    list_select_related = ("message", "message__sender", "reporter")

    def has_add_permission(self, request):
        return False

    @admin.display(description="Message")
    def reported_message(self, obj):
        return (obj.message.body or "[photo]")[:60]

    @admin.display(description="Written by")
    def sender(self, obj):
        return obj.message.sender

    @admin.display(description="Message text")
    def message_text(self, obj):
        return obj.message.body or "[photo]"

    @admin.display(description="Written by")
    def message_sender(self, obj):
        return obj.message.sender

    @admin.display(description="Conversation")
    def conversation_link(self, obj):
        from django.urls import reverse

        return format_html('<a href="{}">Open the conversation</a>', reverse("admin:messaging_conversation_change", args=[obj.message.conversation_id]))

    def _close(self, queryset, status):
        return queryset.filter(status=MessageReport.STATUS_OPEN).update(status=status, reviewed_at=timezone.now())

    @admin.action(description="Hide the reported message and close the report")
    def hide_message(self, request, queryset):
        for report in queryset:
            _hide(report.message, f"Reported ({report.get_reason_display()})")
        self._close(queryset, MessageReport.STATUS_ACTIONED)
        self.message_user(request, f"Hid {queryset.count()} message(s).")

    @admin.action(description="Suspend the sender's account, hide the message and close the report")
    def suspend_sender(self, request, queryset):
        suspended = 0
        for report in queryset.select_related("message__sender"):
            sender = report.message.sender
            _hide(report.message, f"Reported ({report.get_reason_display()})")
            if sender is not None and not sender.is_superuser and sender.is_active:
                sender.is_active = False  # they can no longer sign in or send
                sender.save(update_fields=["is_active"])
                suspended += 1
        self._close(queryset, MessageReport.STATUS_ACTIONED)
        self.message_user(request, f"Suspended {suspended} account(s). Staff accounts are never suspended here.", level=messages.WARNING)

    @admin.action(description="Dismiss (no action needed)")
    def dismiss(self, request, queryset):
        self.message_user(request, f"Dismissed {self._close(queryset, MessageReport.STATUS_DISMISSED)} report(s).")


@admin.register(PhotoDeletion)
class PhotoDeletionAdmin(admin.ModelAdmin):
    """Photos waiting to be removed from the bucket (see `manage.py purge_photo_queue`). Empty is the healthy state."""

    list_display = ("key", "created_at", "attempts", "last_error")
    readonly_fields = ("key", "created_at", "attempts", "last_error")

    def has_add_permission(self, request):
        return False


@admin.register(UserBlock)
class UserBlockAdmin(admin.ModelAdmin):
    list_display = ("id", "blocker", "blocked", "created_at")
    search_fields = ("blocker__email", "blocked__email")

    def has_add_permission(self, request):
        return False


@admin.register(ChatTermsAcceptance)
class ChatTermsAcceptanceAdmin(admin.ModelAdmin):
    list_display = ("user", "accepted_at")
    search_fields = ("user__email",)

    def has_add_permission(self, request):
        return False


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "updated_at")  # the token itself is never shown
    search_fields = ("user__email",)
    exclude = ("token",)

    def has_add_permission(self, request):
        return False
