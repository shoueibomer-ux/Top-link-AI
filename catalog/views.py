from rest_framework.generics import ListAPIView

from .models import Category
from .serializers import CategorySerializer


class CategoryListView(ListAPIView):
    """GET /api/catalog/categories/ — the full category -> services tree for
    the customer-facing categories page and the provider profile's service
    picker. Public (gated only by the shared API key, same as every other
    endpoint) and read-only: categories/services are managed exclusively
    through the Django admin (see catalog/admin.py) — no code change or
    rebuild needed to add, edit, or remove one.
    """

    serializer_class = CategorySerializer

    def get_queryset(self):
        return Category.objects.filter(is_active=True).prefetch_related("services")
