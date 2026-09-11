#global private
using Swag

interface IAliasValue
{
    mtd value()->u32
}

struct AliasValue
{
    number: u32
}

impl IAliasValue for AliasValue
{
    mtd impl value()->u32 => .number
}

#[Swag.Strict]
alias RequiredInterface = IAliasValue

#[Swag.Strict]
alias RequiredPointer   = const *u32

func chooseInterface(primary: RequiredInterface?, fallback: RequiredInterface)->RequiredInterface
{
    let chosen = primary orelse fallback
    #assert(#typeof(chosen) == RequiredInterface)
    return chosen
}

func choosePointer(primary: RequiredPointer?, fallback: RequiredPointer)->RequiredPointer
{
    let chosen = primary orelse fallback
    #assert(#typeof(chosen) == RequiredPointer)
    return chosen
}

#test
{
    var first    = AliasValue{number: 17}
    var second   = AliasValue{number: 29}
    let primary  = cast(RequiredInterface) cast(IAliasValue) &first
    let fallback = cast(RequiredInterface) cast(IAliasValue) &second
    Swag.assert((cast(IAliasValue) chooseInterface(primary, fallback)).value() == 17)
    Swag.assert((cast(IAliasValue) chooseInterface(null, fallback)).value() == 29)
}

#test
{
    var first:  u32 = 17
    var second: u32 = 29
    let primary     = cast(RequiredPointer) &first
    let fallback    = cast(RequiredPointer) &second
    Swag.assert(choosePointer(primary, fallback) == primary)
    Swag.assert(choosePointer(null, fallback) == fallback)
}

const PointerFallback = cast(RequiredPointer) 0x1234'u64
const PointerResolved = cast(RequiredPointer?) null orelse PointerFallback
#assert(#typeof(PointerResolved) == RequiredPointer)
#assert(PointerResolved == PointerFallback)

const PointerPresent = cast(RequiredPointer?) 0x5678'u64 orelse PointerFallback
#assert(#typeof(PointerPresent) == RequiredPointer)
#assert(PointerPresent == cast(RequiredPointer) 0x5678'u64)
