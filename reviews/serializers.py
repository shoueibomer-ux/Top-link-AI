"""How a review is shown. Reviews are public, so the client appears only as "Pat P." and no contact detail is ever
included; a hidden (moderated) review is shown to nobody but its author, who is told it was removed."""

from accounts.names import public_name

from . import ratings


def client_name(review) -> str:
    client = review.client
    profile = getattr(client, "profile", None) if client is not None else None
    return public_name(profile.full_name if profile else "")


def serialize_review(review, viewer_id=None) -> dict:
    mine = viewer_id is not None and review.client_id == viewer_id
    reply = None
    if review.reply:
        reply = {"text": review.reply, "created_at": review.reply_at}
    data = {
        "id": review.id,
        "rating": review.rating,
        "comment": review.comment,
        "client_name": client_name(review),
        "created_at": review.created_at,
        "edited": review.edited_at is not None,
        "reply": reply,
        "mine": mine,
        "hidden": review.hidden,
    }
    if mine:
        data["can_edit"] = (not review.hidden) and review.can_be_edited()
        data["editable_until"] = review.editable_until
    return data


def provider_card(provider, summary=None) -> dict:
    """What anyone may see of an approved provider (no phone, no email), with their rating."""
    summary = summary or ratings.summary_for(provider.id)
    return {
        "id": provider.id,
        "business_name": provider.business_name,
        "bio": provider.bio,
        "categories": [c.slug for c in provider.categories.all()],
        "cities": provider.cities,
        **summary,
    }
