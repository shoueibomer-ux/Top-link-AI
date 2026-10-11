from django.db import migrations


def clear_hand_added_providers(apps, schema_editor):
    """Hand-added providers are being replaced by providers who register in the
    app (providers.ProviderProfile). The one that exists is a test record, and
    there must be no lead offers: refusing to run is safer than quietly
    deleting offers that carry replies and hiring history."""
    LeadOffer = apps.get_model("leads", "LeadOffer")
    Provider = apps.get_model("leads", "Provider")
    offers = LeadOffer.objects.count()
    if offers:
        raise RuntimeError(
            f"Refusing to remove hand-added providers: {offers} lead offer(s) still reference them. "
            "Nothing was changed. Review them in the admin before retrying."
        )
    Provider.objects.all().delete()


class Migration(migrations.Migration):
    # A migration of its own, so the deletes are committed before the next one
    # alters tables (Postgres refuses to ALTER a table with pending trigger events).
    dependencies = [
        ("leads", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(clear_hand_added_providers, migrations.RunPython.noop),
    ]
