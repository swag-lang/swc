#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func average(x: any)
{
    let tt = @kindof(x)
    @assert(tt == #typeof(s32))
}

//#[Swag.PrintBc]
#test
{
    average(0)
}
