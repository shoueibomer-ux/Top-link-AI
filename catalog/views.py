from rest_framework.generics import ListAPIView

from .models import Category
from .serializers import CategorySerializer
from .taxonomy import wants_unlaunched


class CategoryListView(ListAPIView):
    """GET /api/catalog/categories/ — the category -> services tree.

    By default limited to *launched* services (Service.is_launched) and the
    categories that have at least one — what the client-facing app offers.
    `?include_unlaunched=true` returns every active service instead (each
    carries `is_launched`); the app uses it for the full sectors view, with a
    "Coming soon" badge on unlaunched services, and for the provider service
    picker so providers can register for upcoming categories. The website
    reads the full catalog directly and is not affected. Public (gated only
    by the shared API key, same as every other endpoint) and read-only: categories/services are
    managed exclusively through the Django admin (see catalog/admin.py) —
    no code change or rebuild needed to add, edit, or remove one.
    """

    serializer_class = CategorySerializer

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "include_unlaunched": wants_unlaunched(self.request)}

    def get_queryset(self):
        services = {"services__is_active": True}
        if not wants_unlaunched(self.request):
            services["services__is_launched"] = True
        return (
            Category.objects.filter(is_active=True, **services)
            .distinct()
            .prefetch_related("services")
        )
