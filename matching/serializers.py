from rest_framework import serializers
from .models import Profile, MatchRequest, Category, Subscription


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ["id", "name"]


class ProfileCreateSerializer(serializers.ModelSerializer):
    """Client sends name/role/description/location — categories are AI-assigned, not client-supplied."""
    class Meta:
        model = Profile
        fields = ["id", "name", "role", "description", "lat", "lng", "available"]
        read_only_fields = ["id"]


class ProfileResultSerializer(serializers.ModelSerializer):
    categories = CategorySerializer(many=True, read_only=True)

    class Meta:
        model = Profile
        fields = ["id", "name", "role", "categories", "rating"]


class MatchRequestCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = MatchRequest
        fields = ["id", "requester", "request_text", "lat", "lng", "max_distance_km"]
        read_only_fields = ["id"]


class MatchResultSerializer(serializers.Serializer):
    profile = ProfileResultSerializer()
    score = serializers.FloatField()
    breakdown = serializers.DictField()


class SubscriptionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Subscription
        fields = ["device_id", "status", "start_date", "expiry_date"]


class SubscriptionActivateSerializer(serializers.Serializer):
    device_id = serializers.CharField(max_length=64)
    status = serializers.ChoiceField(choices=["trial", "active", "inactive"])
    start_date = serializers.DateTimeField()
    expiry_date = serializers.DateTimeField()
