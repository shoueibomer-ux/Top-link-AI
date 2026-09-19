from rest_framework.views import APIView
from rest_framework.response import Response

from .models import Notification
from .serializers import NotificationSerializer


class NotificationListView(APIView):
    """GET /api/notifications/?device_id=...

    Most recent 20 notifications for a device, plus how many are unread —
    the bell badge shows only when unread_count > 0.
    """

    def get(self, request):
        device_id = request.query_params.get("device_id")
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        notifications = Notification.objects.filter(device_id=device_id)[:20]
        unread_count = Notification.objects.filter(device_id=device_id, is_read=False).count()
        return Response({
            "unread_count": unread_count,
            "notifications": NotificationSerializer(notifications, many=True).data,
        })


class NotificationMarkReadView(APIView):
    """POST /api/notifications/mark-read/  {"device_id": "..."}

    Marks every notification for the device as read — called when the user
    opens the notification panel, so the badge clears.
    """

    def post(self, request):
        device_id = request.data.get("device_id")
        if not device_id:
            return Response({"detail": "device_id is required."}, status=400)

        Notification.objects.filter(device_id=device_id, is_read=False).update(is_read=True)
        return Response({"detail": "ok"})
