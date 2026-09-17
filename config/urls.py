from django.contrib import admin
from django.urls import include, path

from provider_search.views import ProviderSearchView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("matching.urls")),
    path("api/providers/search/", ProviderSearchView.as_view(), name="provider-search"),
]
