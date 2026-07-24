#global private
using Swag

func(T, N: s32) makeRepeated(value: T)->[N] T
{
    var result: [N] T
    for [i] in N do
        result[i] = value
    return result
}

const FUNC_INFO   = cast(const *Swag.TypeInfoFunc) #typeof(makeRepeated'(u16, 3))
const COUNT_VALUE = cast(#null const *s32) FUNC_INFO.generics[1].value

#assert(@countof(FUNC_INFO.generics) == 2)
#assert(FUNC_INFO.generics[0].name == "T")
#assert(FUNC_INFO.generics[0].pointedType == u16)
#assert(FUNC_INFO.generics[1].name == "N")
#assert(FUNC_INFO.generics[1].pointedType == s32)
#assert(COUNT_VALUE != null)
#assert(dref COUNT_VALUE == 3)
#assert(FUNC_INFO.returnType == #type [3] u16)

#test
{
    @assert(@countof(FUNC_INFO.generics) == 2)
    @assert(FUNC_INFO.generics[0].pointedType == u16)
    @assert(FUNC_INFO.generics[1].pointedType == s32)
    @assert(dref COUNT_VALUE == 3)
    @assert(FUNC_INFO.returnType == #type [3] u16)
}
