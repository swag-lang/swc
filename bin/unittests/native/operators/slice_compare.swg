#global private

// Two slices compare over their elements, the way the array they view already does: same
// count, then same content. The compare used to read the data pointer alone, so a slice
// copied into other storage answered 'false', and a shorter view over the same storage
// answered 'true'. Every runtime case forces memory-backed operands through
// 'Swag.Optimize(false)' helpers so neither Sema nor the optimizer folds the answer away.

struct Pair
{
    x, y: s32
}

#[Swag.Optimize(false)]
func eqBytes(a, b: const [..] u8)->bool => a == b
#[Swag.Optimize(false)]
func neBytes(a, b: const [..] u8)->bool => a != b
#[Swag.Optimize(false)]
func eqWords(a, b: const [..] u32)->bool => a == b
#[Swag.Optimize(false)]
func eqPairs(a, b: const [..] Pair)->bool => a == b
#[Swag.Optimize(false)]
func isNullSlice(a: #null const [..] u8)->bool => a == null

const MISSING_BYTES: #null const [..] u8 = null

var g_left:  [8] u8
var g_right: [8] u8
var g_words: [2] [4] u32
var g_pairs: [2] [3] Pair

// The same bytes over different storage are equal, and their data pointers are not.
#test
{
    g_left  = [1, 2, 3, 4, 5, 6, 7, 8]
    g_right = [1, 2, 3, 4, 5, 6, 7, 8]

    let left  = g_left[0 to 7]
    let right = g_right[0 to 7]

    Swag.assert(left.buffer != right.buffer)
    Swag.assert(eqBytes(left, right))
    Swag.assert(!neBytes(left, right))
}

// A shorter view over the same storage differs by its count alone.
#test
{
    g_left = [1, 2, 3, 4, 5, 6, 7, 8]

    let whole = g_left[0 to 7]
    let head  = g_left[0 to 3]

    Swag.assert(whole.buffer == head.buffer)
    Swag.assert(neBytes(whole, head))
    Swag.assert(!eqBytes(whole, head))
}

// A difference in the last element only must still be seen.
#test
{
    g_left  = [1, 2, 3, 4, 5, 6, 7, 8]
    g_right = [1, 2, 3, 4, 5, 6, 7, 9]

    Swag.assert(neBytes(g_left[0 to 7], g_right[0 to 7]))
    Swag.assert(eqBytes(g_left[0 to 6], g_right[0 to 6]))
}

// Empty views are equal whatever storage they came from.
#test
{
    Swag.assert(eqBytes(g_left[0 until 0], g_right[0 until 0]))
}

// An element wider than a byte scales the compared range.
#test
{
    g_words[0] = [10, 20, 30, 40]
    g_words[1] = [10, 20, 30, 41]

    Swag.assert(eqWords(g_words[0][0 to 2], g_words[1][0 to 2]))
    Swag.assert(!eqWords(g_words[0][0 to 3], g_words[1][0 to 3]))
}

// A slice of structs compares whole elements, trailing field included.
#test
{
    g_pairs[0] = [{1, 2}, {3, 4}, {5, 6}]
    g_pairs[1] = [{1, 2}, {3, 4}, {5, 7}]

    Swag.assert(eqPairs(g_pairs[0][0 to 1], g_pairs[1][0 to 1]))
    Swag.assert(!eqPairs(g_pairs[0][0 to 2], g_pairs[1][0 to 2]))
}

// A comparison against 'null' stays a null test rather than a content test.
#test
{
    g_left = [1, 2, 3, 4, 5, 6, 7, 8]

    Swag.assert(isNullSlice(MISSING_BYTES))
    Swag.assert(!isNullSlice(g_left[0 to 7]))
}

// Constant slices fold to the answer the runtime comparison gives.
#test
{
    const a: const [..] u32 = [1, 2, 3]
    const b: const [..] u32 = [1, 2, 3]
    const c: const [..] u32 = [1, 2, 4]
    const d: const [..] u32 = [1, 2]

    #assert(a == b)
    #assert(a != c)
    #assert(a != d)
}
