import re

from pydantic import BaseModel, field_validator


class RegisterRequest(BaseModel):
    name: str
    phone: str
    password: str

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not re.match(r"^\+[1-9]\d{7,14}$", v):
            raise ValueError("Phone must be E.164 format, e.g. +14155552671")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v


class RegisterResponse(BaseModel):
    otp_sent: bool
    # Only populated when DEBUG=true — never expose OTPs in production
    debug_otp: str | None = None


class VerifyOtpRequest(BaseModel):
    phone: str
    otp: str


class LoginRequest(BaseModel):
    phone: str
    password: str
    device_id: str
    fcm_token: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds


class RefreshRequest(BaseModel):
    refresh_token: str
    device_id: str


class LogoutRequest(BaseModel):
    refresh_token: str
