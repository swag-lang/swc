// ============================================================================
// Lexer Identifiers Ok
// ============================================================================

// swc-option lex-only

// Identifiers & keywords coverage

// --- Simple identifiers ---
a
abc
a1
a123b
_with_underscores
camelCase
snake_case
UPPER_CASE
mix3d_Case123
value0xFF

// --- Keywords (should be recognized as keywords, not identifiers) ---
if else elif for while switch defer return break continue
struct enum union using typedef const let var
true false null

// --- Built-in types ---
s8 s16 s32 s64 u8 u16 u32 u64 bool string cstring typeinfo

// --- Selected intrinsics ---
@print @assert @panic @countof @dataof @mkslice @mkstring @args @compiler @err

// --- Identifier start/end edge cases ---
_underscoreStart
end_underscore_
a_b_c_d_e
