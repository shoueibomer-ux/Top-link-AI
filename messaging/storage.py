"""Chat photos in a private Cloudflare R2 bucket (S3-compatible). The app uploads straight to R2 with a
short-lived signed URL, and reads a photo through another short-lived signed URL that only the two people
in the conversation are ever given. The bucket itself is never public. The only module that talks to R2."""

import uuid

from django.conf import settings

ALLOWED_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
UPLOAD_URL_SECONDS = 600
VIEW_URL_SECONDS = 900


def configured() -> bool:
    return bool(
        settings.R2_ACCOUNT_ID and settings.R2_ACCESS_KEY_ID and settings.R2_SECRET_ACCESS_KEY and settings.R2_BUCKET
    )


def _client():
    import boto3
    from botocore.config import Config

    return boto3.client(
        "s3",
        endpoint_url=f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.R2_ACCESS_KEY_ID,
        aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
        region_name="auto",
        config=Config(signature_version="s3v4", retries={"max_attempts": 2}, connect_timeout=5, read_timeout=10),
    )


def new_key(conversation_id: int, content_type: str) -> str:
    """An unguessable object name that records which conversation the photo belongs to."""
    return f"chat/{conversation_id}/{uuid.uuid4().hex}.{ALLOWED_TYPES[content_type]}"


def presign_put(key: str, content_type: str) -> str:
    return _client().generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.R2_BUCKET, "Key": key, "ContentType": content_type},
        ExpiresIn=UPLOAD_URL_SECONDS,
    )


def presign_get(key: str) -> str:
    return _client().generate_presigned_url(
        "get_object", Params={"Bucket": settings.R2_BUCKET, "Key": key}, ExpiresIn=VIEW_URL_SECONDS
    )


def head(key: str):
    """{"size": bytes, "content_type": str} for an uploaded object, or None if it isn't there."""
    from botocore.exceptions import ClientError

    try:
        info = _client().head_object(Bucket=settings.R2_BUCKET, Key=key)
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
            return None
        raise
    return {"size": info.get("ContentLength", 0), "content_type": info.get("ContentType", "")}


def delete(key: str) -> None:
    _client().delete_object(Bucket=settings.R2_BUCKET, Key=key)
