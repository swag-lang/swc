// 
#global private

#[Swag.Macro]
func macroAdd(a: s32, b: s32)->s32 => a + b

#[Swag.Macro]
func macroCompute(a: s32, b: s32 = 1, c: s32 = 1)->s32
{
    let tmp: s32 = a + b
    return tmp + c
}

// A mixin body expands in the caller's scope, so it can name caller locals directly.
#[Swag.Mixin]
func mixinBumpCaller()
{
    total += 1
}

// Macro add and compute with defaults
#test
{
    let base: s32 = 40

    @assert(macroAdd(base, 2) == 42)
    @assert(macroCompute(40) == 42)
    @assert(macroCompute(a: 20, c: 20, b: 2) == 42)
}

// Mixin resolves caller locals at expansion time
#test
{
    var total = 0
    mixinBumpCaller()
    mixinBumpCaller()
    @assert(total == 2)
}
