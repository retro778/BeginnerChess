'' =====================================================================
'' BeginnerChess - json.bi
'' A small, strict JSON reader and writer (RFC 8259) for the online mode.
''
'' Reading: Json_Parse turns a text into a tree of nodes inside a JsonDoc.
'' Nodes are addressed by index; 0 is the root. Getters never fail: a
'' missing member or a value of the wrong kind gives the default value.
'' Limits protect against hostile input: nesting depth, number of nodes,
'' text length.
''
'' Writing: JsonWriter builds a compact object, escaping strings correctly.
'' =====================================================================
#pragma once

Enum JsonKind
    JK_NULL = 0
    JK_BOOL
    JK_NUMBER
    JK_STRING
    JK_ARRAY
    JK_OBJECT
End Enum

Const JSON_MAX_DEPTH = 32
Const JSON_MAX_NODES = 50000
Const JSON_MAX_TEXT = 1048576        '' 1 MiB

Type JsonNode
    kind        As Byte
    bval        As Boolean
    num         As Double
    sval        As String            '' string value (UTF-8)
    key         As String            '' member name when the parent is an object
    firstChild  As Long = -1
    lastChild   As Long = -1
    nextSibling As Long = -1
    count       As Long              '' number of children
End Type

Type JsonDoc
    nodes(Any) As JsonNode
    nodeCount  As Long
End Type

'' Parses text into doc (old contents are discarded). On failure returns
'' False and errMsg describes the problem (doc is then empty).
Declare Function Json_Parse(ByRef doc As JsonDoc, ByRef text As Const String, ByRef errMsg As String) As Boolean

Declare Function Json_Kind(ByRef doc As JsonDoc, ByVal node As Long) As Integer
'' Member of an object node (-1 if missing or node is not an object).
Declare Function Json_Member(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String) As Long
Declare Function Json_Has(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String) As Boolean
Declare Function Json_IsNull(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String) As Boolean
Declare Function Json_GetStr(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                             ByRef def As Const String = "") As String
Declare Function Json_GetNum(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                             ByVal def As Double = 0) As Double
Declare Function Json_GetInt(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                             ByVal def As LongInt = 0) As LongInt
Declare Function Json_GetBool(ByRef doc As JsonDoc, ByVal obj As Long, ByRef keyName As Const String, _
                              ByVal def As Boolean = False) As Boolean
'' Value of a node itself.
Declare Function Json_Str(ByRef doc As JsonDoc, ByVal node As Long) As String
Declare Function Json_Num(ByRef doc As JsonDoc, ByVal node As Long) As Double
'' Arrays (and objects): number of children and the i-th child (0-based, -1 if out of range).
Declare Function Json_Count(ByRef doc As JsonDoc, ByVal node As Long) As Long
Declare Function Json_Item(ByRef doc As JsonDoc, ByVal node As Long, ByVal index As Long) As Long

'' ---- Writing ---------------------------------------------------------
Type JsonWriter
    buf          As String
    depth        As Integer
    needComma(0 To JSON_MAX_DEPTH) As Boolean
End Type

'' A JSON string literal with quotes and escapes ("a\"b").
Declare Function Json_Quote(ByRef s As Const String) As String
Declare Sub JW_Begin(ByRef w As JsonWriter)                       '' starts the outer object
Declare Sub JW_Str(ByRef w As JsonWriter, ByRef keyName As Const String, ByRef value As Const String)
Declare Sub JW_Int(ByRef w As JsonWriter, ByRef keyName As Const String, ByVal value As LongInt)
Declare Sub JW_Bool(ByRef w As JsonWriter, ByRef keyName As Const String, ByVal value As Boolean)
Declare Sub JW_Null(ByRef w As JsonWriter, ByRef keyName As Const String)
Declare Sub JW_BeginObj(ByRef w As JsonWriter, ByRef keyName As Const String)
Declare Sub JW_End(ByRef w As JsonWriter)                         '' closes the innermost object
'' The finished text (closes any objects still open).
Declare Function JW_Text(ByRef w As JsonWriter) As String
