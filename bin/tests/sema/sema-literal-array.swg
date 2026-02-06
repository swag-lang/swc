#global internal

// -----------------------------------------------------------------------------
// Array literals: type inference, casting, indexing, and error cases
// -----------------------------------------------------------------------------

// jagged / non-rectangular nested array should fail (cannot form a single array type)
const At = [[1, 2], [3, 4, 5]] // swc-expected-error {{sema_err_cannot_cast}}

// explicit integer literal suffix drives array element type
const A = [1's32, 2, 3, 4, 5]
#assert(#typeof(A) == #type [5] s32)

// default integer literals infer s32 for the array
const A1 = [1, 2, 3, 4, 5]
#assert(#typeof(A1) == #type [5] s32)

// explicit float suffix drives array element type
const Af = [1.0'f64, 2.0]
#assert(#typeof(Af) == #type [2] f64)

// -----------------------------------------------------------------------------
// locals: inference from variables, and float/int mixing rules
// -----------------------------------------------------------------------------
#test
{
    var x = 1
    var B = [x, 2, 3]
    #assert(#typeof(B) == #type [3] s32)

    // same again (kept to ensure repeated inference paths stay stable)
    var C = [x, 2, 3]
    #assert(#typeof(C) == #type [3] s32)

    // float literal + int literal: int must be explicitly casted to float
    var D = [1.0'f32, cast(f32) 2]
    #assert(#typeof(D) == #type [2] f32)
    #assert(#typeof(D[0]) == f32)
    #assert(#typeof(D[1]) == f32)
}

// empty array literal should fail (no element type / size info)
#test
{
    var E = [] // swc-expected-error {{sema_err_empty_array_literal}}
}

// heterogeneous element types without a valid cast path should fail
#test
{
    var F = ["hello", 1] // swc-expected-error {{sema_err_cannot_cast}}
}

// -----------------------------------------------------------------------------
// const arrays: default float inference, indexing, and nested arrays
// -----------------------------------------------------------------------------

// float + int literal: int promotes to f32 here (per language rule for const literals)
const G = [1.0, 2]
#assert(#typeof(G) == #type [2] f32)
#assert(#typeof(G[0]) == f32)
#assert(#typeof(G[1]) == f32)
#assert(G[0] == 1.0)
#assert(G[1] == 2.0)

// rectangular nested arrays: ok
const G1 = [[1.0], [2.0], [3.0]]
#assert(#typeof(G1) == #type [3] [1] f32)
#assert(#typeof(G1[0]) == #type [1] f32)
#assert(#typeof(G1[0][0]) == f32)
#assert(G1[2][0] == 3.0)

// -----------------------------------------------------------------------------
// indexing bounds checks
// -----------------------------------------------------------------------------
#test
{
    const H = [1, 2]
    var a = H[-1] // swc-expected-error {{sema_err_index_negative}}
}

#test
{
    const H = [1, 2]
    var b = H[2] // swc-expected-error {{sema_err_index_out_of_range}}
}

// -----------------------------------------------------------------------------
// explicit casts inside arrays
// -----------------------------------------------------------------------------

// explicit cast forces element type agreement
const I = [1, cast(s32) 2.2]
#assert(#typeof(I) == #type [2] s32)
#assert(#typeof(I[0]) == s32)
#assert(#typeof(I[1]) == s32)
#assert(I[1] == 2)

// mixing explicit casts to different element types should be ambiguous
const J = [cast(f32) 1, cast(s32) 2.2] // swc-expected-error {{sema_err_ambiguous_array_type}}

// -----------------------------------------------------------------------------
// additional coverage: size inference + assignment compatibility
// -----------------------------------------------------------------------------
#test
{
    // size is part of the type
    const K = [10, 20, 30, 40]
    #assert(#typeof(K) == #type [4] s32)

    // assignment requires exact size
    // (if your language reports a different diagnostic name, adjust expected error)
    var L: [3] s32 = K // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    // nested rectangular with integers
    const M = [[1, 2], [3, 4]]
    #assert(#typeof(M) == #type [2] [2] s32)
    #assert(M[1][0] == 3)
}

#test
{
    // jagged via local vars still invalid
    var x = [1, 2]
    var y = [3, 4, 5]
    var N = [x, y] // swc-expected-error {{sema_err_cannot_cast}}
}

const AB: [2] u32 = [1, 2]