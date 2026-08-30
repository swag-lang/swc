#global private

struct VariadicReferencedValue
{
    first:  u64
    second: u64
    third:  u64
}

#[Swag.NoInline]
func variadicReferencedValueIsIntact(values: ...)->bool
{
    if Swag.kindOf(values[0]) != VariadicReferencedValue do
        return false

    let value = cast(VariadicReferencedValue) values[0]
    return value.first == 11 and value.second == 22 and value.third == 33
}

#[Swag.NoInline]
func passVariadicReferencedValue(value: VariadicReferencedValue)->bool
{
    return variadicReferencedValueIsIntact(value)
}

func runVariadicReferencedValue()->bool
{
    let value: VariadicReferencedValue = {first: 11, second: 22, third: 33}
    return passVariadicReferencedValue(value)
}

#test
{
    const result = #run runVariadicReferencedValue()
    #assert(result)
}
