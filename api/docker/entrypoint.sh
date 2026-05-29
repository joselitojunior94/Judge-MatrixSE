#!/usr/bin/env sh
set -eu

if [ "${WAIT_FOR_POSTGRES:-true}" = "true" ]; then
  POSTGRES_HOST="${POSTGRES_HOST:-db}"
  POSTGRES_PORT="${POSTGRES_PORT:-5432}"
  echo "Waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
  until nc -z "${POSTGRES_HOST}" "${POSTGRES_PORT}"; do
    sleep 1
  done
fi

python manage.py migrate --noinput
python manage.py collectstatic --noinput

if [ "${DJANGO_CREATE_SUPERUSER:-false}" = "true" ]; then
  python manage.py shell <<'PY'
import os
from django.contrib.auth import get_user_model

User = get_user_model()
username = os.environ.get("DJANGO_SUPERUSER_USERNAME")
email = os.environ.get("DJANGO_SUPERUSER_EMAIL", "")
password = os.environ.get("DJANGO_SUPERUSER_PASSWORD")

if username and password and not User.objects.filter(username=username).exists():
    User.objects.create_superuser(username=username, email=email, password=password)
    print(f"Created superuser {username}")
PY
fi

exec "$@"
