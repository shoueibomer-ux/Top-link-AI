from importlib import import_module

from django.db import migrations

# The 9 services Top-Link AI launches with. Every one was already seeded by
# 0002, so on an existing database this only flips is_launched; the
# get_or_create is the safety net for a database where one was deleted. It
# never overwrites an existing row's admin edits, and never reactivates a
# deactivated service. Every other service stays is_launched=False (the
# column default) — active on the website, "coming soon" in the app.
LAUNCH_SLUGS = [
    "plumbing",
    "electrical",
    "carpentry",
    "hvac",
    "painting",
    "construction-finishing",
    "drywall-decor",
    "metalwork-aluminum",
    "glass-mirrors",
]


def launch_services(apps, schema_editor):
    Category = apps.get_model("catalog", "Category")
    Service = apps.get_model("catalog", "Service")

    seed = import_module("catalog.migrations.0002_seed_categories_and_services").CATALOG
    for group_order, group in enumerate(seed):
        wanted = [s for s in group["services"] if s["slug"] in LAUNCH_SLUGS]
        if not wanted:
            continue
        category, _ = Category.objects.get_or_create(
            slug=group["slug"],
            defaults={"name": group["name"], "icon_name": group["icon_name"], "display_order": group_order},
        )
        for service_order, data in enumerate(group["services"]):
            if data["slug"] not in LAUNCH_SLUGS:
                continue
            Service.objects.get_or_create(
                slug=data["slug"],
                defaults={
                    "category": category,
                    "name": data["name"],
                    "icon_name": data["icon_name"],
                    "what_we_cover": data["what_we_cover"],
                    "worker_noun": data["worker_noun"],
                    "google_places_query": data["google_places_query"],
                    "display_order": service_order,
                },
            )

    Service.objects.filter(slug__in=LAUNCH_SLUGS).update(is_launched=True)


class Migration(migrations.Migration):
    dependencies = [
        ("catalog", "0004_service_is_launched"),
    ]

    operations = [
        migrations.RunPython(launch_services, migrations.RunPython.noop),
    ]
