#global private

#[Swag.Safety(.DynCast, true)]
func assumeRuntimeValue(target: typeinfo, source: any)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let view = cast #assume(target) source
}

#test
{
    assumeRuntimeValue(s64, 42's32)
}

#[Swag.Safety(.DynCast, true)]
func assumeRuntimeType(target, source: typeinfo)
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let type = cast #assume(target) source
}

#test
{
    assumeRuntimeType(s64, s32)
}

#[Swag.Safety(.DynCast, true)]
func assumeWrongConstantDescriptor()
{
    // swc-expected-error@(+1) {{safety_err_runtime}}
    let type = cast #assume(const *Swag.TypeInfoStruct) s32
}

#test
{
    assumeWrongConstantDescriptor()
}
