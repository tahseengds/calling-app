from pydantic import BaseModel


class TurnCredentialsResponse(BaseModel):
    username: str
    credential: str
    ttl: int
    uris: list[str]
