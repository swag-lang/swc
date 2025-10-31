enum A : u32 {}
enum A : *T {}
enum A : **T {}

enum A : *enum {} // swc-expected-error ParserInvalidType
enum A : [*] {} // swc-expected-error ParserInvalidType

enum A : [? /* toto */ s32 {} // swc-expected-error ParserMissingClosing
enum A : [* /* toto */ s32 {} // swc-expected-error ParserMissingClosing
enum A : [.. /* toto */ s32 {} // swc-expected-error ParserMissingClosing
enum A : [0 /* toto */ s32 {} // swc-expected-error ParserMissingClosing

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
