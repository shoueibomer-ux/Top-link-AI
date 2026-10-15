"""Finding or creating the account behind a verified Google sign-in. Shared by
the provider and the client sign-in views, so the same person can never end up
as both."""

from django.contrib.auth import get_user_model
from django.db import transaction

from accounts.models import UserProfile, UserRole

from .google_auth import GoogleUser
from .models import GoogleIdentity

User = get_user_model()

_ROLE_NAMES = {UserRole.PROVIDER: "provider", UserRole.CUSTOMER: "client"}


class AccountConflict(Exception):
    pass


def user_for_google(google_user: GoogleUser, role: str):
    """(user, created) for a verified Google user signing in as `role`
    (UserRole.PROVIDER or UserRole.CUSTOMER). Looks the person up by their
    Google id first, then by a verified email that already belongs to an
    account *of that role*. An email that belongs to the other kind of account
    is refused rather than taken over: one Google account is one role."""
    with transaction.atomic():
        identity = GoogleIdentity.objects.select_related("user").filter(sub=google_user.sub).first()
        if identity:
            user, created = identity.user, False
        else:
            user = User.objects.filter(email__iexact=google_user.email).first()
            created = user is None
            if user is None:
                user = User.objects.create_user(username=google_user.email, email=google_user.email)
                user.set_unusable_password()
                user.save(update_fields=["password"])
                UserProfile.objects.create(user=user, role=role, full_name=google_user.name)
            GoogleIdentity.objects.create(user=user, sub=google_user.sub)

        profile = getattr(user, "profile", None)
        if profile is None or profile.role != role:
            other = _ROLE_NAMES.get(profile.role if profile else None, "different")
            raise AccountConflict(f"This email already belongs to a {other} account. Use a different Google account.")
        if not user.is_active:
            raise AccountConflict("This account has been disabled.")
        return user, created
