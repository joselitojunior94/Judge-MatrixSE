from pathlib import Path
import os

import dj_database_url

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/

# SECURITY WARNING: keep the secret key used in production secret!
# In production, set DJANGO_SECRET_KEY environment variable.
SECRET_KEY = os.environ.get(
    'DJANGO_SECRET_KEY',
    'django-insecure-_c)28#j0l98oe6v9ppbuqmj=-yp_khvw5fsmjrro@+mz_tzf%s'
)

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = os.environ.get('DJANGO_DEBUG', 'true').lower() == 'true'

ALLOWED_HOSTS = list({
    host.strip()
    for host in os.environ.get('DJANGO_ALLOWED_HOSTS', '127.0.0.1,localhost').split(',')
    if host.strip()
} | {'127.0.0.1', 'localhost'})  # always allow loopback for internal healthchecks


# Application definition

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework', 
    'corsheaders', 
    'core'
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

CORS_ALLOW_ALL_ORIGINS = (
    DEBUG or os.environ.get('CORS_ALLOW_ALL_ORIGINS', 'false').lower() == 'true'
)
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get('CORS_ALLOWED_ORIGINS', '').split(',')
    if origin.strip()
]
CSRF_TRUSTED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get('CSRF_TRUSTED_ORIGINS', '').split(',')
    if origin.strip()
]

ROOT_URLCONF = 'judge_matrixse_api.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'judge_matrixse_api.wsgi.application'

# Build the database URL from individual POSTGRES_* variables when available.
# This takes priority over DATABASE_URL so that a misconfigured DATABASE_URL
# in the deployment panel never breaks the container.
_pg_host = os.environ.get('POSTGRES_HOST')
_pg_port = os.environ.get('POSTGRES_PORT', '5432')
_pg_user = os.environ.get('POSTGRES_USER')
_pg_pass = os.environ.get('POSTGRES_PASSWORD', '')
_pg_db   = os.environ.get('POSTGRES_DB')

if _pg_host and _pg_user and _pg_db:
    from urllib.parse import quote_plus as _qp
    _DATABASE_URL = f"postgres://{_pg_user}:{_qp(_pg_pass)}@{_pg_host}:{_pg_port}/{_pg_db}"
else:
    _DATABASE_URL = os.environ.get('DATABASE_URL')

if _DATABASE_URL:
    DATABASES = {
        'default': dj_database_url.parse(
            _DATABASE_URL,
            conn_max_age=int(os.environ.get('DB_CONN_MAX_AGE', '600')),
        )
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

REST_FRAMEWORK = {
  'DEFAULT_AUTHENTICATION_CLASSES': ('rest_framework_simplejwt.authentication.JWTAuthentication',),
  'DEFAULT_PERMISSION_CLASSES': ('rest_framework.permissions.IsAuthenticated',),
}

LANGUAGE_CODE = 'en-us'

TIME_ZONE = 'UTC'

USE_I18N = True

USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = os.environ.get('DJANGO_STATIC_ROOT', BASE_DIR / 'staticfiles')
STORAGES = {
    'default': {
        'BACKEND': 'django.core.files.storage.FileSystemStorage',
    },
    'staticfiles': {
        'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage',
    },
}

# Media files (uploaded CSVs, etc.)
MEDIA_URL = '/media/'
MEDIA_ROOT = os.environ.get('DJANGO_MEDIA_ROOT', BASE_DIR / 'media')
SERVE_MEDIA = os.environ.get('DJANGO_SERVE_MEDIA', 'false').lower() == 'true'
PUBLIC_API_BASE_URL = os.environ.get('PUBLIC_API_BASE_URL', '').rstrip('/')

SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE = os.environ.get('DJANGO_SESSION_COOKIE_SECURE', 'false').lower() == 'true'
CSRF_COOKIE_SECURE = os.environ.get('DJANGO_CSRF_COOKIE_SECURE', 'false').lower() == 'true'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# LLM provider settings (used by Phase 8 features). The default is deliberately
# local and deterministic so a fresh install never makes network calls.
LLM_PROVIDER = os.environ.get('LLM_PROVIDER', 'stub')      # 'openai' | 'anthropic' | 'deepseek' | 'stub'
LLM_MODEL    = os.environ.get('LLM_MODEL', 'stub-model-v1')
LLM_API_KEY  = os.environ.get('LLM_API_KEY', '')           # never hardcode; must be set via env
LLM_BASE_URL = os.environ.get('LLM_BASE_URL', '')
