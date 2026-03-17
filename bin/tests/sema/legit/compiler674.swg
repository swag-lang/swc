#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var a: f32
    var b: f64
    let c  = a + b
    @assert(#sizeof(c) == 8)
}
