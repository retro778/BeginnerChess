'' =====================================================================
'' BeginnerChess - engine.bi
'' The computer chess player.
''
''   Search:     negamax with alpha-beta pruning and principal variation
''               search (PVS), iterative deepening, transposition table,
''               move ordering (hash move, MVV-LVA captures, killer moves,
''               history heuristic), quiescence search, check extension,
''               null-move pruning and late-move reductions.
''   Evaluation: tapered middlegame/endgame score built from material,
''               piece-square tables, development, mobility, king safety,
''               pawn structure, passed pawns, centre control, space, rook
''               files, bishop pair, threats and endgame "mop-up".
''   Personality: playing styles re-weight the evaluation terms; difficulty
''               levels limit depth/time and choose naturally imperfect
''               moves at low levels.
''
'' The engine only uses rules.bas. It can run synchronously or in a
'' background thread so the user interface stays responsive.
'' =====================================================================
#pragma once
#include once "rules.bi"
#include once "openings.bi"

Enum EngineLevel
    LEVEL_BEGINNER = 0
    LEVEL_EASY
    LEVEL_NORMAL
    LEVEL_INTERMEDIATE
    LEVEL_ADVANCED
    LEVEL_COUNT
End Enum

Enum EngineStyle
    STYLE_BALANCED = 0
    STYLE_DEFENSIVE
    STYLE_AGGRESSIVE
    STYLE_POSITIONAL
    STYLE_TACTICAL
    STYLE_MATERIAL
    STYLE_COUNT
End Enum

'' Evaluation terms (also used for explanations in later phases).
Enum EvalTerm
    EV_MATERIAL = 0
    EV_PIECE_SQUARES
    EV_DEVELOPMENT
    EV_MOBILITY
    EV_KING_SAFETY
    EV_PAWN_STRUCTURE
    EV_PASSED_PAWNS
    EV_CENTER
    EV_SPACE
    EV_ROOKS
    EV_BISHOP_PAIR
    EV_THREATS
    EV_ENDGAME
    EVAL_TERM_COUNT
End Enum

Const SCORE_MATE = 30000
Const SCORE_INF = 32000
Const MAX_SEARCH_PLY = 64
Const MAX_PV = 32

Type EngineParams
    maxDepth      As Integer    '' iterative deepening limit (plies)
    timeLimitMs   As Integer    '' 0 = no time limit
    useQuiescence As Boolean    '' False = horizon blunders (beginner)
    noise         As Integer    '' +/- centipawns added to root move scores
    temperature   As Integer    '' softmax temperature for choosing among
                                '' good moves (0 = always the best)
    margin        As Integer    '' only moves within this of the best are
                                '' considered when temperature > 0
    blunderChance As Single     '' chance of a wider, weaker choice
    style         As Integer    '' EngineStyle
    contempt      As Integer    '' how much the engine dislikes draws
    minThinkMs    As Integer    '' GUI waits at least this long (feels natural)
    bookPlies     As Integer    '' use the opening book up to this game ply
End Type

Type EngineResult
    bestMove As ChessMove
    score    As Integer          '' centipawns from the mover's point of view
    depth    As Integer          '' last completed depth
    nodes    As ULongInt
    timeMs   As Integer
    pvLen    As Integer
    pv(0 To MAX_PV - 1) As ChessMove
    fromBook As Boolean          '' move came from the opening book
End Type

'' Recommended parameters for a level and style.
Declare Sub Engine_LevelParams(ByVal level As Integer, ByVal style As Integer, ByRef prm As EngineParams)
Declare Function Engine_LevelName(ByVal level As Integer) As String
Declare Function Engine_StyleName(ByVal style As Integer) As String
Declare Function Engine_LevelDescription(ByVal level As Integer) As String
Declare Function Engine_StyleDescription(ByVal style As Integer) As String

'' Searches position p (left unchanged) and fills res. Returns False only
'' when there is no legal move. The returned move is always legal.
Declare Function Engine_Search(ByRef p As Position, ByRef prm As EngineParams, ByRef res As EngineResult) As Boolean

'' Static evaluation in centipawns from the side to move's point of view.
'' Balanced style unless a style and the engine's side are given.
Declare Function Engine_Evaluate(ByRef p As Position, ByVal style As Integer = STYLE_BALANCED, _
                                 ByVal engineSide As Integer = -1) As Integer
'' Per-term evaluation from White's point of view (for explanations/tests).
Declare Sub Engine_EvaluateTerms(ByRef p As Position, terms() As Integer)

'' Resignation rule. Call once per engine move with the engine's score
'' (from its own point of view) for the position p where it is to move.
'' losingStreak is kept by the caller between moves (start at 0).
'' The engine resigns only when it cannot win and is about to lose:
'' it sees a forced mate against itself, or it has been at least a
'' rook-and-a-half down for three moves in a row - and only if the
'' opponent still has enough material to checkmate.
Declare Function Engine_ShouldResign(ByRef p As Position, ByVal score As Integer, _
                                     ByRef losingStreak As Integer) As Boolean

'' ---- Background thinking --------------------------------------------
Declare Sub Engine_StartAsync(ByRef p As Position, ByRef prm As EngineParams)
'' True once the background search has finished; res receives the result.
Declare Function Engine_PollAsync(ByRef res As EngineResult) As Boolean
Declare Function Engine_IsThinking() As Boolean
'' Stops a running background search and waits for the thread to end.
Declare Sub Engine_StopAsync()
'' Asks a running search to finish soon (the result is still delivered).
Declare Sub Engine_RequestStop()

'' Clears the transposition table, killers and history (new game).
Declare Sub Engine_NewGame()
Declare Sub Engine_Shutdown()
