'' =====================================================================
'' BeginnerChess - json.bas
'' Strict JSON reader/writer. See json.bi.
'' =====================================================================
#include once "json.bi"

Type JsonParser
    p      As UByte Ptr          '' the text being parsed
    n      As Long               '' its length
    pos    As Long               '' current position (0-based)
    errMsg As String
End Type

Private Function NewNode(ByRef doc As JsonDoc, ByVal kind As Integer, ByRef jp As JsonParser) As Long
    If doc.nodeCount >= JSON_MAX_NODES Then
        If jp.errMsg = "" Then jp.errMsg = "too many values"
        Return -1
    End If
    If doc.nodeCount > UBound(doc.nodes) Then
        Dim As Long newSize = (UBound(doc.nodes) + 1) * 2
        If newSize < 64 Then newSize = 64
        ReDim Preserve doc.nodes(0 To newSize - 1)
    End If
    Dim As Long i = doc.nodeCount
    doc.nodeCount += 1
    With doc.nodes(i)
        .kind = kind
        .bval = False
        .num = 0
        .sval = ""
        .key = ""
        .firstChild = -1
        .lastChild = -1
        .nextSibling = -1
        .count = 0
    End With
    Return i
End Function

Private Sub AddChild(ByRef doc As JsonDoc, ByVal parent As Long, ByVal child As Long)
    If doc.nodes(parent).lastChild < 0 Then
        doc.nodes(parent).firstChild = child
    Else
        doc.nodes(doc.nodes(parent).lastChild).nextSibling = child
    End If
    doc.nodes(parent).lastChild = child
    doc.nodes(parent).count += 1
End Sub

Private Sub SkipSpace(ByRef jp As JsonParser)
    Do While jp.pos < jp.n
        Select Case jp.p[jp.pos]
        Case 32, 9, 10, 13 : jp.pos += 1
        Case Else : Exit Do
        End Select
    Loop
End Sub

Private Sub SetError(ByRef jp As JsonParser, ByRef msg As Const String)
    If jp.errMsg = "" Then jp.errMsg = msg & " at position " & (jp.pos + 1)
End Sub

'' Bytes a..b-1 of the text as a string.
Private Function Slice(ByRef jp As JsonParser, ByVal a As Long, ByVal b As Long) As String
    Dim As String s = Space(b - a)
    Dim As Long k
    For k = 0 To b - a - 1
        s[k] = jp.p[a + k]
    Next
    Return s
End Function

'' Appends code point cp as UTF-8.
Private Sub PutUtf8(ByRef s As String, ByVal cp As ULong)
    If cp < &h80 Then
        s &= Chr(cp)
    ElseIf cp < &h800 Then
        s &= Chr(&hC0 Or (cp Shr 6), &h80 Or (cp And &h3F))
    ElseIf cp < &h10000 Then
        s &= Chr(&hE0 Or (cp Shr 12), &h80 Or ((cp Shr 6) And &h3F), &h80 Or (cp And &h3F))
    Else
        s &= Chr(&hF0 Or (cp Shr 18), &h80 Or ((cp Shr 12) And &h3F), _
                 &h80 Or ((cp Shr 6) And &h3F), &h80 Or (cp And &h3F))
    End If
End Sub

Private Function Hex4(ByRef jp As JsonParser, ByRef value As ULong) As Boolean
    If jp.pos + 4 > jp.n Then Return False
    value = 0
    Dim As Integer k
    For k = 0 To 3
        Dim As Integer c = jp.p[jp.pos + k], d
        Select Case c
        Case 48 To 57 : d = c - 48
        Case 65 To 70 : d = c - 55
        Case 97 To 102 : d = c - 87
        Case Else : Return False
        End Select
        value = value * 16 + d
    Next
    jp.pos += 4
    Return True
End Function

