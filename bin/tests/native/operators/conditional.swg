#global fileprivate // 

#assert((true ? 10 : 20) == 10)
#assert((false ? 10 : 20) == 20)
#assert((true ? "true" : "false") == "true")
#assert((false ? "true" : "false") == "false")

#test
{
    const a = true ? 10's16 : 20's32
    #assert(#typeof(a) == s32)

    const b = false ? 10's16 : 20's32
    #assert(#typeof(b) == s32)
    #assert(b == 20)

    const c = true ? 1.0'f32 : 2.0'f64
    #assert(#typeof(c) == f64)

    const d = true ? 20's32 : 10's16
    #assert(#typeof(d) == s32)
    @assert(a == 10)
    @assert(b == 20)
    @assert(c == 1.0)
    @assert(d == 20)
}

#test
{
    var a = 0 ? 1 : 2
    @assert(a == 2)
}



namespace NC{}

#assert((true ? (false ? 1 : 2) : 3) == 2)
#assert((false ? 1 : (true ? 2 : 3)) == 2)

const VAL1 = 10
var var2 = 20
#assert((true ? VAL1 : var2) == 10)


