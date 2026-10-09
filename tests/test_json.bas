'' =====================================================================
'' BeginnerChess - tests/test_json.bas
'' Tests for the JSON reader/writer used by the online mode.
'' =====================================================================
#include once "../modules/json.bi"

Dim Shared TestsPassed As Integer = 0
Dim Shared TestsFailed As Integer = 0

Sub Check(ByVal ok As Boolean, ByRef testName As Const String, ByRef detail As Const String = "")
    If ok Then
        TestsPassed += 1
    Else
        TestsFailed += 1
        Print "  FAIL: " & testName;
        If detail <> "" Then Print "  (" & detail & ")" Else Print
    End If
End Sub

Function Parses(ByRef text As Const String) As Boolean
    Dim As JsonDoc d
    Dim As String e
    Return Json_Parse(d, text, e)
End Function

Const Q = Chr(34)

Sub TestReading()
    Print "Reading..."
    Dim As JsonDoc d
    Dim As String e
    Dim As String text = "{" & Q & "type" & Q & ":" & Q & "move_accepted" & Q & "," & _
        Q & "ply" & Q & ": 5, " & Q & "in_check" & Q & ": true, " & Q & "draw_offer" & Q & ": null," & _
        Q & "clock" & Q & ": {" & Q & "white_ms" & Q & ": 597120, " & Q & "running" & Q & ": " & Q & "b" & Q & "}," & _
        Q & "moves" & Q & ": [" & Q & "e2e4" & Q & ", " & Q & "c7c5" & Q & "], " & _
        Q & "ms" & Q & ": 1791496991000, " & Q & "neg" & Q & ": -2.5e1 }"
    Check Json_Parse(d, text, e), "valid message parses", e
    Check Json_GetStr(d, 0, "type") = "move_accepted", "string member"
    Check Json_GetInt(d, 0, "ply") = 5, "integer member"
    Check Json_GetBool(d, 0, "in_check") = True, "boolean member"
    Check Json_IsNull(d, 0, "draw_offer") AndAlso Json_Has(d, 0, "draw_offer"), "null member"
    Dim As Long clk = Json_Member(d, 0, "clock")
    Check Json_Kind(d, clk) = JK_OBJECT AndAlso Json_GetInt(d, clk, "white_ms") = 597120, "nested object"
    Check Json_GetStr(d, clk, "running") = "b", "nested string"
    Dim As Long mv = Json_Member(d, 0, "moves")
    Check Json_Count(d, mv) = 2 AndAlso Json_Str(d, Json_Item(d, mv, 1)) = "c7c5", "array items"
    Check Json_Item(d, mv, 2) = -1 AndAlso Json_Item(d, mv, -1) = -1, "array bounds"
    Check Json_GetInt(d, 0, "ms") = 1791496991000ll, "large integer (milliseconds)"
    Check Json_GetNum(d, 0, "neg") = -25, "negative exponent number"
    '' Defaults for missing members and wrong kinds.
    Check Json_GetStr(d, 0, "nothing", "dflt") = "dflt", "missing -> default"
    Check Json_GetInt(d, 0, "type", -7) = -7, "wrong kind -> default"
    Check Json_GetStr(d, 0, "ply", "x") = "x", "number is not a string"
    Check Json_Member(d, mv, "type") = -1, "member of an array is -1"
    Check Json_GetStr(d, 12345, "type", "z") = "z", "invalid node -> default"

    '' Escapes and Unicode.
    Check Json_Parse(d, "{" & Q & "s" & Q & ":" & Q & "a\" & Q & "b\\c\/d\n\tAé😀" & Q & "}", e), _
          "escapes parse", e
    Dim As String s = Json_GetStr(d, 0, "s")
    Check s = "a" & Q & "b\c/d" & Chr(10, 9) & "A" & Chr(&hC3, &hA9) & Chr(&hF0, &h9F, &h98, &h80), _
          "escapes decoded (incl. UTF-8 and surrogate pair)"
    '' Top-level values and whitespace.
    Check Json_Parse(d, "  [1, 2 , [3]] ", e) AndAlso Json_Count(d, 0) = 3, "top-level array"
    Check Json_Parse(d, "42", e) AndAlso Json_Num(d, 0) = 42, "top-level number"
    Check Json_Parse(d, "{}", e) AndAlso Json_Count(d, 0) = 0, "empty object"
    '' Duplicate members: the first one wins (documented behaviour).
    Check Json_Parse(d, "{" & Q & "a" & Q & ":1," & Q & "a" & Q & ":2}", e) AndAlso Json_GetInt(d, 0, "a") = 1, _
          "duplicate member: first wins"
