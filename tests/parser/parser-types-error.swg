// ============================================================================
// Parser Types Error
// ============================================================================

enum A : *enum {} // swc-expected-error {{ParserInvalidType}}
enum A : [*] {} // swc-expected-error {{ParserInvalidType}}

enum A : [? /* toto */ s32 {} // swc-expected-error {{ParserExpectedClosing}}
enum A : [* /* toto */ s32 {} // swc-expected-error {{ParserExpectedClosing}}
enum A : [.. /* toto */ s32 {} // swc-expected-error {{ParserExpectedClosing}}
enum A : [0 /* toto */ s32 {} // swc-expected-error {{ParserExpectedClosing}}

// Invalid: missing/invalid type pieces
enum A : enum {} // swc-expected-error {{ParserInvalidType}}
enum A : [] s32 {} // swc-expected-error {{ParserExpectedArrayDim}}
enum A : [5][] A {} // swc-expected-error {{ParserExpectedArrayDim}}
enum A : * {} // swc-expected-error {{ParserInvalidType}}
enum A : ** {} // swc-expected-error {{ParserInvalidType}}
enum A : & {} // swc-expected-error {{ParserInvalidType}}
enum A : && {} // swc-expected-error {{ParserInvalidType}}
enum A : [ /* toto */ ] s32 {} // swc-expected-error {{ParserExpectedArrayDim}}

// Invalid: bad bracket/closing handling
enum A : [5 /* toto */ A {} // swc-expected-error {{ParserExpectedClosing}}

// Invalid: unexpected tokens after a valid construct
enum A : [5] A ) {} // swc-expected-error {{ParserExpectedToken}}
enum A : [*] [] s32 {} // swc-expected-error {{ParserExpectedArrayDim}}
enum A : [..] [] s32 {} // swc-expected-error {{ParserExpectedArrayDim}}
enum A : [?] [] s32 {} // swc-expected-error {{ParserExpectedArrayDim}}

enum A : [ /* open only */ 0 {} // swc-expected-error {{ParserExpectedClosing}}
