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


settings = Settings()
