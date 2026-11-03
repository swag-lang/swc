#global private

#[Swag.NoInline]
func pointerValue(value: [*] void)->u64 => cast(u64, value)

#[Swag.NoInline]
func opaquePointer(value: [*] void)->[*] void => value

// The argument is widened to the nullable parameter type before the body narrows it.
// Inlining must preserve that local proof when the caller's variable is non-null.
#[Swag.Inline]
func optionalPointer(value: [*] void?)->u64
{
    if not value do
        return 0
    return pointerValue(value)
}

#[Swag.NoInline]
func scalarValue(value: *u64)->u64 => value[]

#[Swag.Inline]
func optionalScalar(value: *u64?)->u64
{
    if not value do
        return 0
    return scalarValue(value)
}

#[Swag.NoInline]
func firstValue(values: [..] u32)->u32 => values[0]

#[Swag.Inline]
func optionalSlice(values: [..] u32?)->u32
{
    if not values do
        return 0
    return firstValue(values)
}

#[Swag.NoInline]
func stringLength(value: string)->u64 => value.count

#[Swag.Inline]
func optionalString(value: string?)->u64
{
    if not value do
        return 0
    return stringLength(value)
}

#[Swag.Inline]
func copyPointers(destination: [*] void?, source: const [*] void?, size: u64)
{
    if size do
        Swag.memcpy(unwrap destination, unwrap source, size)
}

func optionalSlicePointer(source: const [..] u8)
{
    copyPointers(null, source.buffer + 1, 0)
}

#test
{
    var storage = 37'u64
    let pointer = opaquePointer(&storage)
    Swag.require(optionalPointer(pointer) == cast(u64, pointer))
    Swag.require(optionalPointer(cast([*] void?, pointer)) == cast(u64, pointer))
    defer Swag.require(optionalPointer(cast([*] void?, pointer)) == cast(u64, pointer))
    Swag.require(optionalPointer(null) == 0)
    Swag.require(optionalScalar(&storage) == 37)
    Swag.require(optionalScalar(null) == 0)

    var values = [17'u32, 29]
    let slice: [..] u32 = values
    Swag.require(optionalSlice(slice) == 17)
    Swag.require(optionalSlice(null) == 0)

    let text: string = "allocator"
    Swag.require(optionalString(text) == 9)
    Swag.require(optionalString(null) == 0)

    var bytes = [1'u8, 2]
    let byteSlice: [..] u8 = bytes
    optionalSlicePointer(byteSlice)
}
