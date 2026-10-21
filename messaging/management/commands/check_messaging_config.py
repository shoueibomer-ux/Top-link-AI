import json

from django.conf import settings
from django.core.management.base import BaseCommand

from messaging import storage


class Command(BaseCommand):
    help = (
        "Says whether push notifications (Firebase) and chat photos (Cloudflare R2) are set up. "
        "Never prints a key or secret. With --live it also makes one harmless real call to each service."
    )

    def add_arguments(self, parser):
        parser.add_argument("--live", action="store_true", help="Also try to reach Firebase and R2 with the configured keys.")

    def handle(self, *args, **options):
        live = options["live"]
        self.stdout.write("Chat configuration (values are never shown)\n")
        self._push(live)
        self._photos(live)
        self._photo_queue()
        self.stdout.write(f"\nCall masking (phase 2): {'ON, but not built yet' if settings.CALL_MASKING_ENABLED else 'off (Call dials directly)'}")

    def _line(self, label, ok, detail):
        mark = self.style.SUCCESS("OK  ") if ok else self.style.WARNING("OFF ")
        self.stdout.write(f"  {mark}{label}: {detail}")

    def _push(self, live):
        raw = settings.FCM_SERVICE_ACCOUNT_JSON
        if not raw:
            return self._line("Push notifications", False, "FCM_SERVICE_ACCOUNT_JSON is not set")
        try:
            info = json.loads(raw)
            missing = [k for k in ("project_id", "client_email", "private_key") if not info.get(k)]
        except ValueError:
            return self._line("Push notifications", False, "FCM_SERVICE_ACCOUNT_JSON is set but is not valid JSON")
        if missing:
            return self._line("Push notifications", False, f"FCM_SERVICE_ACCOUNT_JSON is missing: {', '.join(missing)}")
        detail = f"service account for Firebase project '{info['project_id']}'"
        if live:
            try:
                from messaging import push

                push._project_id_and_token()
                detail += "; got an access token from Google"
            except Exception as exc:  # noqa: BLE001
                return self._line("Push notifications", False, f"{detail}; could not get a token ({type(exc).__name__})")
        self._line("Push notifications", True, detail)

    def _photo_queue(self):
        from messaging.models import PhotoDeletion

        waiting = PhotoDeletion.objects.count()
        if waiting:
            self._line("Photo deletions", False, f"{waiting} photo(s) of deleted accounts still to remove; run `manage.py purge_photo_queue`")
        else:
            self._line("Photo deletions", True, "none waiting")

    def _photos(self, live):
        names = ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET")
        missing = [n for n in names if not getattr(settings, n)]
        if missing:
            return self._line("Chat photos", False, f"not set: {', '.join(missing)}")
        detail = f"bucket '{settings.R2_BUCKET}'"
        if live:
            try:
                storage._client().list_objects_v2(Bucket=settings.R2_BUCKET, MaxKeys=1)
                detail += "; reached the bucket"
            except Exception as exc:  # noqa: BLE001
                return self._line("Chat photos", False, f"{detail}; could not reach it ({type(exc).__name__})")
        self._line("Chat photos", True, detail)
