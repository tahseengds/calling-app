from pydantic import BaseModel


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


class FirebaseSignInRequest(BaseModel):
    """
    Payload for /api/auth/firebase-signin.

    The client has already completed Firebase Auth (Google or email/password)
    and obtained an ID token via FirebaseUser.getIdToken(). We verify that
    token server-side and mint *our own* access + refresh JWTs.
    """

    firebase_id_token: str
    device_id: str
    fcm_token: str | None = None
    # Optional display name supplied by the client on first-time sign-in.
    # Ignored for returning users (their existing name wins).
    name: str | None = None
