#global fileprivate //


const A: [5] s32 = [1's32, 2, 3, 4, 5]
#assert(#typeof(A) == #type [5] s32)

const A1: [5] s32 = [1, 2, 3, 4, 5]
#assert(#typeof(A1) == #type [5] s32)

const Af: [2] f64 = [1.0'f64, 2.0]
#assert(#typeof(Af) == #type [2] f64)

const A2 = [1, true, 3]
#assert(A2[0] == 1)
#assert(A2[1] == true)
#assert(A2[2] == 3)

#test
{
    var x = 1
    var B: [3] s32 = [x, 2, 3]
    #assert(#typeof(B) == #type [3] s32)

    var C: [3] s32 = [x, 2, 3]
    #assert(#typeof(C) == #type [3] s32)

    var D: [2] f32 = [1.0'f32, cast(f32) 2]
    #assert(#typeof(D) == #type [2] f32)
    #assert(#typeof(D[0]) == f32)
    #assert(#typeof(D[1]) == f32)
    @assert(B[0] == 1)
    @assert(C[2] == 3)
    @assert(D[1] == 2.0)
}



const G: [2] f32 = [1.0, 2]
#assert(#typeof(G) == #type [2] f32)
#assert(#typeof(G[0]) == f32)
#assert(#typeof(G[1]) == f32)
#assert(G[0] == 1.0)
#assert(G[1] == 2.0)

const G1: [3] [1] f32 = [[1.0], [2.0], [3.0]]
#assert(#typeof(G1) == #type [3] [1] f32)
#assert(#typeof(G1[0]) == #type [1] f32)
#assert(#typeof(G1[0][0]) == f32)
#assert(G1[2][0] == 3.0)



const I: [2] s32 = [1, cast(s32) 2.2]
#assert(#typeof(I) == #type [2] s32)
#assert(#typeof(I[0]) == s32)
#assert(#typeof(I[1]) == s32)
#assert(I[1] == 2)


#test
{
    const K: [4] s32 = [10, 20, 30, 40]
    #assert(#typeof(K) == #type [4] s32)
    @assert(K[3] == 40)
}

#test
{
    const M: [2] [2] s32 = [[1, 2], [3, 4]]
    #assert(#typeof(M) == #type [2] [2] s32)
    #assert(M[1][0] == 3)
    @assert(M[0][1] == 2)
}


const AB: [2] u32 = [1, 2]
const AB1: [?] u32 = [1, 2]
#assert(#typeof(AB1) == #type [2] u32)

const AB2: [?] u32 = [[1], [2]]
#assert(#typeof(AB2) == #type [2] [1] u32)

// Aggregate array literal concretization.
#test
{
    var a = [10, 20, 30]
    #assert(#typeof(a) == #type [3] s32)
    @assert(a[0] == 10)
    @assert(a[2] == 30)
}

#test
{
    var a = [1'f64, 2, 3]
    #assert(#typeof(a) == #type [3] f64)
    @assert(a[2] == 3.0)
}

#test
{
    var a = [[1, 2], [3, 4]]
    #assert(#typeof(a) == #type [2][2] s32)
    @assert(a[0, 0] == 1)
    @assert(a[1, 1] == 4)
    #assert(@countof(a) == 2)
}

// Single value initialization.
#test
{
    var a: [40] s32 = 7
    @assert(a[0] == 7)
    @assert(a[39] == 7)
}

#test
{
    var a: [2, 2] bool = true
    @assert(a[0, 0] == true)
    @assert(a[1, 1] == true)
}

#test
{
    var a: [3] string = "hi"
    @assert(a[0] == "hi")
    @assert(a[2] == "hi")
}

#test
{
    var a: [2, 3] f32 = 1.5
    @assert(a[0, 0] == 1.5)
    @assert(a[1, 2] == 1.5)
}