End Sub

Sub TestMalformed()
    Print "Malformed input..."
    Dim As String bad(0 To 22) = { _
        "", "   ", "{", "}", "[1,]", "{" & Q & "a" & Q & ":}", "{" & Q & "a" & Q & " 1}", _
        "{a:1}", "{'a':1}", "[1 2]", "01", "1.", ".5", "-", "1e", "+1", "tru", "nul", _
        Q & "abc", Q & "a" & Chr(10) & "b" & Q, Q & "\x" & Q, Q & "\ud800" & Q, "{} {}" }
    Dim As Integer k
    For k = 0 To UBound(bad)
        Check Not Parses(bad(k)), "rejects: " & bad(k)
    Next
    '' Error message explains where.
    Dim As JsonDoc d
    Dim As String e
    Json_Parse(d, "{" & Q & "a" & Q & ": [1, 2", e)
    Check InStr(e, "position") > 0, "error has a position", e
    Check d.nodeCount = 0, "failed parse leaves an empty document"
    '' Deep nesting is refused (no stack overflow).
    Check Not Parses(String(5000, "[") & String(5000, "]")), "deep nesting refused"
    Check Parses(String(20, "[") & String(20, "]")), "moderate nesting accepted"
    '' Binary garbage.
    Check Not Parses(Chr(0, 255, 254, 1, 2, 3)), "binary garbage refused"
End Sub

Sub TestWriting()
    Print "Writing..."
    Dim As JsonWriter w
    JW_Begin(w)
    JW_Str(w, "type", "move")
    JW_Str(w, "request_id", "r5")
    JW_Int(w, "expected_ply", 4)
    JW_Bool(w, "claim_draw", False)
    JW_BeginObj(w, "time_control")
    JW_Int(w, "initial_seconds", 600)
    JW_Int(w, "increment_seconds", 0)
    JW_End(w)
    JW_Null(w, "x")
    Dim As String t = JW_Text(w)
    Check t = "{" & Q & "type" & Q & ":" & Q & "move" & Q & "," & Q & "request_id" & Q & ":" & Q & "r5" & Q & "," & _
              Q & "expected_ply" & Q & ":4," & Q & "claim_draw" & Q & ":false," & Q & "time_control" & Q & ":{" & _
              Q & "initial_seconds" & Q & ":600," & Q & "increment_seconds" & Q & ":0}," & Q & "x" & Q & ":null}", _
          "compact object", t
    '' Round trip of awkward strings.
    Dim As String nasty = "quote" & Q & " back\slash" & Chr(10, 13, 9, 1) & "end"
    JW_Begin(w)
    JW_Str(w, "s", nasty)
    Dim As JsonDoc d
    Dim As String e
    Check Json_Parse(d, JW_Text(w), e) AndAlso Json_GetStr(d, 0, "s") = nasty, "string round trip", e
    Check Json_Quote(Chr(31)) = Q & "\u001F" & Q, "control characters escaped"
    '' Unclosed objects are closed by JW_Text.
    JW_Begin(w)
    JW_BeginObj(w, "a")
    JW_Int(w, "b", 1)
    Check JW_Text(w) = "{" & Q & "a" & Q & ":{" & Q & "b" & Q & ":1}}", "open objects closed"
End Sub

Sub TestSize()
    Print "Size limits..."
    '' A realistic large message: a 300-move game snapshot.
    Dim As String moves = "["
    Dim As Integer k
    For k = 1 To 300
        moves &= IIf(k > 1, ",", "") & Q & "e2e4" & Q
    Next
    moves &= "]"
    Dim As JsonDoc d
    Dim As String e
    Dim As Double t0 = Timer
    Check Json_Parse(d, "{" & Q & "moves" & Q & ":" & moves & "}", e) AndAlso Json_Count(d, Json_Member(d, 0, "moves")) = 300, _
          "300-move array", e
    Check Timer - t0 < 0.5, "parsing is fast"
    Check Not Parses("[" & String(JSON_MAX_TEXT, " ") & "]"), "text over 1 MiB refused"
    Dim As String many = "["
    For k = 1 To JSON_MAX_NODES + 10
        many &= IIf(k > 1, ",", "") & "0"
    Next
    Check Not Parses(many & "]"), "too many values refused"
End Sub

Print "BeginnerChess JSON tests"
TestReading()
TestMalformed()
TestWriting()
TestSize()
Print
Print "Passed: " & TestsPassed & "   Failed: " & TestsFailed
If TestsFailed > 0 Then End 1
End 0
