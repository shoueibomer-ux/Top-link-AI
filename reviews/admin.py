from django.contrib import admin
from django.utils import timezone

from .models import Favorite, Review, ReviewReport


def _hide(review, reason):
    review.hidden = True
    review.hidden_reason = reason[:200]
    review.hidden_at = timezone.now()
    review.save(update_fields=["hidden", "hidden_reason", "hidden_at"])


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = ("id", "provider", "rating", "short_comment", "client", "hidden", "open_reports", "created_at")
    list_filter = ("hidden", "rating")
    search_fields = ("comment", "reply", "provider__business_name", "client__email")
    readonly_fields = ("offer", "client", "provider", "rating", "comment", "created_at", "updated_at", "edited_at",
                       "reply", "reply_at", "hidden_at")
    fields = ("provider", "client", "offer", "rating", "comment", "created_at", "edited_at", "reply", "reply_at",
              "hidden", "hidden_reason", "hidden_at")
    actions = ["hide_selected", "restore_selected", "clear_reply"]
    list_select_related = ("provider", "client")

    def has_add_permission(self, request):
        return False

    @admin.display(description="Comment")
    def short_comment(self, obj):
        return (obj.comment or "")[:60]

    @admin.display(description="Open reports")
    def open_reports(self, obj):
        return obj.reports.filter(status=ReviewReport.STATUS_OPEN).count()

    @admin.action(description="Hide selected reviews (they stop showing and stop counting toward the rating)")
    def hide_selected(self, request, queryset):
        count = 0
        for review in queryset.filter(hidden=False):
            _hide(review, "Hidden by an admin")
            count += 1
        self.message_user(request, f"Hid {count} review(s).")

    @admin.action(description="Restore selected reviews")
    def restore_selected(self, request, queryset):
        count = queryset.filter(hidden=True).update(hidden=False, hidden_reason="", hidden_at=None)
        self.message_user(request, f"Restored {count} review(s).")

    @admin.action(description="Remove the provider's reply from selected reviews")
    def clear_reply(self, request, queryset):
        count = queryset.exclude(reply="").update(reply="", reply_at=None)
        self.message_user(request, f"Removed {count} reply(ies).")


@admin.register(ReviewReport)
class ReviewReportAdmin(admin.ModelAdmin):
    """The review moderation queue: open reports first, with the review text and who wrote and reported it."""

    list_display = ("id", "status", "reason", "review_rating", "review_text", "author", "reporter", "created_at")
    list_filter = ("status", "reason")
    search_fields = ("review__comment", "reporter__email", "review__client__email", "details")
    readonly_fields = ("review", "reporter", "reason", "details", "created_at", "reviewed_at", "review_text", "author")
    fields = ("status", "reason", "details", "review_text", "author", "review", "reporter", "created_at", "reviewed_at")
    actions = ["hide_review", "dismiss"]
    list_select_related = ("review", "review__client", "reporter")

    def has_add_permission(self, request):
        return False

    @admin.display(description="Stars")
    def review_rating(self, obj):
        return obj.review.rating

    @admin.display(description="Review")
    def review_text(self, obj):
        return obj.review.comment or "(no comment)"

    @admin.display(description="Written by")
    def author(self, obj):
        return obj.review.client

    def _close(self, queryset, status):
        return queryset.filter(status=ReviewReport.STATUS_OPEN).update(status=status, reviewed_at=timezone.now())

    @admin.action(description="Hide the reported review and close the report")
    def hide_review(self, request, queryset):
        for report in queryset.select_related("review"):
            _hide(report.review, f"Reported ({report.get_reason_display()})")
        self._close(queryset, ReviewReport.STATUS_ACTIONED)
        self.message_user(request, f"Hid {queryset.count()} review(s).")

    @admin.action(description="Dismiss (no action needed)")
    def dismiss(self, request, queryset):
        self.message_user(request, f"Dismissed {self._close(queryset, ReviewReport.STATUS_DISMISSED)} report(s).")


@admin.register(Favorite)
class FavoriteAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "provider", "created_at")
    search_fields = ("user__email", "provider__business_name")

    def has_add_permission(self, request):
        return False
