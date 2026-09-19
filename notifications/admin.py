from django.contrib import admin

from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("id", "device_id", "title", "is_read", "created_at")
    list_filter = ("is_read",)
    search_fields = ("device_id", "title", "body")
    date_hierarchy = "created_at"
