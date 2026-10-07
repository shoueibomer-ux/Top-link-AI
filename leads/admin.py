from django import forms
from django.contrib import admin, messages
from django.core.exceptions import PermissionDenied
from django.http import HttpResponseRedirect
from django.shortcuts import get_object_or_404, render
from django.urls import path, reverse

from provider_search.models import ServiceRequest
from provider_search.services import CITIES

from . import services, sms
from .models import LeadOffer, Provider


class ProviderForm(forms.ModelForm):
    service_areas = forms.MultipleChoiceField(
        choices=[(city, city) for city in CITIES],
        required=False,
        widget=forms.CheckboxSelectMultiple,
        help_text="Leave empty if unknown; they'll still be suggested, flagged as having no area set.",
    )

    class Meta:
        model = Provider
        fields = "__all__"


@admin.register(Provider)
class ProviderAdmin(admin.ModelAdmin):
    form = ProviderForm
    list_display = (
        "business_name", "contact_name", "phone", "is_active", "sms_consent_confirmed", "sms_opt_out", "service_list",
    )
    list_filter = ("is_active", "sms_consent_confirmed", "sms_opt_out", "services")
    search_fields = ("business_name", "contact_name", "phone", "notes")
    filter_horizontal = ("services",)

    @admin.display(description="Services")
    def service_list(self, obj):
        return ", ".join(s.name for s in obj.services.all())


@admin.register(LeadOffer)
class LeadOfferAdmin(admin.ModelAdmin):
    list_display = (
        "ref", "provider", "service_request", "status", "sent_at", "response_time", "hired", "job_completed",
    )
    list_filter = ("status", "hired", "job_completed", "provider")
    list_editable = ("hired", "job_completed")
    list_select_related = ("provider", "service_request")
    readonly_fields = (
        "created_at", "hired_at", "twilio_sid", "followup_sid", "send_error", "response_time", "reply_channel",
    )
    date_hierarchy = "created_at"

    # Offers are created only through "Send to providers", which enforces the
    # rules (consent, opt-outs, at most 3, no duplicates).
    def has_add_permission(self, request):
        return False

    def get_urls(self):
        wrap = self.admin_site.admin_view
        return [
            path("send/<int:request_id>/", wrap(self.send_view), name="leads_send_to_providers"),
            path("tracker/<int:request_id>/", wrap(self.tracker_view), name="leads_tracker"),
            path("<int:pk>/act/", wrap(self.act_view), name="leads_offer_act"),
            *super().get_urls(),
        ]

    def _require_change(self, request):
        if not self.has_change_permission(request):
            raise PermissionDenied

    def _context(self, request, **extra):
        return {**self.admin_site.each_context(request), "opts": self.model._meta, **extra}

    # ---- pick providers, create the offers (and send, if SMS is on) ----------
    def send_view(self, request, request_id):
        self._require_change(request)
        service_request = get_object_or_404(ServiceRequest, pk=request_id)
        problem = services.forwarding_problem(service_request)

        if request.method == "POST" and not problem:
            chosen = Provider.objects.filter(pk__in=request.POST.getlist("providers"))
            try:
                offers = services.create_offers(service_request, chosen)
            except ValueError as exc:
                messages.error(request, str(exc))
                return HttpResponseRedirect(request.path)
            if sms.sms_enabled():
                self._send_all(request, offers)
            else:
                messages.info(
                    request,
                    "SMS is off, so nothing was sent. Copy each message below, send it yourself, then click "
                    "'Mark as sent'.",
                )
            return HttpResponseRedirect(reverse("admin:leads_tracker", args=[service_request.pk]))

        return render(
            request,
            "admin/leads/send_to_providers.html",
            self._context(
                request,
                title=f"Send request #{service_request.pk} to providers",
                service_request=service_request,
                service_name=services.service_name(service_request),
                urgency=services.urgency_label(service_request),
                problem=problem,
                candidates=services.suggest_providers(service_request),
                sms_enabled=sms.sms_enabled(),
                max_offers=services.MAX_OFFERS_PER_SEND,
            ),
        )

    def _send_all(self, request, offers):
        for offer in offers:
            try:
                services.send_offer_sms(offer)
                messages.success(request, f"Texted {offer.provider}.")
            except sms.SmsError as exc:
                messages.error(request, f"Could not text {offer.provider}: {exc}")

    # ---- follow the offers for one request -----------------------------------
    def tracker_view(self, request, request_id):
        self._require_change(request)
        service_request = get_object_or_404(ServiceRequest, pk=request_id)
        rows = []
        for offer in service_request.offers.select_related("provider"):
            first = services.offer_message(offer)
            follow = services.followup_message(offer)
            minutes = None if offer.response_time is None else round(offer.response_time.total_seconds() / 60, 1)
            rows.append({
                "offer": offer,
                "first_message": first,
                "first_sms_link": services.sms_link(offer.provider.phone, first),
                "followup_message": follow,
                "followup_sms_link": services.sms_link(offer.provider.phone, follow),
                "tel_link": services.tel_link(offer.provider.phone),
                "response_minutes": minutes,
                "pending": offer.status == LeadOffer.STATUS_PENDING,
                "awaiting": offer.awaiting_reply,
                "accepted": offer.status == LeadOffer.STATUS_ACCEPTED,
            })
        return render(
            request,
            "admin/leads/tracker.html",
            self._context(
                request,
                title=f"Offers for request #{service_request.pk}",
                service_request=service_request,
                service_name=services.service_name(service_request),
                urgency=services.urgency_label(service_request),
                rows=rows,
                sms_enabled=sms.sms_enabled(),
            ),
        )

    # ---- the one-click buttons ------------------------------------------------
    def act_view(self, request, pk):
        self._require_change(request)
        offer = get_object_or_404(LeadOffer.objects.select_related("provider", "service_request"), pk=pk)
        back = HttpResponseRedirect(reverse("admin:leads_tracker", args=[offer.service_request_id]))
        if request.method != "POST":
            return back
        action = request.POST.get("action", "")
        name = offer.provider

        if action == "mark_sent":
            if offer.status == LeadOffer.STATUS_PENDING:
                offer.mark_sent()
                messages.success(request, f"Marked as sent to {name}. The response clock is running.")
            else:
                messages.warning(request, f"{name}'s offer was already sent.")
        elif action == "retry_send":
            try:
                services.send_offer_sms(offer)
                messages.success(request, f"Texted {name}.")
            except sms.SmsError as exc:
                messages.error(request, f"Could not text {name}: {exc}")
        elif action in ("yes", "no", "no_answer"):
            reply = {"yes": LeadOffer.REPLY_YES, "no": LeadOffer.REPLY_NO, "no_answer": LeadOffer.REPLY_NO_ANSWER}[action]
            if offer.record_reply(reply, LeadOffer.CHANNEL_MANUAL):
                label = {"yes": "YES", "no": "NO", "no_answer": "no answer"}[action]
                messages.success(request, f"Recorded {label} from {name}.")
            else:
                messages.warning(request, f"Couldn't record that for {name}: not sent yet, or a YES/NO is already recorded.")
        elif action == "followup_sent":
            services.mark_followup_sent(offer)
            messages.success(request, f"Marked the client's phone as shared with {name}.")
        elif action == "send_followup":
            try:
                services.share_client_phone(offer)
                messages.success(request, f"Texted the client's phone to {name}.")
            except sms.SmsError as exc:
                messages.error(request, f"Could not text {name}: {exc}")
        else:
            messages.error(request, "Unknown action.")
        return back
