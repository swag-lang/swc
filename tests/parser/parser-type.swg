enum A : u32 {}
enum A : *T {}
enum A : **T {}

enum A : *enum {} // swc-expected-error ParserInvalidType
enum A : [*] {} // swc-expected-error ParserInvalidType
enum A : [*] s32 {}