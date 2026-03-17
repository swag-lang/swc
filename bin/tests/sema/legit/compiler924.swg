#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func average(x: any)
{
    let tx = cast(*string) @dataof(x)
    @assert(dref tx == "toto")
}

//#[Swag.PrintBc]
#test
{
    average("toto")
    average("toto")
}
