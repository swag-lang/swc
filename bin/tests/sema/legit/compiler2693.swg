#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc, Swag.Optimize(.All, false)]
#test
{
    var scale: f64 = undefined
    scale = 1.0
    @assert(scale == 1.0)
}
