#global private

const POINTER_TARGET = "relocatable-pointer-to-integer"
var pointerTarget = POINTER_TARGET.buffer

#[Swag.NoInline]
func literalPointerInteger()->u64 => cast(u64, POINTER_TARGET.buffer)

#[Swag.NoInline]
func runtimePointerInteger(pointer: const [*] u8)->u64 => cast(u64, pointer)

#[Swag.NoInline]
func forwardedPointerInteger()->u64 => literalPointerInteger()

#test
{
    var raw: u64  = 0x1234
    var ptr       = cast(*void, raw)
    var roundtrip = cast(u64, ptr)

    Swag.require(roundtrip == raw)
    Swag.require(ptr == cast(*void, roundtrip))
}

#test
{
    var raw: u64  = 0xABCD
    var ptr       = cast([*]u8, raw)
    var roundtrip = cast(u64, ptr)

    Swag.require(roundtrip == raw)
    Swag.require(ptr == cast([*]u8, roundtrip))
}

// Converting a literal address must use the loaded program's address in both backends.
#test
{
    let literal = literalPointerInteger()
    let runtime = runtimePointerInteger(pointerTarget)
    Swag.require(literal == runtime)
    Swag.require(forwardedPointerInteger() == runtime)
    Swag.require(cast(const [*] u8, literal) == pointerTarget)
}

// Absolute numeric pointers remain foldable constants.
#test
{
    const pointer = cast([*] u8, 0x1234'u64)
    const integer = cast(u64, pointer)
    Swag.require(integer == 0x1234)
}
