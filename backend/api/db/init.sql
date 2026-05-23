-- FamilyLink initial schema — mounted by Postgres on first boot.
-- Future schema changes are managed by Alembic; this file and the
-- initial Alembic migration are kept identical.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                 VARCHAR(100) NOT NULL,
    phone                VARCHAR(20)  NOT NULL UNIQUE,
    avatar_url           TEXT,
    fcm_token            TEXT,
    fcm_token_updated_at TIMESTAMPTZ,
    password_hash        TEXT,
    is_active            BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS contacts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    nickname        VARCHAR(100),
    is_blocked      BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, contact_user_id)
);

CREATE TABLE IF NOT EXISTS conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_a   UUID        NOT NULL REFERENCES users(id),
    participant_b   UUID        NOT NULL REFERENCES users(id),
    -- last_message_id is a plain UUID with no FK to avoid circular dependency
    -- with messages. Application code keeps it consistent.
    last_message_id UUID,
    last_activity   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(participant_a, participant_b)
);

CREATE TABLE IF NOT EXISTS media_files (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uploader_id             UUID         NOT NULL REFERENCES users(id),
    file_type               VARCHAR(20)  NOT NULL,
    original_name           VARCHAR(255),
    stored_name             VARCHAR(255),
    mime_type               VARCHAR(100),
    file_size               BIGINT,
    duration_seconds        INTEGER,
    thumbnail_stored_name   VARCHAR(255),
    width                   INTEGER,
    height                  INTEGER,
    storage_path            TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at              TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID        NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID        NOT NULL REFERENCES users(id),
    message_type    VARCHAR(20) NOT NULL,
    content         TEXT,
    media_id        UUID        REFERENCES media_files(id),
    reply_to_id     UUID        REFERENCES messages(id),
    status          VARCHAR(20) NOT NULL DEFAULT 'sent',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS message_receipts (
    message_id   UUID        NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id      UUID        NOT NULL REFERENCES users(id),
    delivered_at TIMESTAMPTZ,
    read_at      TIMESTAMPTZ,
    PRIMARY KEY(message_id, user_id)
);

CREATE TABLE IF NOT EXISTS call_records (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id        UUID        NOT NULL REFERENCES users(id),
    callee_id        UUID        NOT NULL REFERENCES users(id),
    call_type        VARCHAR(10) NOT NULL,
    status           VARCHAR(20) NOT NULL,
    started_at       TIMESTAMPTZ,
    answered_at      TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,
    duration_seconds INTEGER,
    conversation_id  UUID        REFERENCES conversations(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    device_id   VARCHAR(255),
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at  TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_messages_conversation  ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender        ON messages(sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_participants     ON call_records(caller_id, callee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contacts_user          ON contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user    ON refresh_tokens(user_id);
