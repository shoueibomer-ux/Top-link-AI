from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import UserProfile

User = get_user_model()


class UserProfileSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(source="user.email", read_only=True)

    class Meta:
        model = UserProfile
        fields = ["email", "role", "full_name"]


class ProfileUpdateSerializer(serializers.Serializer):
    """PATCH /api/accounts/me/ — what an account holder may change about
    themselves: their name and their sign-in email. Deliberately NOT `role`
    (a customer must not be able to promote themselves to provider or admin
    — see RegisterSerializer, which is the only place a role is chosen) and
    not the password (a separate flow).

    Registration sets `username = email`, and login resolves the submitted
    email to that username (see EmailTokenObtainPairSerializer), so changing
    the email must change both or the account can no longer log in.
    """

    full_name = serializers.CharField(max_length=200, required=False, allow_blank=True)
    email = serializers.EmailField(required=False)

    def validate_email(self, value):
        value = value.strip()
        user = self.context["request"].user
        taken = User.objects.filter(email__iexact=value) | User.objects.filter(username__iexact=value)
        if taken.exclude(pk=user.pk).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def update(self, profile, validated_data):
        if "full_name" in validated_data:
            profile.full_name = validated_data["full_name"].strip()
            profile.save(update_fields=["full_name"])
        if "email" in validated_data:
            user = profile.user
            user.email = validated_data["email"]
            user.username = validated_data["email"]
            user.save(update_fields=["email", "username"])
        return profile
