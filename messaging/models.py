from django.conf import settings
from django.db import models

from accounts.names import public_name


class Conversation(models.Model):
    """The chat between a client and one provider who accepted their request.
    One per accepted LeadOffer, and only the two people on that offer can ever
    see it: the client who owns the request and the provider's own account."""

    offer = models.OneToOneField("leads.LeadOffer", on_delete=models.CASCADE, related_name="conversation")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Conversation #{self.pk} (offer {self.offer_id})"

    @property
    def client(self):
        return self.offer.service_request.user

    @property
    def provider_user(self):
        return self.offer.provider.user

    def includes(self, user) -> bool:
        return user is not None and user.pk in (self.client and self.client.pk, self.provider_user.pk)

    def other_user(self, user):
        return self.provider_user if self.client and user.pk == self.client.pk else self.client

    def request_summary(self, service_names=None) -> str:
        """What the chat is about, for under the name in the header: "Plumbing · Leaking kitchen sink"."""
        from catalog.models import Service

        request = self.offer.service_request
        if service_names is None:
            service_names = dict(Service.objects.filter(slug=request.category).values_list("slug", "name"))
        service = service_names.get(request.category) or request.category.replace("-", " ").title()
        description = " ".join((request.problem_description or "").split())
        if len(description) > 60:
            description = description[:59].rstrip() + "…"
        return f"{service} · {description}" if description else service

    def display_name_for(self, viewer) -> str:
        """What `viewer` calls the other person: the provider's business name for the client, the
        client's shortened name for the provider."""
        if self.client and viewer.pk == self.client.pk:
            return self.offer.provider.business_name
        owner = self.client
        return public_name(owner.profile.full_name if owner and hasattr(owner, "profile") else "")


class Message(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name="messages")
    # Kept (as a blank) if the account is ever deleted, so the other person's history stays whole.
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    body = models.TextField(blank=True)
    # The object key in the private photo bucket; never a public URL. Signed links are made per request.
    photo_key = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    # Moderation: a hidden message shows as "removed" and is never delivered, counted or pushed.
    hidden = models.BooleanField(default=False)
    hidden_reason = models.CharField(max_length=200, blank=True)
    hidden_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["id"]
        indexes = [models.Index(fields=["conversation", "id"])]

    def __str__(self):
        return f"#{self.pk} {(self.body or '[photo]')[:40]}"


class ConversationRead(models.Model):
    """How far each person has read, so unread counts are per person."""

    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name="reads")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+")
    last_read_id = models.BigIntegerField(default=0)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["conversation", "user"], name="one_read_marker_per_user")]


class UserBlock(models.Model):
    """`blocker` does not want to hear from `blocked`: neither can send the other messages
    (the blocked person is not told which way it works)."""

    blocker = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="blocks_made")
    blocked = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="blocks_received")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["blocker", "blocked"], name="one_block_per_pair")]

    def __str__(self):
        return f"{self.blocker_id} blocked {self.blocked_id}"


class MessageReport(models.Model):
    REASON_SPAM = "spam"
    REASON_HARASSMENT = "harassment"
    REASON_INAPPROPRIATE = "inappropriate"
    REASON_SCAM = "scam"
    REASON_OTHER = "other"
    REASON_CHOICES = [
        (REASON_SPAM, "Spam"),
        (REASON_HARASSMENT, "Harassment or abuse"),
        (REASON_INAPPROPRIATE, "Inappropriate content"),
        (REASON_SCAM, "Scam or fraud"),
        (REASON_OTHER, "Something else"),
    ]
    STATUS_OPEN = "open"
    STATUS_ACTIONED = "actioned"
    STATUS_DISMISSED = "dismissed"
    STATUS_CHOICES = [(STATUS_OPEN, "Open"), (STATUS_ACTIONED, "Action taken"), (STATUS_DISMISSED, "Dismissed")]

    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name="reports")
    reporter = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="message_reports")
    reason = models.CharField(max_length=20, choices=REASON_CHOICES)
    details = models.CharField(max_length=500, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_OPEN, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [models.UniqueConstraint(fields=["message", "reporter"], name="one_report_per_reporter")]

    def __str__(self):
        return f"Report #{self.pk} on message {self.message_id} ({self.reason})"


class DeviceToken(models.Model):
    """A phone that can receive this user's push notifications (FCM registration token)."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="device_tokens")
    token = models.CharField(max_length=300, unique=True)
    platform = models.CharField(max_length=20, default="android")
    updated_at = models.DateTimeField(auto_now=True)


class ChatTermsAcceptance(models.Model):
    """The person agreed to the chat rules (required before their first message)."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="chat_terms")
    accepted_at = models.DateTimeField(auto_now_add=True)
