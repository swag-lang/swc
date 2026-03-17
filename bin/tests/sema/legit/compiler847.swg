#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var a: f32
    let b: s32 = 1
    a = cast() b
    @assert(a == 1)
}
