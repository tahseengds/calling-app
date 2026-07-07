from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Database
    POSTGRES_DB: str = "lumin"
    POSTGRES_USER: str = "lumin"
    POSTGRES_PASSWORD: str = ""
    DATABASE_URL: str

    # Redis
    REDIS_URL: str = "redis://redis:6379/0"
    SIGNALING_REDIS_URL: str = "redis://redis:6379/1"

    # JWT
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # TURN
    TURN_SECRET: str = ""
    TURN_HOST: str = "lumin.example.com"  # TODO: replace domain

    # Media
    MEDIA_SECRET: str = ""
    MEDIA_BASE_PATH: str = "/app/media"
    MAX_IMAGE_SIZE_MB: int = 15
    MAX_VIDEO_SIZE_MB: int = 150
    MAX_AUDIO_SIZE_MB: int = 10
    MAX_DOCUMENT_SIZE_MB: int = 25
    MAX_AVATAR_SIZE_MB: int = 5

    # Firebase
    FIREBASE_PROJECT_ID: str = ""
    FIREBASE_SERVICE_ACCOUNT_PATH: str = "/app/firebase-service-account.json"

    # App
    APP_ENV: str = "production"
    DEBUG: bool = False
    DOMAIN: str = "lumin.example.com"  # TODO: replace domain
    MEDIA_URL_SCHEME: str = "https"  # set to http when serving without TLS (e.g. IP-only)

    # Admin access — comma-separated list of emails treated as administrators.
    # Used to gate the support-requests admin views. Matching is
    # case-insensitive. Empty means "no admins" (endpoints 403 for everyone).
    ADMIN_EMAILS: str = ""

    # Optional shared password for the browser (HTTP Basic) support-admin page
    # at /api/support/requests/view. When set, an admin can log in with their
    # ADMIN_EMAILS address + this password. Leave empty to require each admin's
    # own Lumio account password instead.
    ADMIN_PANEL_PASSWORD: str = ""

    @property
    def admin_emails(self) -> set[str]:
        return {
            e.strip().lower()
            for e in self.ADMIN_EMAILS.split(",")
            if e.strip()
        }

    @model_validator(mode="after")
    def _validate_secrets(self) -> "Settings":
        # Fail closed on a weak JWT signing key in production. A short/guessable
        # secret silently weakens every access token. Skipped in DEBUG so local
        # dev can use throwaway values. Recommended: `openssl rand -hex 64`.
        if not self.DEBUG and len(self.JWT_SECRET) < 32:
            raise ValueError(
                "JWT_SECRET must be at least 32 characters in production "
                "(generate with `openssl rand -hex 64`)"
            )
        return self


settings = Settings()
