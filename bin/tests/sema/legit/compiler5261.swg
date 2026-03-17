#global fileprivate // swc-option sema-only
#global skip
#[Swag.Optimize(.All, false)]
#test
{
    let a = true
    var b = false
    let c = #ref &b
    let d = c orelse a
    @assert(d == true)
}
