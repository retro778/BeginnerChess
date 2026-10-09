"""Online ratings (Elo), calculated only on the server.

* Start: 1200. One rating for all time controls (protocol version 1).
* Expected score: E = 1 / (1 + 10^((R_opponent - R_player) / 400)).
* New rating: R' = round(R + K * (S - E)), S = 1 win, 0.5 draw, 0 loss.
* K = 40 while a player has fewer than 20 rated games ("provisional",
  shown with a question mark), K = 20 afterwards.
* Lowest possible rating: 100.
* Only finished rated games between two registered accounts count; aborted
  games never do. Each game is rated exactly once.
"""

from __future__ import annotations

import logging
from typing import Any

from .persistence import Database

log = logging.getLogger("beginnerchess.ratings")

START_RATING = 1200
PROVISIONAL_GAMES = 20
K_PROVISIONAL = 40
K_ESTABLISHED = 20
MIN_RATING = 100


def expected(rating: int, opponent: int) -> float:
    return 1.0 / (1.0 + 10.0 ** ((opponent - rating) / 400.0))


def k_factor(rated_games: int) -> int:
    return K_PROVISIONAL if rated_games < PROVISIONAL_GAMES else K_ESTABLISHED


def new_rating(rating: int, opponent: int, rated_games: int, score: float) -> int:
    return max(MIN_RATING, round(rating + k_factor(rated_games) * (score - expected(rating, opponent))))


def calc_pair(rw: int, rb: int, nw: int, nb: int, score_white: float) -> tuple[int, int]:
    return new_rating(rw, rb, nw, score_white), new_rating(rb, rw, nb, 1.0 - score_white)


class Ratings:
    def __init__(self, db: Database, presence):
        self.db = db
        self.presence = presence

    async def on_game_end(self, game) -> None:
        """After the game has been stored: rate it and tell both players."""
        if not game.rated or game.status != "finished" or game.result is None:
            return
        wid, bid = game.white.account_id, game.black.account_id
        if wid is None or bid is None:
            return
        score = {"1-0": 1.0, "0-1": 0.0, "1/2-1/2": 0.5}[game.result]
        change = await self.db.rate_game(game.game_id, wid, bid, score, calc_pair)
        if change is None:
            return
        msg: dict[str, Any] = {"type": "rating_update", "game_id": game.game_id}
        for colour, player in (("w", game.white), ("b", game.black)):
            before, after = change[colour]
            player.rating = after
            user = await self.db.user_by_id(player.account_id)
            player.provisional = user is not None and user["rated_games"] < PROVISIONAL_GAMES
            msg["white" if colour == "w" else "black"] = {"before": before, "after": after,
                                                          "provisional": player.provisional}
        log.info("event=rated game=%s white=%s->%s black=%s->%s", game.game_id,
                 change["w"][0], change["w"][1], change["b"][0], change["b"][1])
        for player in (game.white, game.black):
            await self.presence.send(player, msg)
