#global fileprivate // swc-option suite-jit

struct Pair
{
    x: s32
    y: s32
}

#[Swag.Compiler]
var CGZero: s32

#[Swag.Compiler]
var CGPair: Pair = {x: 1, y: 2}

func updateCompilerGlobals()->s32
{
    CGZero = 11
    CGPair.x += 5
    CGPair.y += 7
    return CGZero + CGPair.x + CGPair.y
}

#test
{
    const V = #run updateCompilerGlobals()
    @assert(V == 26)
}
