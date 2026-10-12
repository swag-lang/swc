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

#test
{
    var storage = 37'u64
    let pointer = opaquePointer(&storage)
    Swag.assert(optionalPointer(pointer) == cast(u64, pointer))
    Swag.assert(optionalPointer(cast([*] void?, pointer)) == cast(u64, pointer))
    defer Swag.assert(optionalPointer(cast([*] void?, pointer)) == cast(u64, pointer))
    Swag.assert(optionalPointer(null) == 0)
    Swag.assert(optionalScalar(&storage) == 37)
    Swag.assert(optionalScalar(null) == 0)

    var values = [17'u32, 29]
    let slice: [..] u32 = values
    Swag.assert(optionalSlice(slice) == 17)
    Swag.assert(optionalSlice(null) == 0)

    let text: string = "allocator"
    Swag.assert(optionalString(text) == 9)
    Swag.assert(optionalString(null) == 0)
}