'' Reads a string literal (jp.pos at the opening quote) into result.
Private Function ParseString(ByRef jp As JsonParser, ByRef result As String) As Boolean
    result = ""
    jp.pos += 1
    Dim As Long runStart = jp.pos
    Do
        If jp.pos >= jp.n Then
            SetError(jp, "unterminated string")
            Return False
        End If
        Dim As Integer c = jp.p[jp.pos]
        If c = 34 Then                                       '' closing quote
            result &= Slice(jp, runStart, jp.pos)
            jp.pos += 1
            Return True
        ElseIf c = 92 Then                                   '' escape
            result &= Slice(jp, runStart, jp.pos)
            jp.pos += 1
            If jp.pos >= jp.n Then
                SetError(jp, "unterminated string")
                Return False
            End If
            Dim As Integer e = jp.p[jp.pos]
            jp.pos += 1
            Select Case e
            Case 34 : result &= Chr(34)
            Case 92 : result &= Chr(92)
            Case 47 : result &= "/"
            Case 98 : result &= Chr(8)
            Case 102 : result &= Chr(12)
            Case 110 : result &= Chr(10)
            Case 114 : result &= Chr(13)
            Case 116 : result &= Chr(9)
            Case 117
                Dim As ULong cp, lo
                If Not Hex4(jp, cp) Then
                    SetError(jp, "bad \u escape")
                    Return False
                End If
                If cp >= &hD800 AndAlso cp <= &hDBFF Then        '' high surrogate: low one must follow
                    If jp.pos + 1 < jp.n AndAlso jp.p[jp.pos] = 92 AndAlso jp.p[jp.pos + 1] = 117 Then
                        jp.pos += 2
                        If (Not Hex4(jp, lo)) OrElse lo < &hDC00 OrElse lo > &hDFFF Then
                            SetError(jp, "bad surrogate pair")
                            Return False
                        End If
                        cp = &h10000 + ((cp - &hD800) Shl 10) + (lo - &hDC00)
                    Else
                        SetError(jp, "bad surrogate pair")
                        Return False
                    End If
                ElseIf cp >= &hDC00 AndAlso cp <= &hDFFF Then
                    SetError(jp, "bad surrogate pair")
                    Return False
                End If
                PutUtf8(result, cp)
            Case Else
                jp.pos -= 1
                SetError(jp, "bad escape")
                Return False
            End Select
            runStart = jp.pos
        ElseIf c < 32 Then
            SetError(jp, "control character in string")
            Return False
        Else
            jp.pos += 1
        End If
    Loop
End Function

Private Function IsDigit(ByVal c As Integer) As Boolean
    Return c >= 48 AndAlso c <= 57
End Function

'' Strict JSON number grammar: -?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?
Private Function ParseNumber(ByRef jp As JsonParser, ByRef value As Double) As Boolean
    Dim As Long start = jp.pos
    If jp.pos < jp.n AndAlso jp.p[jp.pos] = 45 Then jp.pos += 1
    If jp.pos >= jp.n OrElse Not IsDigit(jp.p[jp.pos]) Then
        SetError(jp, "bad number")
        Return False
    End If
    If jp.p[jp.pos] = 48 Then
        jp.pos += 1
        If jp.pos < jp.n AndAlso IsDigit(jp.p[jp.pos]) Then
            SetError(jp, "numbers may not start with 0")
            Return False
        End If
    Else
        Do While jp.pos < jp.n AndAlso IsDigit(jp.p[jp.pos])
            jp.pos += 1
        Loop
    End If
    If jp.pos < jp.n AndAlso jp.p[jp.pos] = 46 Then
        jp.pos += 1
        If jp.pos >= jp.n OrElse Not IsDigit(jp.p[jp.pos]) Then
            SetError(jp, "bad number")
            Return False
        End If
        Do While jp.pos < jp.n AndAlso IsDigit(jp.p[jp.pos])
            jp.pos += 1
        Loop
    End If
    If jp.pos < jp.n AndAlso (jp.p[jp.pos] = 101 OrElse jp.p[jp.pos] = 69) Then
        jp.pos += 1
        If jp.pos < jp.n AndAlso (jp.p[jp.pos] = 43 OrElse jp.p[jp.pos] = 45) Then jp.pos += 1
        If jp.pos >= jp.n OrElse Not IsDigit(jp.p[jp.pos]) Then
            SetError(jp, "bad number")
            Return False
        End If
        Do While jp.pos < jp.n AndAlso IsDigit(jp.p[jp.pos])
            jp.pos += 1
        Loop
    End If
    value = Val(Slice(jp, start, jp.pos))
    Return True
