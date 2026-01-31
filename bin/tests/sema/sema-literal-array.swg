#global internal

const At = [[1, 2],[3, 4, 5]] // swc-expected-error {{sema_err_cannot_cast}}

const A = [1's32, 2, 3, 4, 5]
#assert(#typeof(A) == #type [5] s32)

const Af = [1.0'f64, 2]
#assert(#typeof(Af) == #type [2] f64)

#test
{
    var x = 1
    var B = [x, 2, 3]
    #assert(#typeof(B) == #type [3] s32)

    var C = [x, 2, 3]

    var D = [1.0'f32, 2] // int literal must be casted to float
    #assert(#typeof(D) == #type [2] f32)
}

#test
{
    var E = [] // swc-expected-error {{sema_err_empty_array_literal}}
}

#test
{
    var F = ["hello", 1] // swc-expected-error {{sema_err_cannot_cast}}
}

const G = [1.0, 2]
#assert(#typeof(G) == #type [2] f32)
#assert(#typeof(G[0]) == f32)
#assert(#typeof(G[1]) == f32)
#assert(G[1] == 2)

const G1 = [[1.0], [2.0], [3.0]]
#assert(#typeof(G1) == #type [3] [1] f32)

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

const I = [1, cast(s32) 2.2]
#assert(#typeof(I) == #type [2] s32)

const J = [cast(f32) 1, cast(s32) 2.2] // swc-expected-error {{sema_err_ambiguous_array_type}}
//const K = [1, 2.2]