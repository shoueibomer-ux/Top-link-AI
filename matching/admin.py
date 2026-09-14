from django.contrib import admin

from .models import Category, MatchRequest, Profile, Subscription


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ("id", "name")
    search_fields = ("name",)


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "role", "rating", "available", "lat", "lng", "created_at")
    list_filter = ("role", "available", "categories")
    search_fields = ("name", "description")
    filter_horizontal = ("categories",)
    date_hierarchy = "created_at"


@admin.register(MatchRequest)
class MatchRequestAdmin(admin.ModelAdmin):
    list_display = ("id", "requester", "request_text_preview", "lat", "lng", "max_distance_km", "created_at")
    list_filter = ("categories",)
    search_fields = ("request_text", "requester__name")
    filter_horizontal = ("categories",)
    date_hierarchy = "created_at"

    @admin.display(description="Request text")
    def request_text_preview(self, obj):
        text = obj.request_text
        return text if len(text) <= 60 else f"{text[:60]}…"


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ("id", "device_id", "status", "start_date", "expiry_date", "updated_at")
    list_filter = ("status",)
    search_fields = ("device_id",)
    date_hierarchy = "created_at"
