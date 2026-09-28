from django.db import migrations


def relabel_matched_rows(apps, schema_editor):
    """Existing ProviderMatch rows with status="matched" already have real
    contact details recorded (they were created by the old auto-unlock-on-
    search behaviour this migration's code change retires) — "requested" is
    the accurate current label for them, and "subscription" is the accurate
    unlock_method for all of them, since the old behaviour only ever wrote
    full contact details for already-subscribed devices.
    """
    ProviderMatch = apps.get_model("provider_search", "ProviderMatch")
    ProviderMatch.objects.filter(status="matched").update(status="requested")
    ProviderMatch.objects.filter(unlock_method="").update(unlock_method="subscription")


def noop_reverse(apps, schema_editor):
    # Not reversible: we can't tell which rows were originally "matched"
    # vs. legitimately "requested" through the new flow.
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("provider_search", "0008_providermatch_unlock_method_and_more"),
    ]

    operations = [
        migrations.RunPython(relabel_matched_rows, noop_reverse),
    ]
