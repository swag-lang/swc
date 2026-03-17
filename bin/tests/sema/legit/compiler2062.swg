#global fileprivate // swc-option sema-only
#global skip
#test
{
    let x = #typeof(s32)
    let y = #typeof(s32)
    let v = @typecmp(x, y, Swag.TypeCmpFlags.Strict)
    @assert(v)
}
