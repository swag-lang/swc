#global private

func titi(?: ...) {}
func tata(?: s32...) {}

func toto(?: s32, ?: ...) {}

func tutu(?: s32, ?: s32...) {}

alias AliasVariadicS32 = s32...
func variadicAliasTail(a: s32, values: AliasVariadicS32)->s32 => a + cast(s32, values.count)
func(T) genericVariadicAliasTail(value: T, values: AliasVariadicS32)->T => value

func semaTest001()
{
    Swag.assert(variadicAliasTail(1, 2, 3, 4) == 4)
    Swag.assert(genericVariadicAliasTail('a', 1, 2, 3, 4) == 'a')
}
