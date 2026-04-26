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

#[Swag.Operators(opEquals, opCompare)]
struct(T) GeneratedGenericBox
{
    value: T
}

#[Swag.Operators(opEquals, opCompare)]
struct(T) GeneratedGenericPair
{
    left, right: T
}

#[Swag.Operators(opEquals)]
struct GeneratedEqualsIgnoresUserCompare
{
    value: s32
}

impl GeneratedEqualsIgnoresUserCompare
{
    mtd const opCompare(other: const &GeneratedEqualsIgnoresUserCompare)->s32
    {
        return 0
    }
}

#[Swag.Operators(opCompare)]
struct GeneratedCompareOnly
{
    value: s32
}

struct EqualityOnlyField
{
    value: s32
}

impl EqualityOnlyField
{
    mtd const opEquals(other: const &EqualityOnlyField)->bool
    {
        return .value == other.value
    }
}

#[Swag.Operators(opEquals)]
struct GeneratedEqualityOnlyField
{
    field: EqualityOnlyField
}

struct NonComparableField
{
    value: s32
}

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedIgnoredField
{
    key: s32
    #[Swag.OperatorIgnore]
    cache: NonComparableField
}

#[Swag.Operators(opEquals, opCompare)]
struct(T) GeneratedGenericIgnoredField
{
    key: T
    #[Swag.OperatorIgnore]
    cache: NonComparableField
}

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedOnlyIgnoredFields
{
    #[Swag.OperatorIgnore]
    cache: NonComparableField
}

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedEmpty
{
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
    let a = GeneratedGenericBox's32{value: 3}
    let b = GeneratedGenericBox's32{value: 3}
    let c = GeneratedGenericBox's32{value: 4}

    @assert(a == b)
    @assert(a != c)
    @assert(a < c)
}

#test
{
    let a = GeneratedGenericBox'GeneratedPair{value: GeneratedPair{x: 1, y: 2}}
    let b = GeneratedGenericBox'GeneratedPair{value: GeneratedPair{x: 1, y: 2}}
    let c = GeneratedGenericBox'GeneratedPair{value: GeneratedPair{x: 2, y: 1}}

    @assert(a == b)
    @assert(a < c)
}

#test
{
    let a = GeneratedGenericPair's32{left: 1, right: 2}
    let b = GeneratedGenericPair's32{left: 1, right: 2}
    let c = GeneratedGenericPair's32{left: 1, right: 3}

    @assert(a == b)
    @assert(a < c)
}

#test
{
    let a = GeneratedEqualsIgnoresUserCompare{value: 7}
    let b = GeneratedEqualsIgnoresUserCompare{value: 7}
    let c = GeneratedEqualsIgnoresUserCompare{value: 9}

    @assert(a == b)
    @assert(a != c)
}

#test
{
    let a = GeneratedCompareOnly{value: 1}
    let b = GeneratedCompareOnly{value: 2}

    @assert(a < b)
    @assert((b <=> a) > 0)
}

#test
{
    let a = GeneratedEqualityOnlyField{field: EqualityOnlyField{value: 4}}
    let b = GeneratedEqualityOnlyField{field: EqualityOnlyField{value: 4}}
    let c = GeneratedEqualityOnlyField{field: EqualityOnlyField{value: 5}}

    @assert(a == b)
    @assert(a != c)
}

#test
{
    let a = GeneratedIgnoredField{key: 1, cache: NonComparableField{value: 10}}
    let b = GeneratedIgnoredField{key: 1, cache: NonComparableField{value: 20}}
    let c = GeneratedIgnoredField{key: 2, cache: NonComparableField{value: 10}}

    @assert(a == b)
    @assert((a <=> b) == 0)
    @assert(a < c)
}

#test
{
    let a = GeneratedGenericIgnoredField's32{key: 1, cache: NonComparableField{value: 10}}
    let b = GeneratedGenericIgnoredField's32{key: 1, cache: NonComparableField{value: 20}}
    let c = GeneratedGenericIgnoredField's32{key: 2, cache: NonComparableField{value: 10}}

    @assert(a == b)
    @assert((a <=> b) == 0)
    @assert(a < c)
}

#test
{
    let a = GeneratedOnlyIgnoredFields{cache: NonComparableField{value: 10}}
    let b = GeneratedOnlyIgnoredFields{cache: NonComparableField{value: 20}}

    @assert(a == b)
    @assert((a <=> b) == 0)
}

#test
{
    let a = GeneratedEmpty{}
    let b = GeneratedEmpty{}

    @assert(a == b)
    @assert((a <=> b) == 0)
}
