// swc-option suite-test

#global fileprivate

#[Swag.Macro]
func macroAdd(a: s32, b: s32)->s32 => a + b

#[Swag.Macro]
func macroCompute(a: s32, b: s32 = 1, c: s32 = 1)->s32
{
    let tmp: s32 = a + b
    return tmp + c
}

#test
{
    let base: s32 = 40

    @assert(macroAdd(base, 2) == 42)
    @assert(macroCompute(40) == 42)
    @assert(macroCompute(a: 20, c: 20, b: 2) == 42)
}