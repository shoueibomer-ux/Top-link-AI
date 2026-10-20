from django.urls import path

from .views import (
    BlockView,
    CallView,
    ConversationListView,
    ConversationOpenView,
    DeviceView,
    MessageListView,
    PhotoUploadView,
    ReadView,
    ReportView,
    TermsView,
)

urlpatterns = [
    path("conversations/", ConversationListView.as_view(), name="conversation-list"),
    path("conversations/open/", ConversationOpenView.as_view(), name="conversation-open"),
    path("conversations/<int:conversation_id>/messages/", MessageListView.as_view(), name="conversation-messages"),
    path("conversations/<int:conversation_id>/photos/", PhotoUploadView.as_view(), name="conversation-photo-upload"),
    path("conversations/<int:conversation_id>/read/", ReadView.as_view(), name="conversation-read"),
    path("conversations/<int:conversation_id>/block/", BlockView.as_view(), name="conversation-block"),
    path("conversations/<int:conversation_id>/call/", CallView.as_view(), name="conversation-call"),
    path(
        "conversations/<int:conversation_id>/messages/<int:message_id>/report/",
        ReportView.as_view(),
        name="message-report",
    ),
    path("messaging/terms/", TermsView.as_view(), name="chat-terms"),
    path("devices/", DeviceView.as_view(), name="device-token"),
]
