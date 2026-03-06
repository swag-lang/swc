#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    const vv: any = null
    @assert(@dataof(vv) == null)
}
