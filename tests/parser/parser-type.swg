enum A : u32 {}
enum A : *T {}
enum A : **T {}

enum A : *enum {} // swc-expected-error ParserInvalidType
enum A : [*] {} // swc-expected-error ParserInvalidType

enum A : [? /* toto */ s32 {} // swc-expected-error ParserExpectedClosing
enum A : [* /* toto */ s32 {} // swc-expected-error ParserExpectedClosing
enum A : [.. /* toto */ s32 {} // swc-expected-error ParserExpectedClosing
enum A : [0 /* toto */ s32 {} // swc-expected-error ParserExpectedClosing

enum A : [*] s32 {}
enum A : [..] s32 {}
enum A : [?] s32 {}
enum A : [5] A {}
enum A : [5][10] A {}
enum A : [5][10] ****A {}
enum A : [5][..] ****A {}
enum A : &A {}
enum A : &&A {}
enum A : *const *A {}

enum A : [/* toto */ * ] s32 {}

// Valid: pointers + arrays + qualifiers
enum A : *A {}
enum A : *const A {}
enum A : **A {}
enum A : *const *A {}
enum A : *[5]A {}
enum A : [5]*A {}
enum A : [5][10]*const A {}
enum A : [/* c */5] A {}
enum A : [5] /* c */ [10] A {}
enum A : &*A {}
enum A : &&*A {}
enum A : [5][..] *const *A {}
enum A : [*] *A {}
enum A : [..] &A {}
enum A : [?] &A {}

// Invalid: missing/invalid type pieces
enum A : enum {} // swc-expected-error ParserInvalidType
enum A : [] s32 {}
enum A : [5][] A {}
enum A : * {} // swc-expected-error ParserInvalidType
enum A : ** {} // swc-expected-error ParserInvalidType
enum A : & {} // swc-expected-error ParserInvalidType
enum A : && {} // swc-expected-error ParserInvalidType
enum A : [ /* toto */ ] s32 {}

// Invalid: bad bracket/closing handling
enum A : [5 /* toto */ A {} // swc-expected-error ParserExpectedClosing

enum A : [* /* stuck */ ] s32 {}
enum A : [.. /* stuck */ ] s32 {}
enum A : [? /* stuck */ ] s32 {}

// Invalid: unexpected tokens after a valid construct
enum A : [5] A ) {} // swc-expected-error ParserExpectedToken
enum A : [*] [] s32 {}
enum A : [..] [] s32 {}
enum A : [?] [] s32 {}

// Valid: more combos to stress nesting
enum A : [1][2][3] ***A {}
enum A : & & A {}
enum A : *const [5]A {}
enum A : [5]*const *A {}

// swc-expected-error@+ ParserInvalidType
enum A : [ /* open only */ 0 {} // swc-expected-error ParserExpectedClosing
