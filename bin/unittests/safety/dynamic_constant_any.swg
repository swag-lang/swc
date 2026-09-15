#global private

#[Swag.Safety(.DynCast, true)]
func extractWrongConstantType()
{
    const value: any = 42's32
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let result = cast #assume(s64) value
}

#test
{
    extractWrongConstantType()
}
