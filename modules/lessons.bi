'' =====================================================================
'' BeginnerChess - lessons.bi
'' Lessons for "Learn Chess", loaded from text files in data/lessons/.
''
'' File format (one keyword per line, # = comment):
''   LESSON <id>            starts a lesson
''   TITLE <text>           CHAPTER <text>          SUMMARY <text>
''   PAGE                   starts an explanation step (board + text)
''   TASK                   starts a step where the player must move
''   FEN <fen>              position (PAGE positions may leave out kings);
''                          "start" = the normal starting position
''   PLAY <SAN ...>         moves played from the FEN to reach the position
''   TEXT <text>            explanation; several TEXT lines are joined,
''                          "|" starts a new line
''   HIGHLIGHT [green|red|blue|yellow] <squares...>
''   ARROW [green|red|blue|yellow] <e2e4 g1f3 ...>
''   GOAL <kind> [args]     what the player must do (TASK steps):
''        move <SAN...>     one of these moves
''        mate | check | capture | castle | promote | any
''        piece <square>    any move with the piece on that square
''        safe              any move after which the opponent has no
''                          mate in one
''        best              a move the engine rates as good as the best
''        playmate <N>      checkmate the computer within N moves
''        playpromote <N>   promote a pawn within N moves vs the computer
''   REPLY <SAN>            opponent's answer after the previous GOAL
''   HINT / SUCCESS / WRONG <text>
''   FEEDBACK <SAN> <text>  special answer for one wrong move
''   END                    ends the lesson
'' =====================================================================
#pragma once
#include once "game.bi"
#include once "engine.bi"

Const LESSON_MAX_STEPS = 16
Const LESSON_MAX_GOALS = 8

Enum LessonGoalKind
    GOAL_NONE = 0
    GOAL_MOVE
    GOAL_MATE
    GOAL_CHECK
    GOAL_CAPTURE
    GOAL_CASTLE
    GOAL_PROMOTE
    GOAL_ANY
    GOAL_PIECE
    GOAL_SAFE
    GOAL_BEST
    GOAL_PLAYMATE
    GOAL_PLAYPROMOTE
End Enum

Type LessonStep
    isTask     As Boolean
    fen        As String
    playMoves  As String
    text       As String
    highlights As String     '' tokens "1:e4 2:d5" (colour:square)
    arrows     As String     '' tokens "1:e2e4"
    hint       As String
    success    As String
    wrong      As String
    feedback   As String     '' "SAN" & Chr(1) & "text" & Chr(2) ...
    goalCount  As Integer
    goalKind(0 To LESSON_MAX_GOALS - 1)  As Integer
    goalArg(0 To LESSON_MAX_GOALS - 1)   As String
    goalReply(0 To LESSON_MAX_GOALS - 1) As String
End Type

Type Lesson
    id        As String
    title     As String
    chapter   As String
    summary   As String
    stepCount As Integer
    steps(0 To LESSON_MAX_STEPS - 1) As LessonStep
End Type

'' Loads every *.txt file in the folder (in name order). Returns the
'' number of lessons; problems are described in errors (one per line).
Declare Function Lessons_LoadFolder(ByRef folder As Const String, ByRef errors As String) As Integer
Declare Function Lessons_LoadFile(ByRef fileName As Const String, ByRef errors As String) As Integer
Declare Function Lessons_Count() As Integer
Declare Function Lessons_Get(ByVal index As Integer) As Lesson Ptr
Declare Function Lessons_Find(ByRef id As Const String) As Integer

'' Chapters in order of first appearance.
Declare Function Lessons_ChapterCount() As Integer
Declare Function Lessons_ChapterName(ByVal index As Integer) As String

'' Sets up a position for display. Positions without kings (allowed on
'' PAGE steps) are placed on the board without rule checks; isLegal then
'' reports False and the position must not be played on.
Declare Function Lesson_LoadPosition(ByRef fen As Const String, ByRef p As Position, ByRef isLegal As Boolean) As Boolean
'' The position of a step: FEN plus PLAY moves. errMsg explains problems.
Declare Function Lesson_StepPosition(ByRef st As LessonStep, ByRef p As Position, ByRef isLegal As Boolean, _
                                     ByRef errMsg As String) As Boolean

'' Fills board marks from a step's HIGHLIGHT/ARROW data.
Declare Sub Lesson_GetMarks(ByRef st As LessonStep, highlight() As UByte, arrowFrom() As Integer, _
                            arrowTo() As Integer, arrowColor() As Integer, ByRef arrowCount As Integer)

'' Does move m (legal in p) fulfil the goal? p is unchanged afterwards.
Declare Function Lesson_GoalMet(ByVal kind As Integer, ByRef arg As Const String, ByRef p As Position, _
                                ByRef m As ChessMove) As Boolean
'' Friendly description of a goal, e.g. "Give checkmate!".
Declare Function Lesson_GoalText(ByVal kind As Integer, ByRef arg As Const String) As String
'' Feedback text for a specific wrong move (SAN), or "".
Declare Function Lesson_Feedback(ByRef st As LessonStep, ByRef san As Const String) As String
