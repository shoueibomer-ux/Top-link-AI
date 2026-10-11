from django.contrib import admin

from .models import UserProfile


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "role", "full_name", "created_at")
    list_filter = ("role",)
    search_fields = ("user__email", "full_name")
