#global fileprivate
using Swag

struct GenericFlagPlain
{
    value: s32
}

struct(T, N: s32) GenericFlagBox
{
    values: [N] T
}

func(T, N: s32) genericFlagRepeat(value: T)->[N] T
{
    var result: [N] T
    for i in N do
        result[i] = value
    return result
}

const PLAIN_TYPE  = #typeof(GenericFlagPlain)
const STRUCT_TYPE = #typeof(GenericFlagBox'(u16, 3))
const FUNC_TYPE   = #typeof(genericFlagRepeat'(u16, 3))

#assert(!(PLAIN_TYPE.flags & TypeInfoFlags.Generic))
#assert(STRUCT_TYPE.flags & TypeInfoFlags.Generic)
#assert(FUNC_TYPE.flags & TypeInfoFlags.Generic)

#test
{
    @assert(!(PLAIN_TYPE.flags & TypeInfoFlags.Generic))
    @assert(STRUCT_TYPE.flags & TypeInfoFlags.Generic)
    @assert(FUNC_TYPE.flags & TypeInfoFlags.Generic)
}
