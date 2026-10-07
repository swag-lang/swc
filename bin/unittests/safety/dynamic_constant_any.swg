#global private

#[Swag.Safety(.Assume, true)]
func extractWrongConstantType()
{
    const value: any = 42's32
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let result = assume cast(s64, value)
}

#test
{
    extractWrongConstantType()
}
