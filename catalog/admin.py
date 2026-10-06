from django.contrib import admin

from .models import Category, Service


class ServiceInline(admin.TabularInline):
    model = Service
    extra = 0
    fields = ["name", "slug", "icon_name", "worker_noun", "google_places_query", "display_order", "is_active", "is_launched"]


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name", "slug", "display_order", "is_active"]
    list_filter = ["is_active"]
    search_fields = ["name", "slug"]
    inlines = [ServiceInline]


@admin.register(Service)
class ServiceAdmin(admin.ModelAdmin):
    list_display = ["name", "slug", "category", "display_order", "is_active", "is_launched"]
    list_filter = ["category", "is_active", "is_launched"]
    list_editable = ["is_launched"]
    search_fields = ["name", "slug"]
