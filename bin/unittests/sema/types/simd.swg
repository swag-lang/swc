#global private
using Swag

// The '#simd [N] T' type family: every legal 16-byte shape, its size and
// alignment, and the compile-time construction forms (array literal, exact
// array reinterpretation, scalar splat, '#bit' reshape).

var g0: #simd [16] u8
var g1: #simd [16] s8
var g2: #simd [8] u16
var g3: #simd [8] s16
var g4: #simd [4] u32
var g5: #simd [4] s32
var g6: #simd [2] u64
var g7: #simd [2] s64
var g8: #simd [4] f32
var g9: #simd [2] f64

#assert(#sizeof(g0) == 16)
#assert(#sizeof(g3) == 16)
#assert(#sizeof(g8) == 16)
#assert(#alignof(g0) == 16)
#assert(#alignof(g5) == 16)
#assert(#alignof(g9) == 16)

// An alias of a native lane type is the same vector type as the native spelling.
alias Byte = u8
var g10: #simd [16] Byte
#assert(#typeof(g10) == #typeof(g0))

// An alias can name a vector type itself.
alias Bytes16 = #simd [16] u8
var g11: Bytes16
#assert(#typeof(g11) == #typeof(g0))

// Construction folds at compile time: from a full array literal, from a
// scalar splat, and bit for bit from the matching fixed-size array.
const FromLiteral: #simd [4] s32 = [1, 2, 3, 4]
const FromCast                   = cast(#simd [4] s32) [5, 6, 7, 8]
const Splat                      = Swag.vecsplat(42's16)
const Lanes:       [4] s32       = [9, 10, 11, 12]
const FromArray                  = cast(#simd [4] s32) Lanes
const Reshaped                   = cast #bit(#simd [16] u8) FromCast
const BackToArray                = cast([4] s32) FromArray

#assert(BackToArray[0] == 9)
#assert(BackToArray[3] == 12)

// A 'const' qualifier is accepted on the vector type.
func takeVector(v: const #simd [4] f32) {}
