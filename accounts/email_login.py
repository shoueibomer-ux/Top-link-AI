"""Sign-in with a 6-digit code sent by email, for clients and providers. No passwords.

The person types their email, gets a code, types it back. A new email makes a new account of the role they
are signing in as; an email that already has an account (including one made with Google) signs into that same
account. A code works once, for 10 minutes, and allows 5 wrong tries; sending a new one cancels the old.

The messages never say whether an account exists: asking for a code always answers the same way, and only
someone holding the code learns anything about the account behind the email.

Available when the server can send email (EMAIL_HOST_USER and EMAIL_HOST_PASSWORD are set), and always in
local development, where the code is printed to the console instead of emailed. The app asks
GET /api/accounts/email/status/ and hides "Continue with email" when it is off.
"""

import hashlib
import hmac
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone

from .models import EmailLoginCode, UserProfile, UserRole

logger = logging.getLogger(__name__)
User = get_user_model()

CODE_LIFETIME = timedelta(minutes=10)
MAX_WRONG_TRIES = 5
ROLES = {"customer": UserRole.CUSTOMER, "provider": UserRole.PROVIDER}
_ROLE_NAMES = {UserRole.PROVIDER: "provider", UserRole.CUSTOMER: "client"}


class CodeInvalid(Exception):
    """Wrong, expired, used up, or never sent: deliberately one error for all of them."""


class AccountConflict(Exception):
    pass


def enabled() -> bool:
    return bool(settings.DEBUG or (settings.EMAIL_HOST_USER and settings.EMAIL_HOST_PASSWORD))


def normalize(email) -> str:
    return email.strip().lower() if isinstance(email, str) else ""


def _hash(email: str, code: str) -> str:
    # Keyed with SECRET_KEY, so the stored value is useless without it, and tied to the email.
    return hmac.new(settings.SECRET_KEY.encode(), f"{email}:{code}".encode(), hashlib.sha256).hexdigest()


def send_code(email: str, role: str) -> None:
    """Makes a new code for `email` (cancelling any earlier one) and sends it. Raises on a sending failure."""
    code = f"{secrets.randbelow(1_000_000):06d}"
    now = timezone.now()
    with transaction.atomic():
        EmailLoginCode.objects.filter(email=email, used_at__isnull=True).update(used_at=now)
        EmailLoginCode.objects.create(email=email, role=role, code_hash=_hash(email, code), expires_at=now + CODE_LIFETIME)
    if settings.DEBUG:
        # Local development: no email goes out; the code is right here.
        print(f"[email sign-in] code for {email}: {code} (valid 10 minutes)", flush=True)
        return
    send_mail(
        subject=f"Your Tabmatch sign-in code: {code}",
        message=(
            f"Your Tabmatch sign-in code is {code}\n\n"
            "Type it in the app to sign in. It works once and expires in 10 minutes.\n\n"
            "If you didn't ask for this, ignore this email: nobody can sign in without the code.\n\n"
            "Tabmatch"
        ),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[email],
    )


def check_code(email: str, role: str, code) -> None:
    """Uses up the current code for `email` if `code` matches it. Raises CodeInvalid otherwise."""
    code = code.strip() if isinstance(code, str) else ""
    now = timezone.now()
    # The error is raised only after the transaction commits: raising inside it would roll back the wrong-try
    # count and leave the code open to unlimited guesses.
    with transaction.atomic():
        current = (
            EmailLoginCode.objects.select_for_update()
            .filter(email=email, role=role, used_at__isnull=True, expires_at__gt=now)
            .order_by("-created_at")
            .first()
        )
        if current is None or current.wrong_tries >= MAX_WRONG_TRIES:
            ok = False
        elif len(code) == 6 and code.isdigit() and hmac.compare_digest(current.code_hash, _hash(email, code)):
            ok = True
            current.used_at = now
            current.save(update_fields=["used_at"])
        else:
            ok = False
            current.wrong_tries += 1
            if current.wrong_tries >= MAX_WRONG_TRIES:
                current.used_at = now
            current.save(update_fields=["wrong_tries", "used_at"])
    if not ok:
        raise CodeInvalid


def user_for_email(email: str, role: str):
    """(user, created) for someone who has just proved they own `email`, signing in as `role`."""
    with transaction.atomic():
        user = User.objects.filter(email__iexact=email).select_related("profile").first()
        created = user is None
        if user is None:
            user = User.objects.create_user(username=email, email=email)
            user.set_unusable_password()
            user.save(update_fields=["password"])
            UserProfile.objects.create(user=user, role=role)
        profile = getattr(user, "profile", None)
        if profile is None or profile.role != role:
            other = _ROLE_NAMES.get(profile.role if profile else None, "different")
            raise AccountConflict(f"This email already belongs to a {other} account.")
        if not user.is_active:
            raise AccountConflict("This account has been disabled.")
        return user, created
