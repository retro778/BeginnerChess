-- Version 2: active games are saved after every move, so that a server
-- restart can restore them (see games.py, "Server restart recovery").

ALTER TABLE games ADD COLUMN white_key TEXT;            -- player id ("u-5" for accounts, "g-..." for guests)
ALTER TABLE games ADD COLUMN black_key TEXT;
ALTER TABLE games ADD COLUMN white_ms INTEGER;          -- remaining time at the last saved move
ALTER TABLE games ADD COLUMN black_ms INTEGER;
ALTER TABLE games ADD COLUMN draw_offer TEXT;
ALTER TABLE games ADD COLUMN seq INTEGER NOT NULL DEFAULT 0;
ALTER TABLE games ADD COLUMN updated_at TEXT;

CREATE INDEX idx_games_status ON games(status);
