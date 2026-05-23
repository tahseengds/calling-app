"""Acceptance check 5: insert user/conversation/message; verify FK rejection."""
import asyncio
import uuid
from sqlalchemy import text
from app.db import AsyncSessionLocal


async def main() -> None:
    async with AsyncSessionLocal() as s:
        # Insert a user
        user_id = str(uuid.uuid4())
        await s.execute(text(
            "INSERT INTO users (id, name, phone, password_hash) "
            "VALUES (:id, 'Test', '+10000000001', 'x')"
        ), {"id": user_id})

        user2_id = str(uuid.uuid4())
        await s.execute(text(
            "INSERT INTO users (id, name, phone, password_hash) "
            "VALUES (:id, 'Test2', '+10000000002', 'x')"
        ), {"id": user2_id})

        # Insert a conversation
        conv_id = str(uuid.uuid4())
        await s.execute(text(
            "INSERT INTO conversations (id, participant_a, participant_b) "
            "VALUES (:id, :a, :b)"
        ), {"id": conv_id, "a": user_id, "b": user2_id})

        # Insert a valid message
        msg_id = str(uuid.uuid4())
        await s.execute(text(
            "INSERT INTO messages (id, conversation_id, sender_id, message_type, content) "
            "VALUES (:id, :conv, :sender, 'text', 'hello')"
        ), {"id": msg_id, "conv": conv_id, "sender": user_id})

        await s.commit()
        print("INSERT user + conversation + message: OK")

    # FK violation: message with bogus conversation_id must fail
    async with AsyncSessionLocal() as s:
        try:
            await s.execute(text(
                "INSERT INTO messages (id, conversation_id, sender_id, message_type, content) "
                "VALUES (:id, :conv, :sender, 'text', 'bad')"
            ), {"id": str(uuid.uuid4()), "conv": str(uuid.uuid4()), "sender": user_id})
            await s.commit()
            print("ERROR: FK violation was NOT raised — test failed")
        except Exception as e:
            print(f"FK violation correctly rejected: {type(e).__name__}")


asyncio.run(main())
