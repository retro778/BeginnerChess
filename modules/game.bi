'' =====================================================================
'' BeginnerChess - game.bi
'' A chess game: the current position, the move record (with SAN), the
'' result, and the rules that end a game (mate, stalemate, draws,
'' resignation, agreement). The GUI and the engine both go through this
'' module to play moves; it is the single authority on game state.
'' =====================================================================
#pragma once
#include once "rules.bi"
#include once "notation.bi"

Enum GameResult
    RESULT_ONGOING = 0
    RESULT_WHITE_WINS
    RESULT_BLACK_WINS
    RESULT_DRAW
End Enum

Enum GameTermination
    TERM_NONE = 0
    TERM_CHECKMATE
    TERM_STALEMATE
    TERM_THREEFOLD
    TERM_FIFTY_MOVE
    TERM_INSUFFICIENT
    TERM_AGREEMENT
    TERM_RESIGNATION
    TERM_FIVEFOLD             '' automatic draw (FIDE 9.6.1)
    TERM_SEVENTY_FIVE_MOVE    '' automatic draw (FIDE 9.6.2)
End Enum

Type ChessGame
    pos         As Position
    startFEN    As String
    sanMoves(0 To MAX_HISTORY - 1) As String
    comments(0 To MAX_HISTORY - 1) As String   '' comment after each ply (PGN)
    moveCount   As Integer          '' plies played in this game
    result      As GameResult
    termination As GameTermination
End Type

'' Starts a new game from the standard position.
Declare Sub Game_New(ByRef g As ChessGame)
'' Starts a new game from a FEN position.
Declare Function Game_NewFromFEN(ByRef g As ChessGame, ByRef fen As Const String, _
                                 ByRef errMsg As String) As Boolean

'' Plays a move if it is legal and the game is not over.
Declare Function Game_PlayMove(ByRef g As ChessGame, ByRef m As ChessMove, _
                               ByRef errMsg As String) As Boolean
'' Plays a move typed as SAN ("Nf3") or coordinates ("g1f3").
Declare Function Game_PlayMoveText(ByRef g As ChessGame, ByRef text As Const String, _
                                   ByRef errMsg As String) As Boolean
'' Takes back the last move. Also clears a finished game's result.
Declare Function Game_Undo(ByRef g As ChessGame) As Boolean

'' Ends the game by resignation of 'side', or by mutual agreement.
Declare Sub Game_Resign(ByRef g As ChessGame, ByVal side As Integer)
Declare Sub Game_AgreeDraw(ByRef g As ChessGame)
'' Applies a result read from a PGN file ("1-0", "0-1", "1/2-1/2", "*")
'' when the position itself has not ended the game. Returns False for an
'' unknown result string.
Declare Function Game_ApplyResult(ByRef g As ChessGame, ByRef result As Const String) As Boolean

'' Re-examines the position and sets result/termination for the endings
'' that happen automatically: checkmate, stalemate, insufficient
'' material, fivefold repetition and the 75-move rule.
Declare Sub Game_UpdateStatus(ByRef g As ChessGame)

'' Tournament draw claims (FIDE 9.2 / 9.3). The player to move may claim a
'' draw when the current position has occurred three times, or when the
'' last 50 moves by each side contained no capture or pawn move...
Declare Function Game_ClaimableDraw(ByRef g As ChessGame) As GameTermination
Declare Function Game_ClaimDraw(ByRef g As ChessGame) As Boolean
'' ...or when the move they intend to play would produce such a position.
'' Game_ClaimDrawWithMove plays that move and then ends the game drawn.
Declare Function Game_ClaimableDrawWithMove(ByRef g As ChessGame, ByRef m As ChessMove) As GameTermination
Declare Function Game_ClaimDrawWithMove(ByRef g As ChessGame, ByRef m As ChessMove, _
                                        ByRef errMsg As String) As Boolean
'' Friendly explanation of an available claim, or "" if none.
Declare Function Game_ClaimHint(ByRef g As ChessGame) As String

Declare Function Game_IsOver(ByRef g As ChessGame) As Boolean
Declare Function Game_LastMove(ByRef g As ChessGame) As ChessMove
Declare Function Game_ResultString(ByRef g As ChessGame) As String   '' "1-0", "0-1", "1/2-1/2", "*"
Declare Function Game_StatusText(ByRef g As ChessGame) As String     '' friendly description
Declare Function Game_MoveListText(ByRef g As ChessGame) As String   '' "1. e4 e5 2. Nf3 ..."
Declare Function Side_Name(ByVal side As Integer) As String
