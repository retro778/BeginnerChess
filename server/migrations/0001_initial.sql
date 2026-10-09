-- BeginnerChess server database, version 1.
-- Applied once by persistence.py (table schema_migrations records it).

CREATE TABLE users (
    id                INTEGER PRIMARY KEY,
    username          TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash     TEXT NOT NULL,               -- Argon2id; '' for deleted accounts
    created_at        TEXT NOT NULL,               -- UTC ISO 8601
    status            TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'suspended', 'deleted')),
    rating            INTEGER NOT NULL DEFAULT 1200,
    rated_games       INTEGER NOT NULL DEFAULT 0,
    games             INTEGER NOT NULL DEFAULT 0,
    wins              INTEGER NOT NULL DEFAULT 0,
    losses            INTEGER NOT NULL DEFAULT 0,
    draws             INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE sessions (
    id                INTEGER PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash        TEXT NOT NULL UNIQUE,        -- SHA-256 of the token; the token itself is never stored
    created_at        TEXT NOT NULL,
    expires_at        TEXT NOT NULL,
    last_used_at      TEXT NOT NULL
);
CREATE INDEX idx_sessions_user ON sessions(user_id);

CREATE TABLE games (
    id                TEXT PRIMARY KEY,
    white_user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    black_user_id     INTEGER REFERENCES users(id) ON DELETE SET NULL,
    white_name        TEXT NOT NULL,
    black_name        TEXT NOT NULL,
    rated             INTEGER NOT NULL DEFAULT 0,
    initial_ms        INTEGER NOT NULL,
    increment_ms      INTEGER NOT NULL,
    status            TEXT NOT NULL,               -- active | finished | aborted
    result            TEXT,                        -- 1-0 | 0-1 | 1/2-1/2 | NULL
    termination       TEXT,
    moves             TEXT NOT NULL DEFAULT '',    -- UCI moves separated by spaces
    final_fen         TEXT,
    pgn               TEXT,
    started_at        TEXT NOT NULL,
    ended_at          TEXT
);
CREATE INDEX idx_games_white ON games(white_user_id, ended_at);
CREATE INDEX idx_games_black ON games(black_user_id, ended_at);

CREATE TABLE rating_history (
    id                INTEGER PRIMARY KEY,
    user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    game_id           TEXT NOT NULL REFERENCES games(id),
    rating_before     INTEGER NOT NULL,
    rating_after      INTEGER NOT NULL,
    created_at        TEXT NOT NULL
);
CREATE INDEX idx_rating_history_user ON rating_history(user_id, created_at);
