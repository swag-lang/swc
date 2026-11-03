#global private

// The box itself can be present while its stored pointer is null.
func unboxPresentPointer(value: any)->*s32?
{
    return assume cast (*s32?, value)
}

#[Swag.Safety(.Assume, true)]
func unboxNullablePointer(value: any?)->*s32?
{
    return assume cast (*s32?, value)
}

#test
{
    let absent: *s32? = null
    Swag.require(unboxNullablePointer(absent) == null)
    Swag.require(unboxNullablePointer(null) == null)
    var value: s32 = 42
    Swag.require(unboxNullablePointer(&value) == &value)
    Swag.require(unboxPresentPointer(&value) == &value)
}
