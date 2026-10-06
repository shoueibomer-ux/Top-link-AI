from importlib import import_module

from django.apps import apps as django_apps
from django.test import TestCase, override_settings

from website.models import SectorItem

from .models import Category, Service
from .taxonomy import active_service_names, launched_slugs

LAUNCH_SLUGS = {
    "plumbing", "electrical", "carpentry", "hvac", "painting",
    "construction-finishing", "drywall-decor", "metalwork-aluminum", "glass-mirrors",
}


class LaunchServicesMigrationTests(TestCase):
    def test_exactly_the_nine_launch_services_are_launched(self):
        launched = set(Service.objects.filter(is_launched=True).values_list("slug", flat=True))
        self.assertEqual(launched, LAUNCH_SLUGS)

    def test_every_other_service_stays_active_but_not_launched(self):
        others = Service.objects.exclude(slug__in=LAUNCH_SLUGS)
        self.assertGreater(others.count(), 0)
        self.assertFalse(others.filter(is_launched=True).exists())
        self.assertFalse(others.filter(is_active=False).exists())

    def test_rerunning_it_is_idempotent_and_restores_a_deleted_service(self):
        migration = import_module("catalog.migrations.0005_launch_services")
        before = Service.objects.count()
        migration.launch_services(django_apps, None)
        self.assertEqual(Service.objects.count(), before)

        # SectorItem protects its service from deletion, so clear that first.
        SectorItem.objects.filter(service__slug="glass-mirrors").delete()
        Service.objects.filter(slug="glass-mirrors").delete()
        migration.launch_services(django_apps, None)
        self.assertEqual(Service.objects.count(), before)
        restored = Service.objects.get(slug="glass-mirrors")
        self.assertTrue(restored.is_launched)
        self.assertEqual(restored.category.slug, "trades-professional")

    def test_it_does_not_overwrite_admin_edits_or_reactivate_services(self):
        migration = import_module("catalog.migrations.0005_launch_services")
        Service.objects.filter(slug="plumbing").update(name="Pipes", is_active=False)
        migration.launch_services(django_apps, None)
        plumbing = Service.objects.get(slug="plumbing")
        self.assertEqual(plumbing.name, "Pipes")
        self.assertFalse(plumbing.is_active)


class TaxonomyTests(TestCase):
    def test_active_service_names_covers_the_whole_active_catalog(self):
        names = active_service_names()
        self.assertEqual(set(names), set(Service.objects.filter(is_active=True).values_list("slug", flat=True)))
        self.assertEqual(names["plumbing"], Service.objects.get(slug="plumbing").name)

    def test_inactive_services_and_services_in_inactive_categories_are_excluded(self):
        Service.objects.filter(slug="plumbing").update(is_active=False)
        Category.objects.filter(slug="outdoor-services").update(is_active=False)
        names = active_service_names()
        self.assertNotIn("plumbing", names)
        self.assertNotIn("lawn-care", names)
        self.assertIn("electrical", names)

    def test_launched_slugs_are_the_active_launched_services(self):
        self.assertEqual(launched_slugs(), LAUNCH_SLUGS)
        Service.objects.filter(slug="hvac").update(is_active=False)
        Service.objects.filter(slug="lawn-care").update(is_launched=True)
        self.assertEqual(launched_slugs(), (LAUNCH_SLUGS - {"hvac"}) | {"lawn-care"})


@override_settings(API_KEY="test-key")
class CatalogApiTests(TestCase):
    def _get(self):
        return self.client.get("/api/catalog/categories/", HTTP_X_API_KEY="test-key")

    def test_only_launched_services_and_their_groups_are_listed(self):
        groups = self._get().json()
        self.assertEqual([g["slug"] for g in groups], ["trades-professional"])
        self.assertEqual({s["slug"] for s in groups[0]["services"]}, LAUNCH_SLUGS)

    def test_launching_a_service_adds_it_and_its_group(self):
        Service.objects.filter(slug="lawn-care").update(is_launched=True)
        groups = {g["slug"]: g for g in self._get().json()}
        self.assertIn("outdoor-services", groups)
        self.assertEqual([s["slug"] for s in groups["outdoor-services"]["services"]], ["lawn-care"])

    def test_include_unlaunched_returns_every_active_service(self):
        Service.objects.filter(slug="plumbing").update(is_active=False)
        response = self.client.get(
            "/api/catalog/categories/", {"include_unlaunched": "true"}, HTTP_X_API_KEY="test-key"
        )
        groups = response.json()
        services = {s["slug"] for g in groups for s in g["services"]}
        self.assertEqual(services, set(Service.objects.filter(is_active=True).values_list("slug", flat=True)))
        self.assertIn("lawn-care", services)
        self.assertNotIn("plumbing", services)
        self.assertIn("outdoor-services", {g["slug"] for g in groups})

    def test_the_flag_is_off_unless_explicitly_true(self):
        for value in ("", "false", "0", "no"):
            response = self.client.get(
                "/api/catalog/categories/", {"include_unlaunched": value}, HTTP_X_API_KEY="test-key"
            )
            services = {s["slug"] for g in response.json() for s in g["services"]}
            self.assertEqual(services, LAUNCH_SLUGS, value)

    def test_a_deactivated_launched_service_is_hidden(self):
        Service.objects.filter(slug="plumbing").update(is_active=False)
        services = {s["slug"] for g in self._get().json() for s in g["services"]}
        self.assertNotIn("plumbing", services)
