from rest_framework import serializers

from .models import Category, Service


class ServiceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Service
        fields = ["id", "name", "slug", "icon_name", "what_we_cover", "worker_noun"]


class CategorySerializer(serializers.ModelSerializer):
    services = serializers.SerializerMethodField()

    class Meta:
        model = Category
        fields = ["id", "name", "slug", "icon_name", "services"]

    def get_services(self, obj):
        active_services = [s for s in obj.services.all() if s.is_active]
        return ServiceSerializer(active_services, many=True).data
