#global fileprivate

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedPair
{
    x, y: s32
}

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedOuter
{
    pair: GeneratedPair
    tag:  s32
}

#[Swag.Operators(opEquals)]
struct GeneratedEqualsFromCompare
{
    value: s32
}

#[Swag.Operators(opEquals, opCompare)]
struct(T) GeneratedGenericBox
{
    value: T
}

impl GeneratedEqualsFromCompare
{
    mtd const opCompare(other: const &GeneratedEqualsFromCompare)->s32
    {
        return .value <=> other.value
    }
}

#test
{
    let a = GeneratedPair{x: 1, y: 2}
    let b = GeneratedPair{x: 1, y: 2}
    let c = GeneratedPair{x: 1, y: 3}

    @assert(a == b)
    @assert(a != c)
    @assert((a <=> c) < 0)
    @assert(c > a)
}

#test
{
    let a = GeneratedOuter{pair: GeneratedPair{x: 1, y: 2}, tag: 10}
    let b = GeneratedOuter{pair: GeneratedPair{x: 1, y: 2}, tag: 10}
    let c = GeneratedOuter{pair: GeneratedPair{x: 1, y: 2}, tag: 11}

    @assert(a == b)
    @assert(a < c)
}

#test
{
    let a = GeneratedEqualsFromCompare{value: 7}
    let b = GeneratedEqualsFromCompare{value: 7}
    let c = GeneratedEqualsFromCompare{value: 9}

    @assert(a == b)
    @assert(a != c)
}

#test
{
    let a = GeneratedGenericBox's32{value: 7}
    let b = GeneratedGenericBox's32{value: 7}
    let c = GeneratedGenericBox's32{value: 9}

    @assert(a == b)
    @assert(a != c)
    @assert(a < c)
}
