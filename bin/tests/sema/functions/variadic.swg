#global fileprivate

func titi(a: ...) {}
func tata(a: s32...) {}

func toto(a: s32, b: ...) {}

func tutu(a: s32, b: s32...) {}

alias AliasVariadicS32 = s32...
func variadicAliasTail(a: s32, values: AliasVariadicS32)->s32 => a + cast(s32) @countof(values)
func(T) genericVariadicAliasTail(value: T, values: AliasVariadicS32)->T => value

#test
{
    @assert(variadicAliasTail(1, 2, 3, 4) == 4)
    @assert(genericVariadicAliasTail('a', 1, 2, 3, 4) == 'a')
}
