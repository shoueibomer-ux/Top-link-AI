from django.conf import settings
from django.db import transaction
from django.db.models import F, Max, Q
from django.utils.decorators import method_decorator
from django_ratelimit.decorators import ratelimit
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from catalog.models import Service
from leads.models import LeadOffer
from matching.permissions import HasApiKey

from . import push, storage
from .models import (
    ChatTermsAcceptance,
    Conversation,
    ConversationRead,
    DeviceToken,
    Message,
    MessageReport,
    UserBlock,
)

MAX_BODY_CHARS = 2000
PAGE_SIZE = 50
CATCH_UP_LIMIT = 200
_SEND_RATE = "30/m"

CHAT_TERMS_TEXT = (
    "Be respectful and keep it about the job. Don't send anything illegal, abusive, threatening or misleading. "
    "Messages and photos can be reported, and Tabmatch can review reported messages. Accounts that break these "
    "rules can be suspended."
)
NOT_ALLOWED = "You can't send messages in this conversation."


class ChatView(APIView):
    """Every chat endpoint needs the API key and a signed-in person; who may see a given conversation is
    decided by `conversation_for`, never by the URL alone."""

    permission_classes = [HasApiKey, IsAuthenticated]

    @staticmethod
    def conversation_for(user, pk):
        """The conversation, but only if `user` is one of its two people. Anyone else gets None, which the
        views answer with the same 404 as a conversation that does not exist."""
        conversation = (
            Conversation.objects.filter(pk=pk)
            .filter(Q(offer__service_request__user=user) | Q(offer__provider__user=user))
            .select_related("offer", "offer__provider", "offer__provider__user", "offer__service_request",
                            "offer__service_request__user", "offer__service_request__user__profile")
            .first()
        )
        return conversation


def _not_found():
    return Response({"detail": "Conversation not found."}, status=404)


# ---- helpers ------------------------------------------------------------------------------------

def blocked_between(user_a, user_b) -> bool:
    return UserBlock.objects.filter(
        Q(blocker=user_a, blocked=user_b) | Q(blocker=user_b, blocked=user_a)
    ).exists()


def terms_accepted(user) -> bool:
    return ChatTermsAcceptance.objects.filter(user=user).exists()


def unread_count(conversation, user) -> int:
    read = ConversationRead.objects.filter(conversation=conversation, user=user).first()
    return (
        conversation.messages.filter(hidden=False, id__gt=read.last_read_id if read else 0)
        .exclude(sender=user)
        .count()
    )


def mark_read(conversation, user, up_to_id=None) -> None:
    latest = conversation.messages.aggregate(m=Max("id"))["m"] or 0
    target = latest if up_to_id is None else min(int(up_to_id), latest)
    read, _ = ConversationRead.objects.get_or_create(conversation=conversation, user=user)
    if target > read.last_read_id:
        read.last_read_id = target
        read.save(update_fields=["last_read_id"])


def serialize_message(message, viewer) -> dict:
    data = {
        "id": message.id,
        "mine": message.sender_id == viewer.pk,
        "created_at": message.created_at,
        "removed": message.hidden,
        "body": "",
        "photo_url": None,
    }
    if message.hidden:
        return data  # shows as "removed by a moderator"; nothing of it is delivered
    data["body"] = message.body
    if message.photo_key and storage.configured():
        data["photo_url"] = storage.presign_get(message.photo_key)
    return data


def serialize_conversation(conversation, viewer, service_names=None) -> dict:
    offer = conversation.offer
    last = conversation.messages.filter(hidden=False).order_by("-id").first()
    return {
        "id": conversation.id,
        "offer_id": offer.id,
        "request_id": offer.service_request_id,
        "other_name": conversation.display_name_for(viewer),
        "request_summary": conversation.request_summary(service_names),
        "unread_count": unread_count(conversation, viewer),
        "last_message": (
            {"preview": last.body[:80] if last.body else "Photo", "created_at": last.created_at, "mine": last.sender_id == viewer.pk}
            if last
            else None
        ),
        "blocked_by_me": UserBlock.objects.filter(blocker=viewer, blocked=conversation.other_user(viewer)).exists(),
    }


# ---- terms and devices ----------------------------------------------------------------------------

class TermsView(ChatView):
    """GET says whether this person has agreed to the chat rules (and what they are); POST records it."""

    def get(self, request):
        return Response({"accepted": terms_accepted(request.user), "text": CHAT_TERMS_TEXT})

    def post(self, request):
        ChatTermsAcceptance.objects.get_or_create(user=request.user)
        return Response({"accepted": True, "text": CHAT_TERMS_TEXT})


