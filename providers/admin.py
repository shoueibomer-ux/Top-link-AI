from django import forms
from django.contrib import admin, messages

from provider_search.services import CITIES

from .models import ProviderProfile


class ProviderProfileForm(forms.ModelForm):
    cities = forms.MultipleChoiceField(
        choices=[(city, city) for city in CITIES], required=False, widget=forms.CheckboxSelectMultiple
    )

    class Meta:
        model = ProviderProfile
        fields = "__all__"


@admin.register(ProviderProfile)
class ProviderProfileAdmin(admin.ModelAdmin):
    form = ProviderProfileForm
    list_display = ("business_name", "status", "phone", "email", "city_list", "category_list", "created_at")
    list_filter = ("status", "categories")
    search_fields = ("business_name", "email", "phone", "user__email")
    readonly_fields = ("user", "reviewed_at", "created_at", "updated_at")
    filter_horizontal = ("categories",)
    date_hierarchy = "created_at"
    actions = ["approve_selected", "reject_selected"]

    @admin.display(description="Cities")
    def city_list(self, obj):
        return ", ".join(obj.cities or [])

    @admin.display(description="Services")
    def category_list(self, obj):
        return ", ".join(s.name for s in obj.categories.all())

    @admin.action(description="Approve selected providers")
    def approve_selected(self, request, queryset):
        profiles = list(queryset)
        for profile in profiles:
            profile.approve()
        self.message_user(request, f"Approved {len(profiles)} provider(s). They can now be matched with clients.")

    @admin.action(description="Reject selected providers")
    def reject_selected(self, request, queryset):
        profiles = list(queryset)
        for profile in profiles:
            profile.reject()
        self.message_user(
            request,
            f"Rejected {len(profiles)} provider(s). Add a note in each profile to tell them why.",
            level=messages.WARNING,
        )
