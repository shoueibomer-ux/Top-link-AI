"""Deleting an account.

Google Play and the App Store require it, and people have a right to it (PIPEDA). This is the one place that
does it, whether the person taps "Delete my account" in the app, staff do it from the admin for someone who
emailed us, or an operator runs `manage.py delete_account`.

What happens, and why the User row itself is kept:

  Removed outright   chat conversations and every message in them (and their photos in the private R2 bucket,
                     through a retry queue), push-notification tokens, saved providers, blocks, the chat-rules
                     agreement, the link to their Google account, and request notifications.
  Blanked            the name and email on the account, a client's request details (phone, description, where
                     the job is, device id), a provider's business name, phone, email, bio, cities, notes and
                     replies to reviews, and a provider's replies to a deleted client's review. The account can no
                     longer sign in.
  Kept, anonymised   the request rows and lead offers (counts, categories, cities, timing, what happened),
                     the reviews a client wrote (rating and comment, shown as "A client" with no name), and a
                     provider's profile shell so their reviews and offers keep making sense ("Deleted provider").

The User row stays, anonymised and inactive, because a provider's profile hangs off it and offers must keep a
provider. After this nothing on it identifies the person: no name, no email, no phone, no Google id.
"""

import logging
from dataclasses import dataclass

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from leads.models import LeadOffer
from messaging import photo_queue
from messaging.models import (
    ChatTermsAcceptance,
    Conversation,
    DeviceToken,
    Message,
    MessageReport,
    UserBlock,
)
from notifications.models import Notification
from provider_search.models import ServiceRequest
from providers.models import GoogleIdentity, ProviderProfile
from reviews.models import Favorite, Review, ReviewReport

from .models import AccountDeletion, UserProfile

logger = logging.getLogger(__name__)
User = get_user_model()

DELETED_EMAIL_DOMAIN = "deleted.invalid"
DELETED_PROVIDER_NAME = "Deleted provider"
CONFIRM_WORD = "DELETE"

# Offers still waiting on someone: closed, so nobody is asked to answer a request whose person is gone.
_OPEN_OFFER_STATUSES = [LeadOffer.STATUS_PENDING, LeadOffer.STATUS_SENT, LeadOffer.STATUS_VIEWED]


class AccountNotDeletable(Exception):
    """Staff accounts are not deleted this way."""


@dataclass(frozen=True)
class DeletionSummary:
    already_deleted: bool = False
    conversations: int = 0
    messages: int = 0
    photos_found: int = 0
    photos_deleted: int = 0
    photos_waiting: int = 0


def is_deleted(user) -> bool:
    return user.email.endswith(f"@{DELETED_EMAIL_DOMAIN}")


def delete_account(user, via: str = AccountDeletion.VIA_APP) -> DeletionSummary:
    if user.is_superuser or user.is_staff:
        raise AccountNotDeletable("Staff accounts can't be deleted here.")
    if is_deleted(user):
        return DeletionSummary(already_deleted=True)

    now = timezone.now()
    with transaction.atomic():
        user = User.objects.select_for_update().get(pk=user.pk)
        role = getattr(getattr(user, "profile", None), "role", "") or ""
        provider = ProviderProfile.objects.filter(user=user).first()

        # Chats: the whole conversation goes (the other person loses that thread too), with its photos.
        conversations = Conversation.objects.filter(
            Q(offer__service_request__user=user) | Q(offer__provider__user=user)
        )
        messages = Message.objects.filter(conversation__in=conversations)
        photo_keys = list(messages.exclude(photo_key="").values_list("photo_key", flat=True))
        photo_queue.queue_photos(photo_keys)  # recorded before anything is removed
        message_count = messages.count()
        conversation_count = conversations.count()
        conversations.delete()  # messages, read markers and reports about those messages go with it

        DeviceToken.objects.filter(user=user).delete()
        ChatTermsAcceptance.objects.filter(user=user).delete()
        UserBlock.objects.filter(Q(blocker=user) | Q(blocked=user)).delete()
        Favorite.objects.filter(user=user).delete()
        GoogleIdentity.objects.filter(user=user).delete()
        # A provider's reply to their review can use their name: the reply goes, the review stays.
        Review.objects.filter(client=user).update(reply="", reply_at=None)
        # Free text they wrote when reporting something: the report stays, their words go.
        MessageReport.objects.filter(reporter=user).update(details="")
        ReviewReport.objects.filter(reporter=user).update(details="")

        # A client's requests: keep the row, drop what identifies the person or the place.
        requests = ServiceRequest.objects.filter(user=user)
        device_ids = {d for d in requests.values_list("device_id", flat=True) if d}
        LeadOffer.objects.filter(service_request__in=requests, status__in=_OPEN_OFFER_STATUSES).update(
            status=LeadOffer.STATUS_EXPIRED
        )
        requests.filter(no_yes_alert_sent_at__isnull=True).update(no_yes_alert_sent_at=now)  # no "no YES yet" alert
        requests.update(
            phone="",
            problem_description="",
            location="",
            device_id="",
            required_skills=[],
            required_equipment=[],
            required_qualifications=[],
        )
        if device_ids:
            Notification.objects.filter(device_id__in=device_ids).delete()

        # A provider: the profile becomes an anonymous shell.
        if provider is not None:
            LeadOffer.objects.filter(provider=provider, status__in=_OPEN_OFFER_STATUSES).update(
                status=LeadOffer.STATUS_EXPIRED
            )
            Favorite.objects.filter(provider=provider).delete()
            Review.objects.filter(provider=provider).update(reply="", reply_at=None)
            provider.categories.clear()
            ProviderProfile.objects.filter(pk=provider.pk).update(
                business_name=DELETED_PROVIDER_NAME,
                phone="",
                email="",
                bio="",
                cities=[],
                waitlist_cities=[],
                notes="",
                review_note="",
                sms_opt_out=True,  # never text this number again
                status=ProviderProfile.STATUS_REJECTED,
            )

        # The account itself: nothing left that names the person, and it can't sign in.
        user.username = f"deleted-{user.pk}"
        user.email = f"deleted-{user.pk}@{DELETED_EMAIL_DOMAIN}"
        user.first_name = ""
        user.last_name = ""
        user.is_active = False
        user.last_login = None
        user.set_unusable_password()
        user.save()
        UserProfile.objects.filter(user=user).update(full_name="")
        AccountDeletion.objects.create(user_id=user.pk, role=role, via=via)

    # After the database change is safe: remove the photos (any that fail stay queued for a retry).
    deleted, waiting = photo_queue.purge(photo_keys) if photo_keys else (0, 0)
    logger.info("Deleted account %s (%s) via %s", user.pk, role or "no role", via)
    return DeletionSummary(
        conversations=conversation_count,
        messages=message_count,
        photos_found=len(photo_keys),
        photos_deleted=deleted,
        photos_waiting=waiting,
    )
