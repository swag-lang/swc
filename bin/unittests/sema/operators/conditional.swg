#global private

#assert((true ? 10 : 20) == 10)
#assert((false ? 10 : 20) == 20)
#assert((true ? "true" : "false") == "true")
#assert((false ? "true" : "false") == "false")

func semaTest001()
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
}

func semaTest002() { var a = 0 ? 1 : 2 }
func semaTest005() { var a = 0.0'f32 ? 1 : 2 }

namespace NC{}

#assert((true ? (false ? 1 : 2) : 3) == 2)
#assert((false ? 1 : (true ? 2 : 3)) == 2)

const VAL1 = 10
var var2 = 20
#assert((true ? VAL1 : var2) == 10)

func semaTest003()
{
    var A: #null *s32
    var C = A ? A : null
}

func semaTest004()
{
    func keepsTypedBranchWhenFunctionReturnBindsContext(flag: bool, bytes: const [..] u8)->s32
    {
        let fromTrue  = flag ? bytes[0] : 0
        let fromFalse = flag ? 0 : bytes[0]

        #assert(#typeof(fromTrue) == u8)
        #assert(#typeof(fromFalse) == u8)
        return 0
    }
}

func semaTest006()
{
    // Two typed branches settle the type on their own: the return type of the enclosing
    // function binds its 'return' expressions, not every conditional in its body.
    func keepsTypedBranchesWhenFunctionReturnBindsContext(flag: bool, values: const [*] s32, index: u32, other: s32)->u32
    {
        var fromIndex = flag ? values[index] : other
        var fromBoth  = flag ? values[index] : values[index + 1]
        let sum       = fromIndex + other
        var narrower  = flag ? 10's16 : other
        #assert(#typeof(fromIndex) == s32)
        #assert(#typeof(fromBoth) == s32)
        #assert(#typeof(narrower) == s32)
        #assert(#typeof(sum) == s32)

        // A binding that targets the conditional still settles unsized constants.
        var fromConstants: u8 = flag ? 1 : 2
        #assert(#typeof(flag ? 1 : 2) != u8)
        return cast(u32) fromIndex + fromConstants
    }
}

func semaTest007()
{
    // A '#run' block infers its type from the binding that targets it, not from the function
    // it sits in; without a binding, its constant is concretized on its own.
    func runBlocksInferFromTheirOwnBinding()->u32
    {
        var typed: u8 = #run { return 3 }
        var bare      = #run { return 3 }
        #assert(#typeof(typed) == u8)
        #assert(#typeof(bare) == s32)
        return cast(u32) typed + cast(u32) bare
    }
}