class DeviceView(ChatView):
    """POST {"token", "platform"} registers this phone for push; DELETE {"token"} (on sign-out) removes it."""

    def post(self, request):
        token = request.data.get("token")
        platform = request.data.get("platform") or "android"
        if not isinstance(token, str) or not token.strip() or len(token) > 300:
            return Response({"detail": "token is required."}, status=400)
        if not isinstance(platform, str) or len(platform) > 20:
            return Response({"detail": "platform is not valid."}, status=400)
        # A token belongs to whoever signed in on that phone last.
        DeviceToken.objects.update_or_create(token=token.strip(), defaults={"user": request.user, "platform": platform})
        return Response({"registered": True})

    def delete(self, request):
        token = request.data.get("token")
        if isinstance(token, str):
            DeviceToken.objects.filter(token=token, user=request.user).delete()
        return Response({"registered": False})


# ---- conversations ---------------------------------------------------------------------------------

class ConversationListView(ChatView):
    """GET /api/conversations/: this person's chats with unread counts. The app maps them to History
    cards and the provider's leads by offer_id."""

    def get(self, request):
        conversations = (
            Conversation.objects.filter(Q(offer__service_request__user=request.user) | Q(offer__provider__user=request.user))
            .select_related("offer", "offer__provider", "offer__service_request", "offer__service_request__user",
                            "offer__service_request__user__profile")
            .annotate(latest=Max("messages__id"))
            .order_by(F("latest").desc(nulls_last=True), "-id")
        )
        service_names = dict(Service.objects.values_list("slug", "name"))
        items = [serialize_conversation(c, request.user, service_names) for c in conversations]
        return Response({"conversations": items, "total_unread": sum(i["unread_count"] for i in items)})


class ConversationOpenView(ChatView):
    """POST {"offer_id"}: starts (or returns) the chat for an offer that was accepted. Only the offer's
    client or provider can open it; for anyone else it is a 404."""

    def post(self, request):
        offer_id = request.data.get("offer_id")
        offer = None
        if isinstance(offer_id, int) and not isinstance(offer_id, bool):
            offer = (
                # A request with no signed-in owner (from before sign-in existed) has nobody to talk to.
                LeadOffer.objects.filter(
                    pk=offer_id,
                    status=LeadOffer.STATUS_ACCEPTED,
                    service_request__user__isnull=False,
                    # nobody to talk to once either account has been deleted
                    service_request__user__is_active=True,
                    provider__user__is_active=True,
                )
                .filter(Q(service_request__user=request.user) | Q(provider__user=request.user))
                .first()
            )
        if offer is None:
            return Response({"detail": "Conversation not found."}, status=404)
        conversation, _ = Conversation.objects.get_or_create(offer=offer)
        conversation = self.conversation_for(request.user, conversation.pk)
        return Response({**serialize_conversation(conversation, request.user), "terms_accepted": terms_accepted(request.user)})


