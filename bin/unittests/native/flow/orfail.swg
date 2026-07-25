#global private

// 'e orfail V' catches a failure in the fallible expression 'e' and yields the
// lazily-evaluated fallback 'V' instead, dismissing the error (like 'trycatch',
// but with an explicit value that need not be the type default).

struct OrFailError
{
    using base: Swag.BaseError
}

func orFailParse(s: string)->s32 fail
{
    if s == "" do
        fail OrFailError{base: Swag.BaseError{"empty"}}
    return cast(s32) @countof(s)
}

struct OrFailVec
{
    x, y, z: s32
}

func orFailMakeVec(ok: bool)->OrFailVec fail
{
    if !ok do
        fail OrFailError{base: Swag.BaseError{"no"}}
    return OrFailVec{1, 2, 3}
}

var g_orFailSideEffects = 0

func orFailSideFallback()->s32
{
    g_orFailSideEffects += 1
    return -99
}

// Success yields the operand value; failure yields the fallback; the error is
// dismissed on both paths.
#test
{
    let a = orFailParse("swag") orfail 0
    @assert(a == 4)
    @assert(@err == null)

    let b = orFailParse("") orfail 0
    @assert(b == 0)
    @assert(@err == null)

    let c = orFailParse("") orfail -7
    @assert(c == -7)
}

// The fallback is LAZY: evaluated only on the failure path, exactly once.
#test
{
    g_orFailSideEffects = 0

    let a = orFailParse("hello") orfail orFailSideFallback()
    @assert(a == 5)
    @assert(g_orFailSideEffects == 0)

    let b = orFailParse("") orfail orFailSideFallback()
    @assert(b == -99)
    @assert(g_orFailSideEffects == 1)
}

// Address-backed struct result.
#test
{
    let v = orFailMakeVec(true) orfail OrFailVec{7, 8, 9}
    @assert(v.x == 1 and v.z == 3)

    let w = orFailMakeVec(false) orfail OrFailVec{7, 8, 9}
    @assert(w.x == 7 and w.z == 9)
}

// Nested inside a larger expression.
#test
{
    let n = (orFailParse("") orfail 10) + (orFailParse("abc") orfail 0)
    @assert(n == 13)
}
