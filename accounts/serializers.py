from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from provider_search.services import CITIES
from .models import ProviderBusinessProfile, UserProfile, UserRole

User = get_user_model()


class EmailTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Same as SimpleJWT's default, except the public field is `email`
    instead of `username`. The User model itself is untouched (still
    Django's built-in auth.User, USERNAME_FIELD="username" internally) —
    `username_field` is deliberately NOT overridden to "email" here, since
    that would make the parent's validate() call
    authenticate(email=..., password=...), which Django's ModelBackend
    doesn't understand (it expects `username=`) and would always fail.
    Instead this swaps in an `email` input field, resolves it to the
    matching User's real username, and hands that to the parent unchanged.
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        del self.fields[self.username_field]
        self.fields["email"] = serializers.EmailField()

    def validate(self, attrs):
        email = attrs.pop("email", "")
        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            raise serializers.ValidationError({"detail": "Invalid email or password."})
        attrs[self.username_field] = user.get_username()
        return super().validate(attrs)


class ProviderBusinessProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProviderBusinessProfile
        fields = [
            "business_name",
            "description",
            "categories",
            "city",
            "phone",
            "is_available_now",
            "provider_type",
            "team_size",
            "equipment",
            "certifications",
            "service_radius_km",
            "languages",
            "response_time_minutes",
            "completion_rate",
            "place_id",
            "years_experience",
            "is_insured",
            "photo_urls",
            "rating",
            "rating_count",
            "updated_at",
        ]
        read_only_fields = ["response_time_minutes", "completion_rate", "rating", "rating_count", "updated_at"]
        # place_id's model-level unique=True would otherwise add DRF's
        # automatic UniqueValidator, which fires before validate_place_id()
        # below and reports a generic "already exists" instead of the
        # friendlier, more accurate message.
        extra_kwargs = {"place_id": {"validators": []}}

    def validate_city(self, value):
        if value and value not in CITIES:
            raise serializers.ValidationError(f"city must be one of {CITIES}.")
        return value

    def validate_place_id(self, value):
        if not value:
            return value
        existing = ProviderBusinessProfile.objects.filter(place_id=value)
        if self.instance is not None:
            existing = existing.exclude(pk=self.instance.pk)
        if existing.exists():
            raise serializers.ValidationError("This listing has already been claimed by another provider.")
        return value


class UserProfileSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(source="user.email", read_only=True)
    provider_profile = serializers.SerializerMethodField()

    class Meta:
        model = UserProfile
        fields = ["email", "role", "full_name", "provider_profile"]

    def get_provider_profile(self, obj: UserProfile):
        if obj.role != UserRole.PROVIDER:
            return None
        business_profile = getattr(obj.user, "provider_business_profile", None)
        if business_profile is None:
            return None
        return ProviderBusinessProfileSerializer(business_profile).data


class RegisterSerializer(serializers.Serializer):
    """POST /api/accounts/register/ — creates a real Customer or Provider
    account. `role` may only be "customer" or "provider": ADMIN accounts are
    never created through the public API (see UserProfile's docstring) —
    only via `createsuperuser` or the Django admin.
    """

    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)
    full_name = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")
    role = serializers.ChoiceField(choices=[UserRole.CUSTOMER, UserRole.PROVIDER])
    business_name = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def validate_password(self, value):
        validate_password(value)
        return value

    def create(self, validated_data):
        role = validated_data["role"]
        user = User.objects.create_user(
            username=validated_data["email"],
            email=validated_data["email"],
            password=validated_data["password"],
        )
        profile = UserProfile.objects.create(
            user=user, role=role, full_name=validated_data.get("full_name", "")
        )
        if role == UserRole.PROVIDER:
            ProviderBusinessProfile.objects.create(
                user=user, business_name=validated_data.get("business_name", "")
            )
        return profile