class MessageListView(ChatView):
    """GET ?since_id=N: messages after N (oldest first), or the latest page if since_id is missing.
    POST: send a message (text and/or an uploaded photo)."""

    def get(self, request, conversation_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        since = request.query_params.get("since_id")
        queryset = conversation.messages.all()
        if since is not None:
            try:
                messages = list(queryset.filter(id__gt=int(since))[:CATCH_UP_LIMIT])
            except ValueError:
                return Response({"detail": "since_id must be a number."}, status=400)
        else:
            messages = list(reversed(list(queryset.order_by("-id")[:PAGE_SIZE])))
        other = conversation.other_user(request.user)
        return Response({
            "messages": [serialize_message(m, request.user) for m in messages],
            "other_name": conversation.display_name_for(request.user),
            "request_summary": conversation.request_summary(),
            "blocked_by_me": UserBlock.objects.filter(blocker=request.user, blocked=other).exists(),
            "can_send": not blocked_between(request.user, other),
            "terms_accepted": terms_accepted(request.user),
            "photos_enabled": storage.configured(),
        })

    @method_decorator(ratelimit(key="user_or_ip", rate=_SEND_RATE, method="POST", block=False))
    def post(self, request, conversation_id):
        if getattr(request, "limited", False):
            return Response({"detail": "You're sending messages too fast. Wait a moment and try again."}, status=429)
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        if not terms_accepted(request.user):
            return Response({"detail": "Agree to the chat rules first.", "code": "terms_required"}, status=403)
        if blocked_between(request.user, conversation.other_user(request.user)):
            return Response({"detail": NOT_ALLOWED}, status=403)

        body = request.data.get("body")
        body = body.strip() if isinstance(body, str) else ""
        photo_key = request.data.get("photo_key") or ""
        if not isinstance(photo_key, str):
            return Response({"detail": "photo_key is not valid."}, status=400)
        if not body and not photo_key:
            return Response({"detail": "Write a message or add a photo."}, status=400)
        if len(body) > MAX_BODY_CHARS:
            return Response({"detail": f"Messages can be at most {MAX_BODY_CHARS} characters."}, status=400)
        if photo_key:
            problem = self._photo_problem(conversation, photo_key)
            if problem:
                return Response({"detail": problem}, status=400)

        message = Message.objects.create(
            conversation=conversation, sender=request.user, body=body, photo_key=photo_key
        )
        mark_read(conversation, request.user)
        transaction.on_commit(lambda: push.notify_new_message(message))
        return Response(serialize_message(message, request.user), status=201)

    @staticmethod
    def _photo_problem(conversation, key):
        if not storage.configured():
            return "Photos aren't available right now."
        if not key.startswith(f"chat/{conversation.pk}/"):
            return "That photo doesn't belong to this conversation."  # never someone else's upload
        info = storage.head(key)
        if info is None:
            return "The photo didn't finish uploading. Try again."
        if info["size"] > settings.CHAT_PHOTO_MAX_BYTES or info["content_type"] not in storage.ALLOWED_TYPES:
            storage.delete(key)
            return "That photo is too large or not a supported image."
        return None


class PhotoUploadView(ChatView):
    """POST {"content_type"}: a short-lived signed URL to upload one photo for this conversation."""

    def post(self, request, conversation_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        if not terms_accepted(request.user):
            return Response({"detail": "Agree to the chat rules first.", "code": "terms_required"}, status=403)
        if blocked_between(request.user, conversation.other_user(request.user)):
            return Response({"detail": NOT_ALLOWED}, status=403)
        if not storage.configured():
            return Response({"detail": "Photos aren't available right now."}, status=503)
        content_type = request.data.get("content_type")
        if content_type not in storage.ALLOWED_TYPES:
            return Response({"detail": "Photos must be JPEG, PNG or WebP."}, status=400)
        key = storage.new_key(conversation.pk, content_type)
        return Response({
            "key": key,
            "upload_url": storage.presign_put(key, content_type),
            "headers": {"Content-Type": content_type},
            "max_bytes": settings.CHAT_PHOTO_MAX_BYTES,
        })


class ReadView(ChatView):
    """POST {"last_id"?}: marks the conversation read for this person (up to last_id, or everything)."""

    def post(self, request, conversation_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        last_id = request.data.get("last_id")
        mark_read(conversation, request.user, last_id if isinstance(last_id, int) and not isinstance(last_id, bool) else None)
        return Response({"unread_count": unread_count(conversation, request.user)})


class ReportView(ChatView):
    """POST {"reason", "details"?}: report a message from the other person for review."""

    def post(self, request, conversation_id, message_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        message = conversation.messages.filter(pk=message_id).first()
        if message is None:
            return Response({"detail": "Message not found."}, status=404)
        if message.sender_id == request.user.pk:
            return Response({"detail": "You can't report your own message."}, status=400)
        reason = request.data.get("reason")
        if reason not in dict(MessageReport.REASON_CHOICES):
            return Response({"detail": "Choose a reason."}, status=400)
        details = request.data.get("details")
        details = details.strip()[:500] if isinstance(details, str) else ""
        MessageReport.objects.get_or_create(
            message=message, reporter=request.user, defaults={"reason": reason, "details": details}
        )
        return Response({"reported": True}, status=201)


class BlockView(ChatView):
    """POST blocks the other person; DELETE unblocks them."""

    def post(self, request, conversation_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        UserBlock.objects.get_or_create(blocker=request.user, blocked=conversation.other_user(request.user))
        return Response({"blocked_by_me": True})

    def delete(self, request, conversation_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        UserBlock.objects.filter(blocker=request.user, blocked=conversation.other_user(request.user)).delete()
        return Response({"blocked_by_me": False})


class CallView(ChatView):
    """GET: how to call the other person. Phase 1 returns their number for the phone's dialer, and only
    once the provider has accepted. Phase 2 (masked calls through Twilio, behind CALL_MASKING_ENABLED)
    will change only what this returns, not the app."""

    def get(self, request, conversation_id):
        conversation = self.conversation_for(request.user, conversation_id)
        if conversation is None:
            return _not_found()
        offer = conversation.offer
        if offer.status != LeadOffer.STATUS_ACCEPTED:
            return Response({"detail": "Calling opens once the provider has accepted."}, status=403)
        other = conversation.other_user(request.user)
        if blocked_between(request.user, other):
            return Response({"detail": NOT_ALLOWED}, status=403)
        if settings.CALL_MASKING_ENABLED:
            return Response({"detail": "Masked calling isn't available yet."}, status=501)
        number = offer.service_request.phone if conversation.client and request.user.pk == conversation.provider_user.pk else offer.provider.phone
        return Response({"mode": "direct", "number": number, "name": conversation.display_name_for(request.user)})
