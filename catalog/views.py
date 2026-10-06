from rest_framework.generics import ListAPIView

from .models import Category
from .serializers import CategorySerializer


class CategoryListView(ListAPIView):
    """GET /api/catalog/categories/ — the category -> services tree.

    By default limited to *launched* services (Service.is_launched) and the
    categories that have at least one — what the client-facing app offers.
    `?include_unlaunched=true` returns every active service instead; the
    provider profile's service picker uses it so providers can register for
    upcoming categories and help them reach their launch gate. The website
    reads the full catalog directly and is not affected. Public (gated only
    by the shared API key, same as every other endpoint) and read-only: categories/services are
    managed exclusively through the Django admin (see catalog/admin.py) —
    no code change or rebuild needed to add, edit, or remove one.
    """

    serializer_class = CategorySerializer

    def _include_unlaunched(self):
        return self.request.query_params.get("include_unlaunched", "").lower() in ("1", "true")

    def get_serializer_context(self):
        return {**super().get_serializer_context(), "include_unlaunched": self._include_unlaunched()}

    def get_queryset(self):
        services = {"services__is_active": True}
        if not self._include_unlaunched():
            services["services__is_launched"] = True
        return (
            Category.objects.filter(is_active=True, **services)
            .distinct()
            .prefetch_related("services")
        )
