from rest_framework.permissions import BasePermission

from .models import UserRole


class IsClientAccount(BasePermission):
    """A signed-in client (someone who requests services), not a provider."""

    message = "Only client accounts can do this."

    def has_permission(self, request, view):
        profile = getattr(request.user, "profile", None)
        return bool(profile and profile.role == UserRole.CUSTOMER)
