'' =====================================================================
'' BeginnerChess - analysis.bas
'' See analysis.bi.
'' =====================================================================
#include once "analysis.bi"
#include once "openings.bi"

Dim Shared AGame As ChessGame
Dim Shared AInfo() As PositionInfo
Dim Shared ANext As Integer = 0
Dim Shared AMs As Integer = 250
Dim Shared APlies As Integer = 0
Dim Shared ABook() As Boolean

Function Analysis_WinChance(ByVal score As Integer) As Double
    If score > 2000 Then score = 2000
    If score < -2000 Then score = -2000
    Return 100.0 / (1 + 10 ^ (-score / 400.0))
End Function

Function Analysis_Classify(ByVal loss As Double, ByVal isBest As Boolean) As Integer
    If isBest OrElse loss <= 2 Then Return MC_BEST
    If loss <= 6 Then Return MC_GOOD
    If loss <= 12 Then Return MC_INACCURACY
    If loss <= 22 Then Return MC_MISTAKE
    Return MC_BLUNDER
End Function

Function Analysis_ClassName(ByVal c As Integer) As String
    Select Case c
    Case MC_BEST       : Return "Best"
    Case MC_GOOD       : Return "Good"
    Case MC_INACCURACY : Return "Inaccuracy"
    Case MC_MISTAKE    : Return "Mistake"
    Case MC_BLUNDER    : Return "Blunder"
    Case MC_BOOK       : Return "Book"
    End Select
    Return ""
End Function

Sub Analysis_PositionBefore(ByVal i As Integer, ByRef p As Position)
    Dim As String e
    Pos_LoadFEN(p, AGame.startFEN, e)
    Dim As Integer k
    For k = 0 To i - 1
        If k >= APlies Then Exit For
        Pos_MakeMove(p, AGame.pos.undoStack(k).mv)
    Next
End Sub

Sub Analysis_Begin(ByRef g As ChessGame, ByVal msPerPosition As Integer = 250)
    AGame = g
    APlies = g.moveCount
    AMs = msPerPosition
    ReDim AInfo(0 To APlies)
    ReDim ABook(0 To IIf(APlies > 0, APlies - 1, 0))
    ANext = 0
    '' Opening book moves are not judged.
    Static p As Position
    Dim As String e
    Pos_LoadFEN(p, g.startFEN, e)
    Dim As Integer i
    Dim As Boolean inBook = (g.startFEN = START_FEN)
    For i = 0 To APlies - 1
        Dim As ChessMove m = g.pos.undoStack(i).mv
        If inBook Then
            '' Is m one of the book moves here?
            inBook = False
            Dim As Integer tries
            For tries = 0 To 40
                Dim As ChessMove bm
                If Book_Probe(p, tries / 41.0, bm) AndAlso Move_Equal(bm, m) Then inBook = True : Exit For
            Next
        End If
        ABook(i) = inBook
        Pos_MakeMove(p, m)
    Next
End Sub

Function Analysis_Step() As Boolean
    If ANext > APlies Then Return True
    Static p As Position
    Analysis_PositionBefore(ANext, p)
    Dim As PositionInfo Ptr info = @AInfo(ANext)
    If Not Pos_HasLegalMove(p) Then
        info->terminal = True
        info->score = IIf(Pos_InCheck(p), -SCORE_MATE, 0)
        info->bestMove.piece = PC_EMPTY
    Else
        info->terminal = False
        Dim As EngineParams prm
        Engine_LevelParams(LEVEL_ADVANCED, STYLE_BALANCED, prm)
        prm.timeLimitMs = AMs : prm.bookPlies = 0 : prm.maxDepth = 12 : prm.contempt = 0
        Dim As EngineResult res
        Engine_Search(p, prm, res)
        info->score = res.score
        info->bestMove = res.bestMove
    End If
    Dim As Integer ws = info->score
    If ws > 3000 Then ws = 3000
    If ws < -3000 Then ws = -3000
    info->whiteScore = IIf(p.sideToMove = SIDE_WHITE, ws, -ws)
    ANext += 1
    Return ANext > APlies
End Function

Function Analysis_Progress() As Integer
    If APlies < 0 Then Return 100
    Return ANext * 100 \ (APlies + 1)
End Function

Function Analysis_Done() As Boolean
    Return ANext > APlies
End Function

Function Analysis_Plies() As Integer
    Return APlies
End Function

Function Analysis_PlayedMove(ByVal i As Integer) As ChessMove
    Return AGame.pos.undoStack(i).mv
End Function

Function Analysis_BestMove(ByVal i As Integer) As ChessMove
    Return AInfo(i).bestMove
End Function

'' Score of the position before ply i, for the side to move there.
Private Function ScoreBefore(ByVal i As Integer) As Integer
    Return AInfo(i).score
End Function

Function Analysis_Loss(ByVal i As Integer) As Integer
    If i < 0 OrElse i >= APlies OrElse i + 1 >= ANext Then Return 0
    Dim As Double before = Analysis_WinChance(AInfo(i).score)
    Dim As Double after = Analysis_WinChance(-AInfo(i + 1).score)
    Dim As Double loss = before - after
    If loss < 0 Then loss = 0
    Return CInt(loss)
End Function

Function Analysis_Class(ByVal i As Integer) As Integer
    If i < 0 OrElse i >= APlies OrElse i + 1 >= ANext Then Return -1
    If ABook(i) Then Return MC_BOOK
    Dim As Boolean isBest = Move_Equal(AInfo(i).bestMove, AGame.pos.undoStack(i).mv)
    Dim As Double loss = Analysis_WinChance(AInfo(i).score) - Analysis_WinChance(-AInfo(i + 1).score)
    '' Delivering checkmate is always best.
    If AInfo(i + 1).terminal AndAlso AInfo(i + 1).score = -SCORE_MATE Then isBest = True
    Return Analysis_Classify(loss, isBest)
End Function

Function Analysis_WhiteScore(ByVal i As Integer) As Integer
    '' Position after ply i = position before ply i+1.
    Dim As Integer k = i + 1
    If k < 0 Then k = 0
    If k >= ANext Then Return 0
    Return AInfo(k).whiteScore
End Function
