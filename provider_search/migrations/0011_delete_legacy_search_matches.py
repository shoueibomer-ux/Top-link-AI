from django.db import migrations
from django.db.migrations.recorder import MigrationRecorder

# The migration that introduced the unlock endpoint (and ProviderMatch.
# unlock_method) in the same release as the fix for "every search creates a
# match". Anything created before it was applied came from the old behaviour.
_GATING_MIGRATION = "0008_providermatch_unlock_method_and_more"


def delete_legacy_search_matches(apps, schema_editor):
    """Permanently deletes the fake "Requested" rows migration 0009 left behind.

    Before the unlock gate existed, EVERY provider search created a
    ProviderMatch (default status "matched") for each result, so a device
    that merely browsed accumulated hundreds of phantom "requests" — and,
    worse, each one counted as an unlock of that provider's full contact
    details. 0009 relabeled them "requested" and stamped them
    unlock_method="subscription", which made them indistinguishable from
    real unlocks: they showed up in the client's "Your requests" and would
    have landed in providers' incoming-request queues as customer requests
    nobody made. Relabeling was the wrong fix; this removes them.

    A row is legacy iff it was created before 0008 was applied on this
    database (nothing created by the unlock endpoint can predate it) AND is
    still "requested" — i.e. it was an untouched "matched" row. Rows a client
    moved to another status (contacted, booked, ...) show real engagement and
    are kept, as is anything created after the gate shipped. On a database
    that never held old-behaviour rows this deletes nothing.

    Irreversible: the rows were never real data, so there is nothing to
    restore (see the noop reverse below).
    """
    ProviderMatch = apps.get_model("provider_search", "ProviderMatch")

    gating = (
        MigrationRecorder(schema_editor.connection)
        .migration_qs.filter(app="provider_search", name=_GATING_MIGRATION)
        .first()
    )
    if gating is None:
        # Can't establish the cutoff — refuse to guess when deleting.
        return 0

    deleted, _ = ProviderMatch.objects.filter(
        first_unlocked_at__lt=gating.applied,
        status="requested",
        provider_decision="",
        responded_at__isnull=True,
    ).delete()
    return deleted


def delete_legacy_search_matches_and_report(apps, schema_editor):
    """What `migrate` runs: the deletion above, plus a line saying how many
    rows went (kept out of the function itself so tests stay quiet)."""
    deleted = delete_legacy_search_matches(apps, schema_editor)
    if deleted:
        print(f"\n  Deleted {deleted} legacy search-created ProviderMatch row(s).", end="")


class Migration(migrations.Migration):
    dependencies = [
        ("provider_search", "0010_providermatch_provider_decision_and_more"),
    ]

    operations = [
        migrations.RunPython(delete_legacy_search_matches_and_report, migrations.RunPython.noop),
    ]
