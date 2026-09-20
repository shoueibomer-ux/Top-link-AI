from django.contrib import admin

from .models import Sector, SectorItem


class SectorItemInline(admin.TabularInline):
    model = SectorItem
    extra = 0
    autocomplete_fields = ["service"]


@admin.register(Sector)
class SectorAdmin(admin.ModelAdmin):
    list_display = ["name", "slug", "display_order", "is_active"]
    list_filter = ["is_active"]
    search_fields = ["name"]
    inlines = [SectorItemInline]


@admin.register(SectorItem)
class SectorItemAdmin(admin.ModelAdmin):
    list_display = ["label", "sector", "service", "display_order", "is_active"]
    list_filter = ["sector", "is_active"]
    search_fields = ["label", "service__name", "service__slug"]
    autocomplete_fields = ["service"]
