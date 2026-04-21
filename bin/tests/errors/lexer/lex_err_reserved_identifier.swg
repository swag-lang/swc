#global fileprivate

// Any identifier beginning with two underscores is reserved, regardless of the declaration kind.
var __a = 0                // swc-expected-error {{lex_err_reserved_identifier}}
const __b: s32 = 1         // swc-expected-error {{lex_err_reserved_identifier}}
func __c() {}              // swc-expected-error {{lex_err_reserved_identifier}}
struct __D {}              // swc-expected-error {{lex_err_reserved_identifier}}
