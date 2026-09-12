from rest_framework import serializers
from .models import Profile, MatchRequest, Category


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
