import secrets

from django.conf import settings
from django.db import IntegrityError, models, transaction
from django.utils import timezone

from provider_search.models import ServiceRequest

# No 0/O or 1/I/L, so a code read out loud or typed from a screenshot comes out right.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8


def _new_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


class InviteCode(models.Model):
    """A client's own invite link (/invite/<code>/). One per client, made the
    first time they open "Invite friends" or share a provider."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="invite_code")
    code = models.CharField(max_length=16, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.code

    @classmethod
    def for_user(cls, user) -> "InviteCode":
        existing = cls.objects.filter(user=user).first()
        if existing:
            return existing
        for _ in range(5):
            try:
                with transaction.atomic():
                    return cls.objects.create(user=user, code=_new_code())
            except IntegrityError:
                # Either the code was taken (try another) or a parallel request made this user's code.
                existing = cls.objects.filter(user=user).first()
                if existing:
                    return existing
        raise RuntimeError("Could not create an invite code")


class InviteSignup(models.Model):
    """A new client who came through someone's invite (they opened the invite
    link, or typed the code, around the time they signed up). `code` is kept
    even if the inviter's account and its InviteCode are later deleted."""

    invitee = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="invited_by")
    invite = models.ForeignKey(InviteCode, null=True, blank=True, on_delete=models.SET_NULL, related_name="signups")
    code = models.CharField(max_length=16, db_index=True)
    # The provider the inviter shared, when the invite was a "Share this provider" link.
    shared_provider = models.ForeignKey(
        "providers.ProviderProfile", null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.invitee_id} via {self.code}"


class ReminderPreference(models.Model):
    """A client's choice about seasonal reminders. No row means the default:
    on (they are a past client; see growth.jobs for who is eligible). Turned
    off from the app's Settings or the unsubscribe link in any reminder."""

    VIA_APP = "app"
    VIA_EMAIL = "email"
    VIA_ADMIN = "admin"

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reminder_preference")
    seasonal_reminders = models.BooleanField(default=True)
    changed_via = models.CharField(max_length=10, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user_id}: {'on' if self.seasonal_reminders else 'off'}"

    @classmethod
    def set_for(cls, user, enabled: bool, via: str) -> "ReminderPreference":
        pref, _ = cls.objects.update_or_create(user=user, defaults={"seasonal_reminders": enabled, "changed_via": via})
        return pref

    @classmethod
    def enabled_for(cls, user) -> bool:
        pref = cls.objects.filter(user=user).first()
        return pref.seasonal_reminders if pref else True


class ReminderSend(models.Model):
    """One seasonal reminder that went to one client: the log of every send,
    and what stops a second one in the same month or the same campaign twice
    in a season."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="seasonal_reminders")
    campaign = models.CharField(max_length=50)
    service = models.CharField(max_length=50)
    season_year = models.PositiveSmallIntegerField()
    sent_at = models.DateTimeField(default=timezone.now, db_index=True)
    # Phones FCM accepted the notification for (0: no app registered, or push is off).
    push_count = models.PositiveSmallIntegerField(default=0)
    email_sent = models.BooleanField(default=False)
    note = models.CharField(max_length=200, blank=True)

    class Meta:
        ordering = ["-sent_at"]
        constraints = [
            models.UniqueConstraint(fields=["user", "campaign", "season_year"], name="one_reminder_per_campaign_per_season"),
        ]

    def __str__(self):
        return f"{self.campaign} {self.season_year} -> {self.user_id}"


class GrowthReport(ServiceRequest):
    """The admin's growth dashboard (see growth.admin.GrowthReportAdmin). A
    proxy with no table, only so the dashboard has a place in the admin."""

    class Meta:
        proxy = True
        verbose_name = "growth dashboard"
        verbose_name_plural = "growth dashboard"
