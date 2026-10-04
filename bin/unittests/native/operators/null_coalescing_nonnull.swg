#global private

var FallbackCalls: u32

interface IValue
{
    mtd value()->u32
}

struct Value
{
    number: u32
}

#[Swag.Strict]
alias RequiredPointer = *s32

impl IValue for Value
{
    mtd impl value()->u32 => .number
}

func fallbackValue()->IValue?
{
    FallbackCalls += 1
    return null
}

#[Swag.Inline]
func selectedValue(value: IValue?)->u32 => (value orelse fallbackValue())!.value()

// A non-null left operand never evaluates its fallback. A nullable fallback must still be
// accepted, including when inline substitution specializes a nullable parameter to non-null.
#test
{
    var value = Value{42}
    let present: IValue = &value
    FallbackCalls = 0
    let resolved = present orelse fallbackValue()
    #assert(#typeof(resolved) == IValue)
    Swag.assert(resolved.value() == 42)
    Swag.assert(selectedValue(present) == 42)
    Swag.assert(FallbackCalls == 0)
}

#test
{
    var value           = 42
    let present         = &value
    let fallback: *s32? = null
    let resolved        = present orelse fallback
    #assert(#typeof(resolved) == *s32)
    Swag.assert(resolved[] == 42)
    Swag.assert((present orelse null)[] == 42)

    let aliasPointer  = cast(RequiredPointer) present
    let resolvedAlias = aliasPointer orelse fallback
    #assert(#typeof(resolvedAlias) == RequiredPointer)
    Swag.assert(resolvedAlias[] == 42)

    let text:   string  = "present"
    let noText: string? = null
    let resolvedText    = text orelse noText
    #assert(#typeof(resolvedText) == string)
    Swag.assert(resolvedText == "present")

    let values:  [2] u32         = [17, 42]
    let slice:   const [..] u32  = values
    let noSlice: const [..] u32? = null
    let resolvedSlice            = slice orelse noSlice
    #assert(#typeof(resolvedSlice) == const [..] u32)
    Swag.assert(resolvedSlice[1] == 42)
}
