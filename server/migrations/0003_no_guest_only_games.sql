-- Version 3: games between two guests are not stored (nobody has a history
-- for them; see docs/PRIVACY.md). Removes such games stored by version 2,
-- and games that belong to nobody after both players deleted their accounts.

DELETE FROM games WHERE white_user_id IS NULL AND black_user_id IS NULL;
