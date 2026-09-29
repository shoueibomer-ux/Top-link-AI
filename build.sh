#!/usr/bin/env bash
# Render's build command for the Django backend (see render.yaml). Runs on
# every deploy, before the new instance is put into rotation.
set -o errexit

pip install -r requirements.txt

# Writes whitenoise's content-hashed static files to STATIC_ROOT (see
# config/settings.py) — must run after every dependency install, since admin/
# DRF's own static assets come from those packages.
python manage.py collectstatic --no-input

# Applies pending migrations before the new code starts serving traffic.
python manage.py migrate

# Bootstraps a Django admin login from DJANGO_SUPERUSER_* env vars, if set
# and the account doesn't already exist — see accounts/management/commands/
# create_superuser_from_env.py. A no-op if those vars aren't set (they're
# optional) or the account already exists, so this is safe on every deploy.
python manage.py create_superuser_from_env
