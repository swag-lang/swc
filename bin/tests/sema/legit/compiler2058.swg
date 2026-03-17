#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    let x = "toto"
    let y = "toto"
    @assert(@stringcmp(x, y))
    let z = "titi"
    @assert(!@stringcmp(x, z))
}
