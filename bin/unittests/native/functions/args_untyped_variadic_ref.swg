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
    if @kindof(values[0]) != VariadicReferencedValue do
        return false

    let value = cast(VariadicReferencedValue) values[0]
    return value.first == 11 and value.second == 22 and value.third == 33
}

#[Swag.NoInline]
func passVariadicReferencedValue(value: VariadicReferencedValue)->bool
{
    return variadicReferencedValueIsIntact(value)
}

#test
{
    let value: VariadicReferencedValue = {first: 11, second: 22, third: 33}
    @assert(passVariadicReferencedValue(value))
}
