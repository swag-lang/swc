#global fileprivate // swc-option sema-only
#global skip
struct(T) AA {}

#test
{
    var v:  AA's32
    let ptr = #typeof(v)
    @assert(ptr.structName == "AA")
}
