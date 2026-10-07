#global private

#[Swag.Safety(.Assume, true), Swag.NoInline]
func assumeRuntimeValue(target: typeinfo, source: any)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let view = assume cast(target, source)
    discard view
}

#test
{
    assumeRuntimeValue(s64, 42's32)
}

#[Swag.Safety(.Assume, true), Swag.NoInline]
func assumeRuntimeType(target, source: typeinfo)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let type = assume cast(target, source)
    discard type
}

#test
{
    assumeRuntimeType(s64, s32)
}

#[Swag.Safety(.Assume, true)]
func assumeWrongConstantDescriptor()
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let type = assume cast(const *Swag.TypeInfoStruct, s32)
    discard type
}

#test
{
    assumeWrongConstantDescriptor()
}
