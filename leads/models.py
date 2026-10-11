from django.db import models
from django.utils import timezone


class LeadOffer(models.Model):
    """One client request offered to one provider, and what happened.

    States follow docs/ai-agent-system.md (sent, viewed, accepted, declined,
    expired) plus `pending`: the offer exists but the message hasn't gone out
    yet (in manual mode, until you mark it sent). `viewed` is kept for later;
    nothing sets it yet, since SMS can't report a message being read.
    """

    STATUS_PENDING = "pending"
    STATUS_SENT = "sent"
    STATUS_VIEWED = "viewed"
    STATUS_ACCEPTED = "accepted"
    STATUS_DECLINED = "declined"
    STATUS_EXPIRED = "expired"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending (not sent yet)"),
        (STATUS_SENT, "Sent"),
        (STATUS_VIEWED, "Viewed"),
        (STATUS_ACCEPTED, "Accepted (YES)"),
        (STATUS_DECLINED, "Declined (NO)"),
        (STATUS_EXPIRED, "Expired / no answer"),
    ]

    REPLY_YES = "yes"
    REPLY_NO = "no"
    REPLY_NO_ANSWER = "no_answer"

    CHANNEL_SMS = "sms"
    CHANNEL_MANUAL = "manual"

    service_request = models.ForeignKey("provider_search.ServiceRequest", on_delete=models.CASCADE, related_name="offers")
    provider = models.ForeignKey("providers.ProviderProfile", on_delete=models.PROTECT, related_name="offers")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)

    created_at = models.DateTimeField(auto_now_add=True)
    # When the message actually went out: by Twilio, or when you marked it sent.
    sent_at = models.DateTimeField(null=True, blank=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    # responded_at - sent_at, for YES / NO replies.
    response_time = models.DurationField(null=True, blank=True)
    reply_channel = models.CharField(max_length=10, blank=True)
    reminder_sent_at = models.DateTimeField(null=True, blank=True)
    client_phone_shared_at = models.DateTimeField(null=True, blank=True)

    twilio_sid = models.CharField(max_length=64, blank=True)
    followup_sid = models.CharField(max_length=64, blank=True)
    send_error = models.TextField(blank=True)

    # Filled in by you in the admin once you know how it went.
    hired = models.BooleanField(default=False, help_text="The client hired this provider.")
    hired_at = models.DateTimeField(null=True, blank=True, editable=False)
    job_completed = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["service_request", "provider"], name="one_offer_per_request_and_provider"),
        ]

    def __str__(self):
        return f"#{self.pk} {self.provider} <- request {self.service_request_id} ({self.status})"

    @property
    def ref(self) -> int:
        """The number providers quote when replying (YES 42)."""
        return self.pk

    @property
    def awaiting_reply(self) -> bool:
        return self.sent_at is not None and self.responded_at is None and self.status in (
            self.STATUS_SENT, self.STATUS_VIEWED, self.STATUS_EXPIRED,
        )

    def mark_sent(self, sid: str = "", now=None) -> None:
        self.status = self.STATUS_SENT
        self.sent_at = now or timezone.now()
        self.twilio_sid = sid or self.twilio_sid
        self.send_error = ""
        self.save(update_fields=["status", "sent_at", "twilio_sid", "send_error"])

    def record_reply(self, reply: str, channel: str, now=None) -> bool:
        """Records YES / NO / no answer. Returns False (changing nothing) if the
        offer was never sent or already has a YES/NO."""
        if self.sent_at is None or self.status in (self.STATUS_ACCEPTED, self.STATUS_DECLINED):
            return False
        now = now or timezone.now()
        if reply == self.REPLY_NO_ANSWER:
            self.status = self.STATUS_EXPIRED
            self.reply_channel = channel
            self.save(update_fields=["status", "reply_channel"])
            return True
        self.status = self.STATUS_ACCEPTED if reply == self.REPLY_YES else self.STATUS_DECLINED
        self.responded_at = now
        self.response_time = now - self.sent_at
        self.reply_channel = channel
        self.save(update_fields=["status", "responded_at", "response_time", "reply_channel"])
        return True

    def save(self, *args, **kwargs):
        if self.hired and self.hired_at is None:
            self.hired_at = timezone.now()
            if kwargs.get("update_fields") is not None:
                kwargs["update_fields"] = [*kwargs["update_fields"], "hired_at"]
        elif not self.hired and self.hired_at is not None:
            self.hired_at = None
            if kwargs.get("update_fields") is not None:
                kwargs["update_fields"] = [*kwargs["update_fields"], "hired_at"]
        super().save(*args, **kwargs)


class DailySummaryLog(models.Model):
    """One row per day the summary email went out, so the 15-minute cron job
    sends it once."""

    date = models.DateField(unique=True)
    sent_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"daily summary {self.date}"