End Function

Private Function Literal(ByRef jp As JsonParser, ByRef word As Const String) As Boolean
    Dim As Long k
    If jp.pos + Len(word) > jp.n Then Return False
    For k = 0 To Len(word) - 1
        If jp.p[jp.pos + k] <> word[k] Then Return False
    Next
    jp.pos += Len(word)
    Return True
End Function

'' Parses one value; returns its node index or -1.
Private Function ParseValue(ByRef doc As JsonDoc, ByRef jp As JsonParser, ByVal depth As Integer) As Long
    If depth > JSON_MAX_DEPTH Then
        SetError(jp, "nested too deeply")
        Return -1
    End If
    SkipSpace(jp)
    If jp.pos >= jp.n Then
        SetError(jp, "unexpected end")
        Return -1
    End If
    Dim As Integer c = jp.p[jp.pos]
    Dim As Long node
    Select Case c
    Case 123                                                    '' {
        node = NewNode(doc, JK_OBJECT, jp)
        If node < 0 Then Return -1
        jp.pos += 1
        SkipSpace(jp)
        If jp.pos < jp.n AndAlso jp.p[jp.pos] = 125 Then
            jp.pos += 1
            Return node
        End If
        Do
            SkipSpace(jp)
            If jp.pos >= jp.n OrElse jp.p[jp.pos] <> 34 Then
                SetError(jp, "expected a member name")
                Return -1
            End If
            Dim As String keyName
            If Not ParseString(jp, keyName) Then Return -1
            SkipSpace(jp)
            If jp.pos >= jp.n OrElse jp.p[jp.pos] <> 58 Then
                SetError(jp, "expected ':'")
                Return -1
            End If
            jp.pos += 1
            Dim As Long child = ParseValue(doc, jp, depth + 1)
            If child < 0 Then Return -1
            doc.nodes(child).key = keyName
            AddChild(doc, node, child)
            SkipSpace(jp)
            If jp.pos < jp.n AndAlso jp.p[jp.pos] = 44 Then
                jp.pos += 1
            ElseIf jp.pos < jp.n AndAlso jp.p[jp.pos] = 125 Then
                jp.pos += 1
                Return node
            Else
                SetError(jp, "expected ',' or '}'")
                Return -1
            End If
        Loop
    Case 91                                                     '' [
        node = NewNode(doc, JK_ARRAY, jp)
        If node < 0 Then Return -1
        jp.pos += 1
        SkipSpace(jp)
        If jp.pos < jp.n AndAlso jp.p[jp.pos] = 93 Then
            jp.pos += 1
            Return node
        End If
        Do
            Dim As Long child = ParseValue(doc, jp, depth + 1)
            If child < 0 Then Return -1
            AddChild(doc, node, child)
            SkipSpace(jp)
            If jp.pos < jp.n AndAlso jp.p[jp.pos] = 44 Then
                jp.pos += 1
            ElseIf jp.pos < jp.n AndAlso jp.p[jp.pos] = 93 Then
                jp.pos += 1
                Return node
            Else
                SetError(jp, "expected ',' or ']'")
                Return -1
            End If
        Loop
    Case 34
        Dim As String s
        If Not ParseString(jp, s) Then Return -1
        node = NewNode(doc, JK_STRING, jp)
        If node >= 0 Then doc.nodes(node).sval = s
        Return node
    Case 116, 102, 110                                          '' true false null
        If Literal(jp, "true") Then
            node = NewNode(doc, JK_BOOL, jp)
            If node >= 0 Then doc.nodes(node).bval = True
            Return node
        ElseIf Literal(jp, "false") Then
            Return NewNode(doc, JK_BOOL, jp)
        ElseIf Literal(jp, "null") Then
            Return NewNode(doc, JK_NULL, jp)
        End If
        SetError(jp, "unknown word")
        Return -1
    Case Else
        If c = 45 OrElse IsDigit(c) Then
            Dim As Double v
            If Not ParseNumber(jp, v) Then Return -1
            node = NewNode(doc, JK_NUMBER, jp)
            If node >= 0 Then doc.nodes(node).num = v
            Return node
        End If
        SetError(jp, "unexpected character")
        Return -1
    End Select
End Function

Function Json_Parse(ByRef doc As JsonDoc, ByRef text As Const String, ByRef errMsg As String) As Boolean
    Erase doc.nodes
    doc.nodeCount = 0
    errMsg = ""
    If Len(text) = 0 Then
        errMsg = "empty text"
        Return False
    End If
    If Len(text) > JSON_MAX_TEXT Then
        errMsg = "text too long"
        Return False
    End If
    Dim As JsonParser jp
    jp.p = Cast(UByte Ptr, StrPtr(text))
    jp.n = Len(text)
    Dim As Long root = ParseValue(doc, jp, 0)
    If root >= 0 Then
        SkipSpace(jp)
        If jp.pos < jp.n Then
            SetError(jp, "unexpected text after the value")
            root = -1
        End If
    End If
    If root < 0 Then
        errMsg = jp.errMsg
        Erase doc.nodes
        doc.nodeCount = 0
        Return False
    End If
    Return True
End Function

'' ---------------------------------------------------------------------
'' Getters
'' ---------------------------------------------------------------------
Private Function ValidNode(ByRef doc As JsonDoc, ByVal node As Long) As Boolean
    Return node >= 0 AndAlso node < doc.nodeCount
End Function

Function Json_Kind(ByRef doc As JsonDoc, ByVal node As Long) As Integer
    If Not ValidNode(doc, node) Then Return JK_NULL
    Return doc.nodes(node).kind
End Function

Function Json_Member(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String) As Long
    If Not ValidNode(doc, obj) Then Return -1
    If doc.nodes(obj).kind <> JK_OBJECT Then Return -1
    Dim As Long c = doc.nodes(obj).firstChild
    Do While c >= 0
        If doc.nodes(c).key = keyName Then Return c
        c = doc.nodes(c).nextSibling
    Loop
    Return -1
End Function

Function Json_Has(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String) As Boolean
    Return Json_Member(doc, obj, keyName) >= 0
End Function

Function Json_IsNull(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String) As Boolean
    Dim As Long m = Json_Member(doc, obj, keyName)
    Return m < 0 OrElse doc.nodes(m).kind = JK_NULL
End Function

Function Json_GetStr(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                     ByRef def As Const String = "") As String
    Dim As Long m = Json_Member(doc, obj, keyName)
    If m < 0 OrElse doc.nodes(m).kind <> JK_STRING Then Return def
    Return doc.nodes(m).sval
End Function

Function Json_GetNum(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                     ByVal def As Double = 0) As Double
    Dim As Long m = Json_Member(doc, obj, keyName)
    If m < 0 OrElse doc.nodes(m).kind <> JK_NUMBER Then Return def
    Return doc.nodes(m).num
End Function

Function Json_GetInt(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                     ByVal def As LongInt = 0) As LongInt
    Dim As Long m = Json_Member(doc, obj, keyName)
    If m < 0 OrElse doc.nodes(m).kind <> JK_NUMBER Then Return def
    Dim As Double v = doc.nodes(m).num
    If v > 9.0e15 OrElse v < -9.0e15 Then Return def
    Return CLngInt(Int(v))
End Function

Function Json_GetBool(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                      ByVal def As Boolean = False) As Boolean
    Dim As Long m = Json_Member(doc, obj, keyName)
    If m < 0 OrElse doc.nodes(m).kind <> JK_BOOL Then Return def
    Return doc.nodes(m).bval
End Function

Function Json_Str(ByRef doc As JsonDoc, ByVal node As Long) As String
    If Not ValidNode(doc, node) Then Return ""
    If doc.nodes(node).kind <> JK_STRING Then Return ""
    Return doc.nodes(node).sval
End Function

Function Json_Num(ByRef doc As JsonDoc, ByVal node As Long) As Double
    If Not ValidNode(doc, node) Then Return 0
    If doc.nodes(node).kind <> JK_NUMBER Then Return 0
    Return doc.nodes(node).num
End Function

Function Json_Count(ByRef doc As JsonDoc, ByVal node As Long) As Long
    If Not ValidNode(doc, node) Then Return 0
    Return doc.nodes(node).count
End Function

Function Json_Item(ByRef doc As JsonDoc, ByVal node As Long, ByVal index As Long) As Long
    If Not ValidNode(doc, node) OrElse index < 0 Then Return -1
    Dim As Long c = doc.nodes(node).firstChild, k = 0
    Do While c >= 0
        If k = index Then Return c
        k += 1
        c = doc.nodes(c).nextSibling
    Loop
    Return -1
End Function

'' ---------------------------------------------------------------------
'' Writer
'' ---------------------------------------------------------------------
Function Json_Quote(ByRef s As Const String) As String
    Dim As String r = Chr(34)
    Dim As Long k
    For k = 0 To Len(s) - 1
        Dim As Integer c = s[k]
        Select Case c
        Case 34 : r &= "\" & Chr(34)
        Case 92 : r &= "\\"
        Case 10 : r &= "\n"
        Case 13 : r &= "\r"
        Case 9 : r &= "\t"
        Case 8 : r &= "\b"
        Case 12 : r &= "\f"
        Case Is < 32 : r &= "\u" & Hex(c, 4)
        Case Else : r &= Chr(c)
        End Select
    Next
    Return r & Chr(34)
End Function

Private Sub WriteKey(ByRef w As JsonWriter, ByRef keyName As Const String)
    If w.needComma(w.depth) Then w.buf &= ","
    w.needComma(w.depth) = True
    w.buf &= Json_Quote(keyName) & ":"
End Sub

Sub JW_Begin(ByRef w As JsonWriter)
    w.buf = "{"
    w.depth = 1
    w.needComma(1) = False
End Sub

Sub JW_Str(ByRef w As JsonWriter, ByRef keyName As Const String, ByRef value As Const String)
    WriteKey(w, keyName)
    w.buf &= Json_Quote(value)
End Sub

Sub JW_Int(ByRef w As JsonWriter, ByRef keyName As Const String, ByVal value As LongInt)
    WriteKey(w, keyName)
    w.buf &= Str(value)
End Sub

Sub JW_Bool(ByRef w As JsonWriter, ByRef keyName As Const String, ByVal value As Boolean)
    WriteKey(w, keyName)
    w.buf &= IIf(value, "true", "false")
End Sub

Sub JW_Null(ByRef w As JsonWriter, ByRef keyName As Const String)
    WriteKey(w, keyName)
    w.buf &= "null"
End Sub

Sub JW_BeginObj(ByRef w As JsonWriter, ByRef keyName As Const String)
    If w.depth >= JSON_MAX_DEPTH Then Exit Sub
    WriteKey(w, keyName)
    w.buf &= "{"
    w.depth += 1
    w.needComma(w.depth) = False
End Sub

Sub JW_End(ByRef w As JsonWriter)
    If w.depth <= 0 Then Exit Sub
    w.buf &= "}"
    w.depth -= 1
End Sub

Function JW_Text(ByRef w As JsonWriter) As String
    Do While w.depth > 0
        JW_End(w)
    Loop
    Return w.buf
End Function
