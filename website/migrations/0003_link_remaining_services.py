from django.db import migrations

# Surfaces the catalog services that had no website sector item (the 9 named
# in the request, plus Carpentry and Home Repair, which were only reachable via
# a body link on the home-improvement page and not from site navigation), so every
# backend Service is reachable from site navigation. Each item points at its
# real catalog.Service; nothing here invents a website-only service.
#
# (sector slug, display label, catalog.Service slug)
NEW_ITEMS = [
    ("construction-renovation", "Carpentry", "carpentry"),
    ("construction-renovation", "Metalwork / Aluminum", "metalwork-aluminum"),
    ("construction-renovation", "Glass & Mirrors", "glass-mirrors"),
    ("home-services", "Home Repair", "home-repair"),
    ("automotive-services", "Tire Repair", "tire-repair"),
    ("events-personal", "Event Decoration", "event-decoration"),
    ("events-personal", "Sound & Lighting", "sound-lighting"),
    ("personal-services", "Barber Services", "barber-services"),
    ("personal-services", "Beauty Services", "beauty-services"),
    ("personal-services", "Personal Training", "personal-training"),
    ("personal-services", "Tutoring", "tutoring"),
]


def add_items(apps, schema_editor):
    Sector = apps.get_model("website", "Sector")
    SectorItem = apps.get_model("website", "SectorItem")
    Service = apps.get_model("catalog", "Service")

    personal, _ = Sector.objects.get_or_create(
        slug="personal-services",
        defaults={
            "name": "Personal Services",
            "blurb": "Grooming, wellness and learning.",
            "display_order": Sector.objects.count(),
        },
    )
    for sector_slug, label, service_slug in NEW_ITEMS:
        sector = personal if sector_slug == "personal-services" else Sector.objects.get(slug=sector_slug)
        SectorItem.objects.get_or_create(
            sector=sector,
            label=label,
            defaults={
                "service": Service.objects.get(slug=service_slug),
                "display_order": SectorItem.objects.filter(sector=sector).count(),
            },
        )


def remove_items(apps, schema_editor):
    Sector = apps.get_model("website", "Sector")
    SectorItem = apps.get_model("website", "SectorItem")
    for sector_slug, label, _ in NEW_ITEMS:
        SectorItem.objects.filter(sector__slug=sector_slug, label=label).delete()
    Sector.objects.filter(slug="personal-services").delete()


class Migration(migrations.Migration):
    dependencies = [
        ("website", "0002_seed_sectors"),
        ("catalog", "0003_extended_services_and_outdoor"),
    ]

    operations = [migrations.RunPython(add_items, remove_items)]
